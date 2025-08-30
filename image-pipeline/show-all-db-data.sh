#!/bin/bash

echo "=============================================="
echo "     COMPLETE POSTGRESQL DATABASE DUMP"
echo "=============================================="
echo ""

# Database structure
echo "DATABASE STRUCTURE:"
echo "-------------------"
docker exec postgres psql -U postgres -d imagedb -c "\dt+"

echo ""
echo "TABLE SCHEMA:"
echo "-------------"
docker exec postgres psql -U postgres -d imagedb -c "\d image_records"

echo ""
echo "=============================================="
echo "ALL RECORDS IN DATABASE:"
echo "=============================================="
echo ""

# Show all records with all fields
docker exec postgres psql -U postgres -d imagedb -c "
SELECT 
    id,
    filename,
    minio_path,
    milvus_id,
    text_milvus_id,
    embedding_dim,
    file_size,
    width,
    height,
    format,
    caption,
    processed_at,
    metadata::text
FROM image_records
ORDER BY processed_at DESC;"

echo ""
echo "=============================================="
echo "DETAILED VIEW (First 3 records):"
echo "=============================================="
echo ""

# Show detailed view of first few records
docker exec postgres psql -U postgres -d imagedb -c "
SELECT * FROM image_records ORDER BY processed_at DESC LIMIT 3 \gx"

echo ""
echo "=============================================="
echo "DATABASE STATISTICS:"
echo "=============================================="
echo ""

docker exec postgres psql -U postgres -d imagedb -c "
SELECT 
    'Total Records' as metric, COUNT(*)::text as value
FROM image_records
UNION ALL
SELECT 
    'Unique Files', COUNT(DISTINCT filename)::text
FROM image_records
UNION ALL
SELECT 
    'With Image Embeddings', COUNT(milvus_id)::text
FROM image_records
UNION ALL
SELECT 
    'With Text Embeddings', COUNT(text_milvus_id)::text
FROM image_records
UNION ALL
SELECT 
    'Total Size (MB)', (SUM(file_size)/1024/1024)::text
FROM image_records
UNION ALL
SELECT 
    'First Processed', MIN(processed_at)::text
FROM image_records
UNION ALL
SELECT 
    'Last Processed', MAX(processed_at)::text
FROM image_records;"

echo ""
echo "=============================================="
echo "EXPORT OPTIONS:"
echo "=============================================="
echo ""
echo "To export all data to CSV:"
echo "docker exec postgres psql -U postgres -d imagedb -c \"\copy image_records TO '/tmp/all_records.csv' CSV HEADER\""
echo "docker cp postgres:/tmp/all_records.csv ./all_records.csv"
echo ""
echo "To connect directly to PostgreSQL:"
echo "docker exec -it postgres psql -U postgres -d imagedb"
echo ""
