#!/bin/bash

clear
echo "=============================================="
echo "   COMPLETE DOCKER PIPELINE"
echo "=============================================="
echo ""

# Step 1: Start infrastructure
echo "[1/5] Starting infrastructure services..."
docker compose up -d zookeeper kafka postgres minio minio-init

# Wait for services
echo "[2/5] Waiting for services to initialize (30s)..."
for i in {30..1}; do
    echo -ne "  $i seconds remaining...\r"
    sleep 1
done
echo ""

# Step 2: Build and start Rust backend
echo "[3/5] Building Rust backend (this may take 2-3 minutes)..."
docker compose build rust-backend
docker compose up -d rust-backend

# Wait for Rust to start
echo "  Waiting for Rust backend to start..."
sleep 10

# Check Rust health
echo "  Checking Rust backend health..."
if curl -s http://localhost:3000/health > /dev/null; then
    echo "  ✓ Rust backend is healthy"
else
    echo "  ⚠ Rust backend may still be starting..."
fi

# Step 3: Build Python producer
echo "[4/5] Building Python producer..."
docker compose build python-producer

# Step 4: Run Python producer
echo "[5/5] Running Python producer to send images..."
docker compose run --rm python-producer

# Show results
echo ""
echo "=============================================="
echo "   RESULTS"
echo "=============================================="
echo ""

# Show Rust backend stats
echo "Rust Backend Stats:"
curl -s http://localhost:3000/stats | python3 -m json.tool 2>/dev/null || echo "  Stats not available yet"

echo ""
echo "Database Records:"
docker exec postgres psql -U postgres -d imagedb -t -c "
    SELECT COUNT(*) as total_images, 
           SUM(file_size) as total_bytes,
           MAX(processed_at) as last_processed 
    FROM image_records;
" 2>/dev/null || echo "  No records yet"

echo ""
echo "Recent Processing Logs:"
docker logs --tail 10 rust-backend 2>/dev/null | grep "✓"

echo ""
echo "=============================================="
echo "   ACCESS POINTS"
echo "=============================================="
echo ""
echo "• MinIO Console: http://localhost:9001"
echo "  Username: minioadmin"
echo "  Password: minioadmin123"
echo ""
echo "• Rust Backend Health: http://localhost:3000/health"
echo "• Rust Backend Stats: http://localhost:3000/stats"
echo ""
echo "• PostgreSQL: localhost:5432"
echo "  Database: imagedb"
echo "  User: postgres"
echo "  Password: postgres123"
echo ""
echo "=============================================="
echo ""
echo "Commands:"
echo "  • View Rust logs:     docker logs -f rust-backend"
echo "  • View database:      docker exec postgres psql -U postgres -d imagedb -c 'SELECT * FROM image_records;'"
echo "  • Send more images:   docker compose run --rm python-producer"
echo "  • Stop everything:    docker compose down"
echo "  • Clean everything:   docker compose down -v"
echo ""
