#!/bin/bash

clear
echo "=============================================="
echo "     🎉 COMPLETE PIPELINE RESULTS 🎉"
echo "=============================================="
echo ""

# 1. Rust Backend Status
echo "📡 RUST BACKEND API:"
echo "-------------------"
echo -n "Health: "
curl -s http://localhost:3000/health
echo ""
echo "Stats:"
curl -s http://localhost:3000/stats 2>/dev/null | python3 -c "
import sys, json
try:
    data = json.loads(sys.stdin.read())
    print(f'  Messages Processed: {data.get(\"messages_processed\", 0)}')
    print(f'  Image Embeddings: {data.get(\"image_embeddings_stored\", 0)}')
    print(f'  Text Embeddings: {data.get(\"text_embeddings_stored\", 0)}')
    print(f'  MinIO Uploads: {data.get(\"minio_uploads\", 0)}')
    print(f'  PostgreSQL Inserts: {data.get(\"postgres_inserts\", 0)}')
    print(f'  Status: {data.get(\"status\", \"Unknown\")}')
    print(f'  Last Processed: {data.get(\"last_processed\", \"Never\")}')
except Exception as e:
    print(f'  Raw response: {sys.stdin.read()}')
" || echo "  Could not parse stats"

# 2. PostgreSQL Database
echo ""
echo "💾 POSTGRESQL DATABASE:"
echo "----------------------"
docker exec postgres psql -U postgres -d imagedb -c "
SELECT 
    COUNT(*) as total_images,
    COUNT(DISTINCT milvus_id) as image_vectors,
    COUNT(DISTINCT text_milvus_id) as text_vectors,
    AVG(embedding_dim) as avg_embedding_dim
FROM image_records;" 2>/dev/null || echo "No data in database"

echo ""
echo "Recent Images Processed:"
docker exec postgres psql -U postgres -d imagedb -c "
SELECT 
    filename,
    caption,
    processed_at
FROM image_records 
ORDER BY processed_at DESC 
LIMIT 5;" 2>/dev/null || echo "No records"

# 3. MinIO Storage
echo ""
echo "📦 MINIO STORAGE:"
echo "----------------"
echo "Total objects in bucket:"
docker exec minio mc ls myminio/images 2>/dev/null | wc -l || echo "0"

# 4. Kafka Status
echo ""
echo "📨 KAFKA:"
echo "---------"
echo "Topics:"
docker exec kafka kafka-topics --list --bootstrap-server localhost:9092 2>/dev/null | head -5

# 5. Service Summary
echo ""
echo "✅ SERVICES RUNNING:"
echo "-------------------"
docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "NAME|rust-backend|kafka|postgres|minio|milvus" | head -10

echo ""
echo "=============================================="
echo "         🌐 ACCESS POINTS"
echo "=============================================="
echo ""
echo "📊 Rust Backend API:  http://localhost:3000/stats"
echo "🗄️  MinIO Console:    http://localhost:9001"
echo "                      Username: minioadmin"
echo "                      Password: minioadmin123"
echo "🔍 PostgreSQL:        psql -h localhost -U postgres -d imagedb"
echo "                      Password: postgres123"
echo ""
echo "=============================================="
