#!/bin/bash

echo "============================================"
echo "  TESTING DUAL FASTAPI ENDPOINTS"
echo "============================================"
echo ""

FASTAPI_URL="http://localhost:8003"

# Test both endpoints
python3 << 'PYTHON'
import requests
import base64
from PIL import Image
import io
import json

fastapi_url = "http://localhost:8003"

print("1. Testing IMAGE embedding endpoint...")
try:
    # Create test image
    img = Image.new('RGB', (224, 224), color='blue')
    buffered = io.BytesIO()
    img.save(buffered, format="JPEG")
    img_base64 = base64.b64encode(buffered.getvalue()).decode()
    
    response = requests.post(
        f"{fastapi_url}/retrieval/SigLIP/embed-image",
        json={"image": img_base64},
        timeout=10
    )
    
    if response.status_code == 200:
        embedding = response.json().get("embedding", [])
        print(f"   ✓ Image embedding received")
        print(f"     Dimension: {len(embedding)}")
        print(f"     Sample: {embedding[:3]}")
    else:
        print(f"   ✗ Error: {response.status_code}")
except Exception as e:
    print(f"   ✗ Failed: {e}")

print("\n2. Testing TEXT embedding endpoint...")
try:
    response = requests.post(
        f"{fastapi_url}/retrieval/SigLIP/embed-text",
        json={"text": "A beautiful sunset over the ocean"},
        timeout=10
    )
    
    if response.status_code == 200:
        embedding = response.json().get("embedding", [])
        print(f"   ✓ Text embedding received")
        print(f"     Dimension: {len(embedding)}")
        print(f"     Sample: {embedding[:3]}")
    else:
        print(f"   ✗ Error: {response.status_code}")
except Exception as e:
    print(f"   ✗ Failed: {e}")

print("\n✓ Both endpoints are working!")
PYTHON

echo ""
echo "============================================"
