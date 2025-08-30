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
    
    # Check docs endpoint
    echo ""
    echo "Checking /docs endpoint..."
    if curl -s $FASTAPI_URL/docs | grep -q "swagger"; then
        echo "✓ Docs endpoint accessible"
    else
        echo "✗ Docs endpoint not accessible"
    fi
else
    echo "✗ FastAPI is not running!"
    echo "Please start your FastAPI service on port 8003"
    exit 1
fi

# Test embedding endpoint with proper parameters
echo ""
echo "Testing embedding endpoints..."
python3 << 'PYTHON'
import requests
import base64
from PIL import Image
import io
import json

fastapi_url = "http://localhost:8003"

# Create a proper test image (224x224 is common for vision models)
print("\n1. Testing IMAGE embedding endpoint...")
img = Image.new('RGB', (224, 224), color='red')
buffered = io.BytesIO()
img.save(buffered, format="JPEG")
img_base64 = base64.b64encode(buffered.getvalue()).decode()

# Test with proper model_name parameter
try:
    response = requests.post(
        f"{fastapi_url}/retrieval/SigLIP/embed-image",
        json={
            "image": img_base64,
            "model_name": "SigLIP"  # Add this parameter
        },
        timeout=10
    )
    
    print(f"   Status Code: {response.status_code}")
    
    if response.status_code == 200:
        result = response.json()
        embedding = result.get("embedding", [])
        print(f"   ✓ Image embedding received")
        print(f"   Dimension: {len(embedding)}")
        if len(embedding) > 0:
            print(f"   Sample values: {embedding[:3]}")
        
        # Save dimension for Milvus
        with open('embedding_dim.txt', 'w') as f:
            f.write(str(len(embedding)))
    else:
        print(f"   ✗ Error: Status {response.status_code}")
        print(f"   Response: {response.text}")
except Exception as e:
    print(f"   ✗ Failed: {e}")

# Test TEXT embedding endpoint
print("\n2. Testing TEXT embedding endpoint...")
try:
    response = requests.post(
        f"{fastapi_url}/retrieval/SigLIP/embed-text",
        json={
            "text": "A beautiful sunset over the ocean",
            "model_name": "SigLIP"  # Add this parameter
        },
        timeout=10
    )
    
    print(f"   Status Code: {response.status_code}")
    
    if response.status_code == 200:
        result = response.json()
        embedding = result.get("embedding", [])
        print(f"   ✓ Text embedding received")
        print(f"   Dimension: {len(embedding)}")
        if len(embedding) > 0:
            print(f"   Sample values: {embedding[:3]}")
    else:
        print(f"   ✗ Error: Status {response.status_code}")
        print(f"   Response: {response.text}")
except Exception as e:
    print(f"   ✗ Failed: {e}")

print("\n✓ FastAPI test complete!")
PYTHON

echo ""
echo "==================================="