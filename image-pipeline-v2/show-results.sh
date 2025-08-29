#!/bin/bash

clear
echo "================================================"
echo "         PIPELINE RESULTS DASHBOARD"
echo "================================================"

# 1. Service Status
echo -e "\n📦 SERVICE STATUS:"
echo "-------------------"
docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "NAME|rust|milvus|postgres|minio|kafka" | head -10

# 2. Rust Backend Stats
echo -e "\n📊 PROCESSING STATS:"
echo "-------------------"
curl -s http://localhost:3000/stats 2>/dev/null | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(f'  Messages Processed: {data.get(\"messages_processed\", 0)}')
    print(f'  Image Embeddings: {data.get(\"image_embeddings_stored\", 0)}')
    print(f'  Text Embeddings: {data.get(\"text_embeddings_stored\", 0)}')
    print(f'  MinIO Uploads: {data.get(\"minio_uploads\", 0)}')
    print(f'  Errors: {data.get(\"errors\", 0)}')
    print(f'  Status: {data.get(\"status\", \"Unknown\")}')
except:
    print('  Stats not available')
"

# 3. Database Records
echo -e "\n💾 DATABASE RECORDS:"
echo "-------------------"
docker exec postgres psql -U postgres -d imagedb -t -c "
SELECT 
    COUNT(*) as total,
    COUNT(DISTINCT milvus_id) as image_vectors,
    COUNT(DISTINCT text_milvus_id) as text_vectors
FROM image_records;" 2>/dev/null || echo "  Database not accessible"

# 4. Recent Files
echo -e "\n📁 RECENT FILES PROCESSED:"
echo "--------------------------"
docker exec postgres psql -U postgres -d imagedb -t -c "
SELECT filename, caption, processed_at 
FROM image_records 
ORDER BY processed_at DESC 
LIMIT 5;" 2>/dev/null || echo "  No records found"

# 5. Access Points
echo -e "\n🌐 ACCESS POINTS:"
echo "-----------------"
echo "  MinIO Console:  http://localhost:9001 (minioadmin/minioadmin123)"
echo "  Rust API:       http://localhost:3000/stats"
echo "  PostgreSQL:     localhost:5432 (postgres/postgres123)"
echo "  Milvus:         localhost:19530"

echo -e "\n================================================\n"
