#!/bin/bash

echo "========================================"
echo "    COMPLETE DATABASE CHECK"
echo "========================================"
echo ""

# 1. PostgreSQL
echo "📊 POSTGRESQL DATABASE"
echo "------------------------"
docker exec postgres psql -U postgres -d imagedb -c "
SELECT 
    COUNT(*) as total_records,
    COUNT(DISTINCT milvus_id) as unique_image_vectors,
    COUNT(DISTINCT text_milvus_id) as unique_text_vectors,
    SUM(file_size)/1024/1024 as total_mb,
    MAX(processed_at) as last_processed
FROM image_records;"

echo ""
echo "Recent records:"
docker exec postgres psql -U postgres -d imagedb -c "
SELECT 
    filename,
    LENGTH(milvus_id) as milvus_id_len,
    LENGTH(text_milvus_id) as text_id_len,
    embedding_dim,
    processed_at
FROM image_records 
ORDER BY processed_at DESC 
LIMIT 5;"

# 2. MinIO Object Storage
echo ""
echo "📦 MINIO OBJECT STORAGE"
echo "------------------------"
docker exec minio sh -c "
mc alias set local http://localhost:9000 minioadmin minioadmin123 2>/dev/null
echo 'Total objects:'
mc ls local/images 2>/dev/null | wc -l
echo ''
echo 'Recent files:'
mc ls local/images 2>/dev/null | tail -5
echo ''
echo 'Storage size:'
mc du local/images 2>/dev/null
"

# 3. Milvus Vector Database
echo ""
echo "🔍 MILVUS VECTOR DATABASE"
echo "------------------------"
python3 << 'PYTHON'
try:
    from pymilvus import connections, Collection, utility
    
    connections.connect(host="localhost", port=19530, timeout=5)
    
    collections = utility.list_collections()
    print(f"Collections: {collections}")
    
    for coll_name in collections:
        try:
            coll = Collection(coll_name)
            coll.load()
            print(f"\n{coll_name}:")
            print(f"  Vectors stored: {coll.num_entities}")
            
            # Get schema info
            for field in coll.schema.fields:
                if field.name == "embedding":
                    print(f"  Embedding dimension: {field.params.get('dim', 'unknown')}")
                    break
        except Exception as e:
            print(f"  Error loading {coll_name}: {e}")
            
except ImportError:
    print("pymilvus not installed. Install with: pip install pymilvus")
except Exception as e:
    print(f"Cannot connect to Milvus: {e}")
PYTHON

# 4. Kafka Topics
echo ""
echo "📨 KAFKA TOPICS"
echo "------------------------"
docker exec kafka kafka-topics --list --bootstrap-server localhost:9092 2>/dev/null

echo ""
echo "Topic details:"
docker exec kafka kafka-consumer-groups --bootstrap-server localhost:9092 --all-groups --describe 2>/dev/null | head -20

# 5. Cross-reference check
echo ""
echo "🔗 DATA CONSISTENCY CHECK"
echo "------------------------"
docker exec postgres psql -U postgres -d imagedb -t -c "
WITH stats AS (
    SELECT 
        COUNT(*) as pg_records,
        COUNT(DISTINCT milvus_id) as pg_milvus_refs,
        COUNT(DISTINCT minio_path) as pg_minio_refs
    FROM image_records
)
SELECT 
    'PostgreSQL records: ' || pg_records || E'\n' ||
    'Milvus references: ' || pg_milvus_refs || E'\n' ||
    'MinIO references: ' || pg_minio_refs
FROM stats;"

echo ""
echo "========================================"
