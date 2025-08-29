#!/bin/bash

echo "==================================="
echo "  TESTING FASTAPI CONNECTION"
echo "==================================="
echo ""

FASTAPI_URL="http://localhost:8003"

# Check if FastAPI is running
echo "Checking FastAPI at $FASTAPI_URL..."
if curl -s -f $FASTAPI_URL > /dev/null; then
    echo "✓ FastAPI is running"
else
    echo "✗ FastAPI is not running!"
    echo "Please start your FastAPI service on port 8003"
    exit 1
fi

# Test embedding endpoint
echo ""
echo "Testing embedding endpoint..."
python3 << 'PYTHON'
import requests
import base64
from PIL import Image
import io
import json

# Create test image
img = Image.new('RGB', (224, 224), color='red')
buffered = io.BytesIO()
img.save(buffered, format="JPEG")
img_base64 = base64.b64encode(buffered.getvalue()).decode()

# Call FastAPI
try:
    response = requests.post(
        "http://localhost:8003/retrieval/SigLIP/embed-image",
        json={"image": img_base64},
        timeout=10
    )
    
    if response.status_code == 200:
        result = response.json()
        embedding = result.get("embedding", [])
        print(f"✓ Embedding received")
        print(f"  Dimension: {len(embedding)}")
        print(f"  Sample values: {embedding[:3]}")
        
        # Save dimension for Milvus
        with open('embedding_dim.txt', 'w') as f:
            f.write(str(len(embedding)))
    else:
        print(f"✗ Error: Status {response.status_code}")
        print(f"  Response: {response.text}")
except Exception as e:
    print(f"✗ Failed: {e}")
PYTHON

echo ""
echo "==================================="
