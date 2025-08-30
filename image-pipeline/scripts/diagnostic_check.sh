#!/bin/bash

# ================================================
#    PIPELINE DIAGNOSTIC CHECK (READ-ONLY)
#    No modifications - Just checking status
# ================================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Configuration
PIPELINE_DIR="${1:-image-pipeline}"

echo ""
echo -e "${CYAN}╔════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║${BOLD}              PIPELINE DIAGNOSTIC CHECK (READ-ONLY)                 ${NC}${CYAN}║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BOLD}Target Directory:${NC} $PIPELINE_DIR"
echo -e "${BOLD}Time:${NC} $(date)"
echo ""

# ================================================
#              1. SYSTEM REQUIREMENTS
# ================================================

echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}  1. SYSTEM REQUIREMENTS${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Check Docker
echo -n "  Docker: "
if command -v docker > /dev/null 2>&1; then
    DOCKER_VERSION=$(docker --version | cut -d' ' -f3 | tr -d ',')
    echo -e "${GREEN}✓${NC} Installed (version $DOCKER_VERSION)"
    
    # Check if Docker daemon is running
    echo -n "  Docker Daemon: "
    if docker info > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} Running"
    else
        echo -e "${RED}✗${NC} Not running or no permissions"
    fi
else
    echo -e "${RED}✗${NC} Not installed"
fi

# Check Docker Compose
echo -n "  Docker Compose: "
if docker compose version > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} Available (v2)"
elif command -v docker-compose > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} Available (v1)"
else
    echo -e "${RED}✗${NC} Not available"
fi

# Check Python
echo -n "  Python3: "
if command -v python3 > /dev/null 2>&1; then
    PYTHON_VERSION=$(python3 --version | cut -d' ' -f2)
    echo -e "${GREEN}✓${NC} Installed (version $PYTHON_VERSION)"
else
    echo -e "${RED}✗${NC} Not installed"
fi

# Check curl
echo -n "  Curl: "
if command -v curl > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} Available"
else
    echo -e "${RED}✗${NC} Not available"
fi

# ================================================
#              2. DIRECTORY STRUCTURE
# ================================================

echo ""
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}  2. DIRECTORY STRUCTURE${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Check if pipeline directory exists
echo -n "  Pipeline Directory: "
if [ -d "$PIPELINE_DIR" ]; then
    echo -e "${GREEN}✓${NC} $PIPELINE_DIR exists"
    
    # List structure
    echo -e "\n  ${BOLD}Directory Contents:${NC}"
    ls -la "$PIPELINE_DIR" | head -15 | sed 's/^/    /'
    
    # Check for key directories
    echo -e "\n  ${BOLD}Key Components:${NC}"
    for dir in "rust-backend" "python-producer" "milvus-init" "images" "init-scripts"; do
        echo -n "    $dir: "
        if [ -d "$PIPELINE_DIR/$dir" ]; then
            FILE_COUNT=$(find "$PIPELINE_DIR/$dir" -type f 2>/dev/null | wc -l)
            echo -e "${GREEN}✓${NC} ($FILE_COUNT files)"
        else
            echo -e "${YELLOW}✗${NC} Not found"
        fi
    done
else
    echo -e "${RED}✗${NC} Directory not found: $PIPELINE_DIR"
    echo "    Available directories:"
    ls -d */ 2>/dev/null | sed 's/^/      /'
fi

# ================================================
#           3. CONFIGURATION FILES
# ================================================

echo ""
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}  3. CONFIGURATION FILES${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

if [ -d "$PIPELINE_DIR" ]; then
    cd "$PIPELINE_DIR"
    
    # Check docker-compose.yml
    echo -n "  docker-compose.yml: "
    if [ -f "docker-compose.yml" ]; then
        SERVICE_COUNT=$(grep -c "^  [a-z]" docker-compose.yml 2>/dev/null || echo "0")
        echo -e "${GREEN}✓${NC} Found ($SERVICE_COUNT services defined)"
    else
        echo -e "${RED}✗${NC} Not found"
    fi
    
    # Check Dockerfiles
    echo -e "\n  ${BOLD}Dockerfiles:${NC}"
    for dockerfile in rust-backend/Dockerfile python-producer/Dockerfile milvus-init/Dockerfile; do
        echo -n "    $dockerfile: "
        if [ -f "$dockerfile" ]; then
            BASE_IMAGE=$(grep "^FROM" "$dockerfile" | head -1 | awk '{print $2}')
            echo -e "${GREEN}✓${NC} (base: $BASE_IMAGE)"
        else
            echo -e "${RED}✗${NC} Not found"
        fi
    done
    
    # Check Rust configuration
    echo -e "\n  ${BOLD}Rust Configuration:${NC}"
    echo -n "    Cargo.toml: "
    if [ -f "rust-backend/Cargo.toml" ]; then
        RUST_VERSION=$(grep "edition" rust-backend/Cargo.toml | cut -d'"' -f2)
        echo -e "${GREEN}✓${NC} (edition: $RUST_VERSION)"
    else
        echo -e "${RED}✗${NC} Not found"
    fi
    
    # Check for build errors
    echo -n "    Build log: "
    if [ -f "build.log" ] || [ -f "rust-backend/build.log" ]; then
        echo -e "${YELLOW}⚠${NC} Build error log exists"
        if [ -f "build.log" ]; then
            echo "      Last error:"
            grep -A2 "ERROR:" build.log | tail -3 | sed 's/^/        /'
        fi
    else
        echo -e "${BLUE}ℹ${NC} No build log"
    fi
fi

# ================================================
#           4. RUNNING SERVICES
# ================================================

echo ""
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}  4. RUNNING DOCKER CONTAINERS${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

RUNNING_CONTAINERS=$(docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | tail -n +2)
if [ -z "$RUNNING_CONTAINERS" ]; then
    echo -e "  ${YELLOW}No containers running${NC}"
else
    echo -e "  ${BOLD}Running Containers:${NC}"
    echo "$RUNNING_CONTAINERS" | sed 's/^/    /'
fi

echo ""
STOPPED_CONTAINERS=$(docker ps -a --filter "status=exited" --format "{{.Names}}" | head -5)
if [ ! -z "$STOPPED_CONTAINERS" ]; then
    echo -e "  ${BOLD}Recently Stopped:${NC}"
    echo "$STOPPED_CONTAINERS" | sed 's/^/    /'
fi

# ================================================
#           5. SERVICE ENDPOINTS
# ================================================

echo ""
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}  5. SERVICE ENDPOINT STATUS${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Check FastAPI
echo -n "  FastAPI (8003): "
if curl -s -f http://localhost:8003 > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} Running"
    
    # Test endpoints
    echo "    Endpoints:"
    echo -n "      /docs: "
    if curl -s http://localhost:8003/docs | grep -q "swagger" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} Accessible"
    else
        echo -e "${RED}✗${NC} Not accessible"
    fi
    
    echo -n "      Image embed: "
    if curl -s -X POST http://localhost:8003/retrieval/SigLIP/embed-image \
         -H "Content-Type: application/json" \
         -d '{"image":"test"}' | grep -q "embedding\|error" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} Responding"
    else
        echo -e "${RED}✗${NC} Not responding"
    fi
else
    echo -e "${RED}✗${NC} Not running"
fi

# Check Rust Backend
echo -n "  Rust Backend (3000): "
if curl -s http://localhost:3000/health 2>/dev/null | grep -q "OK"; then
    echo -e "${GREEN}✓${NC} Running"
    
    # Get stats
    STATS=$(curl -s http://localhost:3000/stats 2>/dev/null)
    if [ ! -z "$STATS" ]; then
        echo "    Stats:"
        echo "$STATS" | python3 -m json.tool 2>/dev/null | head -8 | sed 's/^/      /'
    fi
else
    echo -e "${RED}✗${NC} Not running"
fi

# Check PostgreSQL
echo -n "  PostgreSQL (5432): "
if docker exec postgres pg_isready -U postgres > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} Running"
    
    # Check database
    DB_SIZE=$(docker exec postgres psql -U postgres -t -c "SELECT pg_database_size('imagedb');" 2>/dev/null | xargs)
    if [ ! -z "$DB_SIZE" ]; then
        echo "    Database 'imagedb' size: $(echo "scale=2; $DB_SIZE/1024/1024" | bc 2>/dev/null || echo "?") MB"
    fi
else
    echo -e "${RED}✗${NC} Not running"
fi

# Check MinIO
echo -n "  MinIO (9000/9001): "
if curl -s http://localhost:9000/minio/health/live > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} Running"
else
    echo -e "${RED}✗${NC} Not running"
fi

# Check Kafka
echo -n "  Kafka (9092): "
if docker exec kafka kafka-broker-api-versions --bootstrap-server localhost:9092 > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} Running"
    
    # List topics
    TOPICS=$(docker exec kafka kafka-topics --list --bootstrap-server localhost:9092 2>/dev/null | head -3)
    if [ ! -z "$TOPICS" ]; then
        echo "    Topics: $(echo $TOPICS | tr '\n' ', ')"
    fi
else
    echo -e "${RED}✗${NC} Not running"
fi

# Check Milvus
echo -n "  Milvus (19530): "
if curl -s http://localhost:9091/healthz 2>/dev/null | grep -q "OK"; then
    echo -e "${GREEN}✓${NC} Running"
else
    echo -e "${RED}✗${NC} Not running"
fi

# ================================================
#              6. DATA STATUS
# ================================================

echo ""
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}  6. DATA STATUS${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Check images directory
echo -n "  Image Directory: "
if [ -d "$PIPELINE_DIR/images" ]; then
    IMAGE_COUNT=$(find "$PIPELINE_DIR/images" -type f \( -name "*.jpg" -o -name "*.jpeg" -o -name "*.png" \) 2>/dev/null | wc -l)
    echo -e "${GREEN}✓${NC} $IMAGE_COUNT images found"
else
    echo -e "${YELLOW}✗${NC} No images directory"
fi

# Check PostgreSQL data
echo -n "  PostgreSQL Records: "
PG_COUNT=$(docker exec postgres psql -U postgres -d imagedb -t -c "SELECT COUNT(*) FROM image_records;" 2>/dev/null | xargs)
if [ ! -z "$PG_COUNT" ] && [ "$PG_COUNT" != "0" ]; then
    echo -e "${GREEN}✓${NC} $PG_COUNT records"
else
    echo -e "${YELLOW}○${NC} No records or table not found"
fi

# Check MinIO data
echo -n "  MinIO Objects: "
MINIO_COUNT=$(docker exec minio sh -c "mc alias set local http://localhost:9000 minioadmin minioadmin123 2>/dev/null && mc ls local/images 2>/dev/null | wc -l")
if [ ! -z "$MINIO_COUNT" ] && [ "$MINIO_COUNT" != "0" ]; then
    echo -e "${GREEN}✓${NC} $MINIO_COUNT files"
else
    echo -e "${YELLOW}○${NC} No files or bucket not found"
fi

# Check Kafka messages
echo -n "  Kafka Messages: "
KAFKA_MSG=$(docker exec kafka kafka-run-class kafka.tools.GetOffsetShell --broker-list localhost:9092 --topic image-topic 2>/dev/null | cut -d: -f3)
if [ ! -z "$KAFKA_MSG" ] && [ "$KAFKA_MSG" != "0" ]; then
    echo -e "${GREEN}✓${NC} $KAFKA_MSG messages in image-topic"
else
    echo -e "${YELLOW}○${NC} No messages or topic not found"
fi

# ================================================
#              7. RESOURCE USAGE
# ================================================

echo ""
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}  7. RESOURCE USAGE${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Docker disk usage
echo -e "  ${BOLD}Docker Disk Usage:${NC}"
docker system df | sed 's/^/    /'

# Top memory consumers
echo -e "\n  ${BOLD}Top Memory Consumers:${NC}"
docker stats --no-stream --format "table {{.Container}}\t{{.MemUsage}}\t{{.CPUPerc}}" | head -6 | sed 's/^/    /'

# ================================================
#              8. RECENT LOGS
# ================================================

echo ""
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}  8. RECENT ERROR LOGS${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Check for rust-backend errors
if docker ps | grep -q rust-backend; then
    echo -e "  ${BOLD}Rust Backend (last 5 lines):${NC}"
    docker logs rust-backend 2>&1 | tail -5 | sed 's/^/    /'
fi

# Check for any containers that exited with errors
FAILED_CONTAINERS=$(docker ps -a --filter "status=exited" --filter "exited=1" --format "{{.Names}}" | head -3)
if [ ! -z "$FAILED_CONTAINERS" ]; then
    echo -e "\n  ${BOLD}Failed Containers:${NC}"
    for container in $FAILED_CONTAINERS; do
        echo "    $container:"
        docker logs $container 2>&1 | tail -3 | sed 's/^/      /'
    done
fi

# ================================================
#                   SUMMARY
# ================================================

echo ""
echo -e "${CYAN}╔════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║${BOLD}                        DIAGNOSTIC SUMMARY                          ${NC}${CYAN}║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════════════╝${NC}"

# Count running services
RUNNING_COUNT=$(docker ps --format "{{.Names}}" | wc -l)
EXPECTED_SERVICES=("kafka" "postgres" "minio" "milvus" "rust-backend" "zookeeper" "etcd")
RUNNING_EXPECTED=0

for service in "${EXPECTED_SERVICES[@]}"; do
    if docker ps --format "{{.Names}}" | grep -q "^$service$"; then
        ((RUNNING_EXPECTED++))
    fi
done

echo ""
echo -e "${BOLD}Pipeline Status:${NC}"
echo "  • Directory: $PIPELINE_DIR $([ -d "$PIPELINE_DIR" ] && echo "✓" || echo "✗")"
echo "  • Docker: $(command -v docker > /dev/null 2>&1 && echo "✓ Installed" || echo "✗ Not installed")"
echo "  • Containers: $RUNNING_EXPECTED/${#EXPECTED_SERVICES[@]} expected services running"
echo "  • Total containers: $RUNNING_COUNT running"

echo ""
echo -e "${BOLD}Key Issues Detected:${NC}"

# Check for the main build error
if [ -f "$PIPELINE_DIR/build.log" ] && grep -q "edition2024" "$PIPELINE_DIR/build.log"; then
    echo -e "  ${RED}•${NC} Rust build failed: edition2024 feature (need to update Rust version)"
fi

if ! curl -s http://localhost:8003 > /dev/null 2>&1; then
    echo -e "  ${RED}•${NC} FastAPI service not running on port 8003"
fi

if ! docker ps | grep -q rust-backend; then
    echo -e "  ${RED}•${NC} Rust backend not running (likely due to build failure)"
fi

if [ "$RUNNING_EXPECTED" -lt 4 ]; then
    echo -e "  ${YELLOW}•${NC} Some services are not running"
fi

echo ""
echo -e "${BOLD}Recommendations:${NC}"
echo "  1. Start FastAPI service if not running (port 8003)"
echo "  2. Fix Rust build issue (update Dockerfile to use rust:1.79)"
echo "  3. Rebuild and restart failed containers"
echo "  4. Check docker logs for any failed services"

echo ""
echo -e "${BLUE}ℹ${NC} This was a read-only diagnostic. No changes were made."
echo -e "${BLUE}ℹ${NC} To fix issues and run the pipeline, use the comprehensive test script."
echo ""
