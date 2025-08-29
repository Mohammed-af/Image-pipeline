-- Enhanced schema for dual embeddings
CREATE TABLE IF NOT EXISTS image_records (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    filename VARCHAR(255) NOT NULL,
    minio_path TEXT,
    milvus_id VARCHAR(100) UNIQUE,        -- Image embedding ID in Milvus
    text_milvus_id VARCHAR(100) UNIQUE,   -- Text embedding ID in Milvus
    embedding_dim INTEGER,
    file_size BIGINT,
    width INTEGER,
    height INTEGER,
    format VARCHAR(50),
    caption TEXT,                         -- Generated caption for text embedding
    processed_at TIMESTAMP DEFAULT NOW(),
    metadata JSONB
);

-- Indexes
CREATE INDEX idx_filename ON image_records(filename);
CREATE INDEX idx_milvus_id ON image_records(milvus_id);
CREATE INDEX idx_text_milvus_id ON image_records(text_milvus_id);
CREATE INDEX idx_processed_at ON image_records(processed_at DESC);

-- Enhanced statistics view
CREATE VIEW dual_embedding_stats AS
SELECT 
    COUNT(*) as total_images,
    COUNT(milvus_id) as image_embeddings,
    COUNT(text_milvus_id) as text_embeddings,
    SUM(file_size) as total_bytes,
    AVG(embedding_dim) as avg_embedding_dim,
    MAX(processed_at) as last_processed
FROM image_records;

GRANT ALL ON ALL TABLES IN SCHEMA public TO postgres;
