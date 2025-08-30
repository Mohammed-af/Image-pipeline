#!/bin/bash

# Complete Pipeline Test Script (CPU Mode)
echo "=================================================="
echo "   FULL PIPELINE TEST - ALL COMPONENTS (CPU)"
echo "=================================================="
echo ""

# Step 1: Clean up any existing containers
echo "[1/10] Cleaning up existing containers..."
cd image-pipeline
docker compose down -v
docker stop triton-server model-serving-app 2>/dev/null
docker rm triton-server model-serving-app 2>/dev/null
echo ""

# Step 2: Start Triton (CPU mode)
echo "[2/10] Starting Triton Server (CPU mode)..."
docker run --name triton-server \
    --rm -d \
    --network ml-network \
    -p 8000:8000 -p 8001:8001 -p 8002:8002 \
    -v $(pwd)/../tritonserver/model_repository:/models \
    nvcr.io/nvidia/tritonserver:25.07-py3 \
    tritonserver \
    --model-repository=/models \
    --model-control-mode=poll \
    --repository-poll-secs=5

sleep 10

echo "[3/10] Starting FastAPI Model Serving..."
docker run --name model-serving-app \
    --rm -d \
    -p 8003:8003 \
    --network ml-network \
    -e TRITON_SERVER_URL="triton-server:8001" \
    crossmodal-model-serving

docker network connect image-pipeline_pipeline-net model-serving-app
sleep 5
echo ""

# Step 4: Start Infrastructure Services
echo "[4/10] Starting Infrastructure (Kafka, PostgreSQL, MinIO, etcd)..."
docker compose up -d zookeeper kafka postgres minio minio-init etcd
sleep 30
echo ""

# Step 5: Start Milvus
echo "[5/10] Starting Milvus Vector Database..."
docker compose up -d milvus
sleep 60
echo ""

# Step 6: Initialize Milvus Collections
echo "[6/10] Initializing Milvus collections..."
docker compose build milvus-init
docker compose run --rm milvus-init
echo ""

# Step 7: Build and Start Rust Backend
echo "[7/10] Building and starting Rust backend..."
docker compose build rust-backend
docker compose up -d rust-backend
sleep 10
echo ""

# Step 8: Run Producer to Process Images
echo "[8/10] Processing images through pipeline..."
docker compose build python-producer
docker compose run --rm python-producer
echo ""

# Step 9: Verification
echo "[9/10] Verifying Results..."
echo ""
echo "=== SERVICE STATUS ==="
docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "triton|model-serving|kafka|postgres|minio|milvus|rust-backend|zookeeper|etcd" | head -15

echo ""
echo "=== RUST BACKEND STATS ==="
curl -s http://localhost:3000/stats 2>/dev/null | python3 -m json.tool 2>/dev/null || echo "{\"status\": \"not available\"}"

echo ""
echo "=== POSTGRESQL RECORDS ==="
docker exec postgres psql -U postgres -d imagedb -c "
SELECT COUNT(*) as total_records,
       COUNT(DISTINCT milvus_id) as image_vectors,
       COUNT(DISTINCT text_milvus_id) as text_vectors
FROM image_records;" 2>/dev/null || echo "No data"

echo ""
echo "=== RECENT PROCESSED IMAGES ==="
docker exec postgres psql -U postgres -d imagedb -c "
SELECT filename, caption, processed_at 
FROM image_records 
ORDER BY processed_at DESC 
LIMIT 5;" 2>/dev/null || echo "No records"

echo ""
echo "=== MINIO FILES ==="
MINIO_COUNT=$(docker exec minio sh -c "mc alias set local http://localhost:9000 minioadmin minioadmin123 2>/dev/null && mc ls local/images 2>/dev/null | wc -l" || echo "0")
echo "Files in MinIO: $MINIO_COUNT"

echo ""
echo "=== KAFKA MESSAGES ==="
KAFKA_MSG=$(docker exec kafka kafka-run-class kafka.tools.GetOffsetShell --broker-list localhost:9092 --topic image-topic 2>/dev/null | cut -d: -f3 || echo "0")
echo "Messages in Kafka topic: $KAFKA_MSG"

echo ""
echo "=== MILVUS VECTORS ==="
python3 << 'PYTHON' 2>/dev/null
try:
    from pymilvus import connections, utility, Collection
    connections.connect(host="localhost", port=19530, timeout=5)
    for coll_name in utility.list_collections():
        coll = Collection(coll_name)
        print(f"  {coll_name}: {coll.num_entities} vectors")
except Exception as e:
    print(f"  Could not connect to Milvus: {e}")
PYTHON

# Step 10: Final Summary
echo ""
echo "[10/10] Test Complete!"
echo ""
echo "=================================================="
echo "                 TEST SUMMARY"
echo "=================================================="
echo ""

# Check if everything is working
SUCCESS=true
if [ "$KAFKA_MSG" = "0" ]; then
    echo "⚠ No messages in Kafka"
    SUCCESS=false
fi

if [ "$MINIO_COUNT" = "0" ]; then
    echo "⚠ No files in MinIO"
    SUCCESS=false
fi

if $SUCCESS; then
    echo "✅ Pipeline is working successfully!"
else
    echo "⚠ Some components may need attention"
fi

echo ""
echo "Access Points:"
echo "  • Triton Health:  http://localhost:8000/v2/health/ready"
echo "  • FastAPI Docs:   http://localhost:8003/docs"
echo "  • MinIO Console:  http://localhost:9001 (minioadmin/minioadmin123)"
echo "  • Rust API:       http://localhost:3000/stats"
echo "  • PostgreSQL:     localhost:5432 (postgres/postgres123)"
echo "  • Milvus:         localhost:19530"
echo ""
echo "Commands to check logs:"
echo "  docker logs rust-backend --tail 50"
echo "  docker logs model-serving-app --tail 50"
echo "  docker logs python-producer --tail 50"
echo ""
echo "To stop everything:"
echo "  docker compose down"
echo "  docker stop triton-server model-serving-app"
echo ""
echo "=================================================="
