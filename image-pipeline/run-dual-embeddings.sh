#!/bin/bash

clear
echo "=============================================="
echo "   PIPELINE WITH DUAL EMBEDDINGS"
echo "   Text + Image from FastAPI"
echo "=============================================="
echo ""

# Test FastAPI endpoints
echo "[1/7] Testing FastAPI endpoints..."
./test-dual-endpoints.sh

if [ $? -ne 0 ]; then
    echo "✗ FastAPI endpoints not working!"
    exit 1
fi

# Start infrastructure
echo ""
echo "[2/7] Starting infrastructure..."
docker compose up -d zookeeper kafka postgres minio minio-init etcd

# Wait
echo "[3/7] Waiting for services (30s)..."
sleep 30

# Start Milvus
echo "[4/7] Starting Milvus..."
docker compose up -d milvus
sleep 60

# Initialize Milvus with dual collections
echo "[5/7] Creating Milvus collections..."
docker compose build milvus-init
docker compose run --rm milvus-init

# Build and start Rust backend
echo "[6/7] Starting Rust backend..."
docker compose build rust-backend
docker compose up -d rust-backend
sleep 10

# Run enhanced producer
echo "[7/7] Processing images with dual embeddings..."
docker compose build python-producer
docker compose run --rm python-producer

# Show results
echo ""
echo "=============================================="
echo "   RESULTS"
echo "=============================================="

curl -s http://localhost:3000/stats | python3 -m json.tool

echo ""
docker exec postgres psql -U postgres -d imagedb -c "
SELECT filename, caption, milvus_id, text_milvus_id 
FROM image_records 
ORDER BY processed_at DESC LIMIT 5;"

echo ""
echo "=============================================="
echo "✓ Dual embeddings pipeline complete!"
echo "  - Image embeddings in Milvus"
echo "  - Text embeddings in Milvus"
echo "  - Both linked in PostgreSQL"
echo "=============================================="
