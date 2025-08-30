#!/bin/bash

clear
echo "=============================================="
echo "         COMPLETE SERVICE CHECK"
echo "=============================================="
echo ""

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to check service
check_service() {
    local name=$1
    local check_cmd=$2
    local port=$3
    
    printf "%-20s Port %-6s " "$name:" "$port"
    
    if eval $check_cmd > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Running${NC}"
        return 0
    else
        echo -e "${RED}✗ Not responding${NC}"
        return 1
    fi
}

echo "🐳 DOCKER SERVICES:"
echo "-------------------------------------------"

# Check all containers
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | head -15

echo ""
echo "🌐 SERVICE ENDPOINTS:"
echo "-------------------------------------------"

# 1. Kafka
check_service "Kafka" "docker exec kafka kafka-broker-api-versions --bootstrap-server localhost:9092" "9092"

# 2. PostgreSQL
check_service "PostgreSQL" "docker exec postgres pg_isready -U postgres" "5432"

# 3. MinIO
check_service "MinIO API" "curl -s http://localhost:9000/minio/health/live" "9000"
check_service "MinIO Console" "curl -s -o /dev/null -w '%{http_code}' http://localhost:9001 | grep -q '200\|301\|302'" "9001"

# 4. Rust Backend
check_service "Rust Backend API" "curl -s http://localhost:3000/health" "3000"

# 5. Milvus
check_service "Milvus" "curl -s http://localhost:9091/healthz | grep -q 'OK'" "19530"

# 6. Zookeeper
check_service "Zookeeper" "docker exec zookeeper echo ruok | nc localhost 2181 | grep -q imok" "2181"

# 7. FastAPI (on host)
check_service "FastAPI" "curl -s http://localhost:8003" "8003"

echo ""
echo "📊 SERVICE STATISTICS:"
echo "-------------------------------------------"

# Rust Backend Stats
echo -e "\n${YELLOW}Rust Backend Stats:${NC}"
if curl -s http://localhost:3000/stats > /dev/null 2>&1; then
    curl -s http://localhost:3000/stats | python3 -m json.tool 2>/dev/null || echo "  Stats endpoint not returning JSON"
else
    echo "  API not accessible"
fi

# Database Stats
echo -e "\n${YELLOW}PostgreSQL Database:${NC}"
if docker exec postgres pg_isready > /dev/null 2>&1; then
    docker exec postgres psql -U postgres -d imagedb -t -c "
    SELECT 
        'Total Records: ' || COUNT(*) as metric
    FROM image_records
    UNION ALL
    SELECT 
        'Latest: ' || COALESCE(MAX(processed_at)::text, 'No records')
    FROM image_records;" 2>/dev/null || echo "  No data"
else
    echo "  Database not accessible"
fi

# Kafka Topics
echo -e "\n${YELLOW}Kafka Topics:${NC}"
if docker exec kafka kafka-topics --list --bootstrap-server localhost:9092 > /dev/null 2>&1; then
    docker exec kafka kafka-topics --list --bootstrap-server localhost:9092 2>/dev/null | head -5
else
    echo "  Cannot list topics"
fi

# Milvus Collections
echo -e "\n${YELLOW}Milvus Collections:${NC}"
if command -v python3 > /dev/null; then
    python3 << 'PYTHON' 2>/dev/null
try:
    from pymilvus import connections, utility
    connections.connect(host="localhost", port=19530, timeout=2)
    collections = utility.list_collections()
    print(f"  Collections: {collections}")
except:
    print("  Cannot connect to Milvus (pymilvus may not be installed)")
PYTHON
else
    echo "  Python not available for check"
fi

echo ""
echo "=============================================="
echo "            ACCESS POINTS"
echo "=============================================="
echo ""
echo "📌 Web Interfaces:"
echo "  • MinIO Console:  http://localhost:9001"
echo "    Username: minioadmin"
echo "    Password: minioadmin123"
echo ""
echo "📌 APIs:"
echo "  • Rust Backend:   http://localhost:3000/stats"
echo "  • FastAPI:        http://localhost:8003"
echo ""
echo "📌 Databases:"
echo "  • PostgreSQL:     psql -h localhost -U postgres -d imagedb"
echo "    Password: postgres123"
echo "  • Milvus:         localhost:19530"
echo ""
echo "=============================================="
