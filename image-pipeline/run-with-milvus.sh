#!/bin/bash

clear
echo "=============================================="
echo "   COMPLETE PIPELINE WITH MILVUS & FASTAPI"
echo "=============================================="
echo ""

# Check FastAPI first
echo "[1/7] Checking FastAPI connection..."
if ! curl -s -f http://localhost:8003 > /dev/null; then
    echo "✗ FastAPI is not running on port 8003!"
    echo "Please start your FastAPI service first."
    exit 1
fi
echo "✓ FastAPI is running on port 8003"

# Start infrastructure
echo "[2/7] Starting infrastructure..."
docker compose up -d zookeeper kafka postgres minio minio-init etcd

# Wait for basic services
echo "[3/7] Waiting for services (30s)..."
sleep 30

# Start Milvus
echo "[4/7] Starting Milvus..."
docker compose up -d milvus
echo "  Waiting for Milvus to initialize (60s)..."
sleep 60

# Initialize Milvus collection
echo "[5/7] Initializing Milvus collection..."
docker compose build milvus-init
docker compose run --rm milvus-init

# Build and start Rust backend
echo "[6/7] Building and starting Rust backend..."
docker compose build rust-backend
docker compose up -d rust-backend
sleep 10

# Run Python producer
echo "[7/7] Sending images through pipeline..."
docker compose build python-producer
docker compose run --rm python-producer

# Show results
echo ""
echo "=============================================="
echo "   RESULTS"
echo "=============================================="

# Rust stats
echo "Rust Backend Stats:"
curl -s http://localhost:3000/stats | python3 -m json.tool

# Database stats
echo ""
echo "Database Statistics:"
docker exec postgres psql -U postgres -d imagedb -t -c "SELECT * FROM processing_stats;"

echo ""
echo "=============================================="
echo "   SERVICES STATUS"
echo "=============================================="
echo ""
echo "✓ FastAPI:    http://localhost:8003"
echo "✓ MinIO:      http://localhost:9001 (minioadmin/minioadmin123)"
echo "✓ Milvus:     localhost:19530"
echo "✓ PostgreSQL: localhost:5432"
echo "✓ Rust API:   http://localhost:3000/stats"
echo ""
echo "=============================================="
