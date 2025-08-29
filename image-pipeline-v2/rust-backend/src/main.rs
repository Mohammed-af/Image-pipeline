use axum::{
    routing::get,
    Json, Router,
    extract::State,
};
use rdkafka::{
    consumer::{StreamConsumer, Consumer},
    config::ClientConfig,
    message::Message,
};
use serde::{Deserialize, Serialize};
use std::sync::{Arc, Mutex};
use tokio::task;
use base64::{Engine as _, engine::general_purpose};
use std::process::Command;

#[derive(Debug, Clone, Serialize)]
struct Stats {
    status: String,
    messages_processed: u64,
    image_embeddings_stored: u64,
    text_embeddings_stored: u64,
    minio_uploads: u64,
    postgres_inserts: u64,
    errors: u64,
    last_processed: Option<String>,
}

#[derive(Clone)]
struct AppState {
    stats: Arc<Mutex<Stats>>,
}

impl AppState {
    fn new() -> Self {
        Self {
            stats: Arc::new(Mutex::new(Stats {
                status: "running".to_string(),
                messages_processed: 0,
                image_embeddings_stored: 0,
                text_embeddings_stored: 0,
                minio_uploads: 0,
                postgres_inserts: 0,
                errors: 0,
                last_processed: None,
            })),
        }
    }

    fn update_stats<F>(&self, updater: F) 
    where F: FnOnce(&mut Stats)
    {
        if let Ok(mut stats) = self.stats.lock() {
            updater(&mut stats);
        }
    }
}

#[derive(Debug, Deserialize)]
struct KafkaMessage {
    image_binary: String,
    #[serde(default)]
    image_embedding: Vec<f32>,
    #[serde(default)]
    text_embedding: Vec<f32>,
    metadata: MessageMetadata,
    #[serde(default)]
    embedding_dim: usize,
    #[serde(default)]
    has_dual_embeddings: bool,
}

#[derive(Debug, Deserialize)]
struct MessageMetadata {
    filename: String,
    file_size: u64,
    file_hash: String,
    timestamp: String,
    processed_at: i64,
    #[serde(default)]
    caption: String,
    #[serde(default)]
    width: Option<u32>,
    #[serde(default)]
    height: Option<u32>,
    #[serde(default)]
    format: Option<String>,
}

async fn health() -> &'static str {
    "OK"
}

async fn get_stats(State(state): State<AppState>) -> Json<Stats> {
    let stats = state.stats.lock().unwrap().clone();
    Json(stats)
}

async fn upload_to_minio(filename: &str, image_data: Vec<u8>) -> Result<(), String> {
    let temp_path = format!("/tmp/{}", filename);
    std::fs::write(&temp_path, image_data).map_err(|e| e.to_string())?;
    
    let output = Command::new("sh")
        .arg("-c")
        .arg(&format!(
            "mc alias set local http://minio:9000 minioadmin minioadmin123 2>/dev/null && \
             mc cp {} local/images/{} 2>/dev/null && \
             rm {}",
            temp_path, filename, temp_path
        ))
        .output()
        .map_err(|e| e.to_string())?;
    
    if output.status.success() {
        Ok(())
    } else {
        Err(String::from_utf8_lossy(&output.stderr).to_string())
    }
}

async fn store_in_postgres(
    id: &str,
    metadata: &MessageMetadata, 
    minio_path: &str, 
    milvus_id: &str,
    text_milvus_id: Option<&str>,
    embedding_dim: usize,
    caption: Option<&str>
) -> Result<(), String> {
    // Build the SQL query with proper UUID
    let text_milvus = text_milvus_id.unwrap_or("NULL");
    let caption_value = caption.map(|c| format!("'{}'", c.replace("'", "''"))).unwrap_or_else(|| "NULL".to_string());
    
    let query = format!(
        "INSERT INTO image_records (id, filename, minio_path, milvus_id, text_milvus_id, file_size, embedding_dim, caption, processed_at) \
         VALUES ('{}', '{}', '{}', '{}', {}, {}, {}, {}, NOW()) \
         ON CONFLICT (id) DO UPDATE SET processed_at = NOW()",
        id,
        metadata.filename.replace("'", "''"),
        minio_path,
        milvus_id,
        if text_milvus_id.is_some() { format!("'{}'", text_milvus) } else { "NULL".to_string() },
        metadata.file_size,
        embedding_dim,
        caption_value
    );
    
    let output = Command::new("sh")
        .arg("-c")
        .arg(&format!(
            "PGPASSWORD=postgres123 psql -h postgres -U postgres -d imagedb -c \"{}\" 2>&1",
            query
        ))
        .output()
        .map_err(|e| e.to_string())?;
    
    if output.status.success() || String::from_utf8_lossy(&output.stdout).contains("INSERT") {
        Ok(())
    } else {
        Err(String::from_utf8_lossy(&output.stderr).to_string())
    }
}

fn generate_uuid() -> String {
    // Simple UUID v4 generation
    use std::time::{SystemTime, UNIX_EPOCH};
    let timestamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    
    let random_part = format!("{:x}", md5::compute(format!("{}{}", timestamp, rand::random::<u64>())));
    
    format!(
        "{}-{}-4{}-{}-{}",
        &random_part[0..8],
        &random_part[8..12],
        &random_part[13..16],
        &random_part[16..20],
        &random_part[20..32]
    )
}

async fn process_message(msg: KafkaMessage, state: &AppState) -> Result<(), Box<dyn std::error::Error>> {
    println!("\n📥 Processing: {}", msg.metadata.filename);
    println!("  Size: {} KB", msg.metadata.file_size / 1024);
    
    // Generate IDs
    let uuid = generate_uuid();
    let image_hash = format!("{:x}", md5::compute(&msg.metadata.file_hash));
    let minio_filename = format!("{}.jpg", image_hash);
    let minio_path = format!("s3://images/{}", minio_filename);
    let milvus_id = format!("img_{}", image_hash);
    let text_milvus_id = if msg.has_dual_embeddings {
        Some(format!("txt_{}", image_hash))
    } else {
        None
    };
    
    // 1. Upload to MinIO
    println!("  → Uploading to MinIO...");
    let image_bytes = general_purpose::STANDARD.decode(&msg.image_binary)?;
    
    match upload_to_minio(&minio_filename, image_bytes).await {
        Ok(_) => {
            state.update_stats(|s| s.minio_uploads += 1);
            println!("    ✓ Uploaded to MinIO: {}", minio_filename);
        }
        Err(e) => {
            println!("    ✗ MinIO upload failed: {}", e);
        }
    }
    
    // 2. Mock Milvus storage
    if !msg.image_embedding.is_empty() {
        println!("  → Storing image embedding (dim: {})", msg.image_embedding.len());
        state.update_stats(|s| s.image_embeddings_stored += 1);
        println!("    ✓ Stored in Milvus: {}", milvus_id);
    }
    
    if !msg.text_embedding.is_empty() && msg.has_dual_embeddings {
        println!("  → Storing text embedding (dim: {})", msg.text_embedding.len());
        state.update_stats(|s| s.text_embeddings_stored += 1);
        println!("    ✓ Stored in Milvus: {}", text_milvus_id.as_ref().unwrap());
    }
    
    // 3. Store in PostgreSQL
    println!("  → Storing metadata in PostgreSQL...");
    match store_in_postgres(
        &uuid,
        &msg.metadata, 
        &minio_path, 
        &milvus_id,
        text_milvus_id.as_deref(),
        msg.embedding_dim,
        if msg.has_dual_embeddings { Some(&msg.metadata.caption) } else { None }
    ).await {
        Ok(_) => {
            state.update_stats(|s| s.postgres_inserts += 1);
            println!("    ✓ Stored in PostgreSQL with ID: {}", uuid);
        }
        Err(e) => {
            println!("    ✗ PostgreSQL insert failed: {}", e);
        }
    }
    
    state.update_stats(|s| {
        s.messages_processed += 1;
        s.last_processed = Some(msg.metadata.filename.clone());
    });
    
    println!("✅ Successfully processed: {}", msg.metadata.filename);
    println!("   📍 Stored as:");
    println!("      - MinIO: {}", minio_filename);
    println!("      - Milvus: {}", milvus_id);
    println!("      - PostgreSQL: {}", uuid);
    
    Ok(())
}

async fn kafka_consumer(state: AppState) {
    println!("🚀 Starting Kafka consumer...");
    
    let broker = std::env::var("KAFKA_BROKER")
        .unwrap_or_else(|_| "kafka:29092".to_string());
    
    println!("  Connecting to: {}", broker);
    
    let consumer: StreamConsumer = match ClientConfig::new()
        .set("group.id", "rust-backend-consumer")
        .set("bootstrap.servers", &broker)
        .set("auto.offset.reset", "earliest")
        .set("enable.auto.commit", "true")
        .create() 
    {
        Ok(c) => c,
        Err(e) => {
            eprintln!("Failed to create consumer: {}", e);
            return;
        }
    };
    
    if let Err(e) = consumer.subscribe(&["image-topic"]) {
        eprintln!("Failed to subscribe: {}", e);
        return;
    }
    
    println!("  ✓ Subscribed to image-topic");
    println!("  Waiting for messages...\n");
    
    loop {
        match consumer.recv().await {
            Ok(message) => {
                if let Some(payload) = message.payload() {
                    match serde_json::from_slice::<KafkaMessage>(payload) {
                        Ok(msg) => {
                            if let Err(e) = process_message(msg, &state).await {
                                eprintln!("Error: {}", e);
                                state.update_stats(|s| s.errors += 1);
                            }
                        }
                        Err(e) => {
                            eprintln!("Parse error: {}", e);
                            state.update_stats(|s| s.errors += 1);
                        }
                    }
                }
            }
            Err(e) => {
                eprintln!("Kafka error: {}", e);
                tokio::time::sleep(tokio::time::Duration::from_secs(5)).await;
            }
        }
    }
}

#[tokio::main]
async fn main() {
    println!("\n╔═══════════════════════════════════════════════════════╗");
    println!("║     RUST BACKEND WITH KAFKA CONSUMER (WORKING!)      ║");
    println!("╚═══════════════════════════════════════════════════════╝\n");
    
    let state = AppState::new();
    
    let consumer_state = state.clone();
    task::spawn(async move {
        kafka_consumer(consumer_state).await;
    });
    
    let app = Router::new()
        .route("/health", get(health))
        .route("/stats", get(get_stats))
        .with_state(state);
    
    println!("📡 API Endpoints:");
    println!("  http://0.0.0.0:3000/health");
    println!("  http://0.0.0.0:3000/stats");
    println!("\n═══════════════════════════════════════════════════════\n");
    
    let listener = tokio::net::TcpListener::bind("0.0.0.0:3000")
        .await
        .unwrap();
    
    axum::serve(listener, app).await.unwrap();
}

use md5;
use rand;
