#!/usr/bin/env python3
import os
import sys
import time
import requests
from pymilvus import connections, Collection, CollectionSchema, FieldSchema, DataType, utility

def wait_for_milvus(host, port, max_retries=30):
    """Wait for Milvus to be ready"""
    print(f"Waiting for Milvus at {host}:{port}...")
    for i in range(max_retries):
        try:
            connections.connect(
                alias="default",
                host=host,
                port=port,
                timeout=5
            )
            print("✓ Connected to Milvus")
            return True
        except Exception as e:
            print(f"  Attempt {i+1}/{max_retries}: {e}")
            time.sleep(5)
    return False

def detect_embedding_dimension():
    """Detect embedding dimension from FastAPI"""
    fastapi_url = os.getenv("FASTAPI_URL", "http://localhost:8003")
    print(f"\nDetecting embedding dimension from FastAPI at {fastapi_url}...")
    
    try:
        # Check if FastAPI is running
        response = requests.get(fastapi_url, timeout=5)
        print(f"✓ FastAPI is running")
        
        # Create a minimal test image
        from PIL import Image
        import io
        import base64
        
        img = Image.new('RGB', (1, 1), color='white')
        buffered = io.BytesIO()
        img.save(buffered, format="JPEG")
        img_base64 = base64.b64encode(buffered.getvalue()).decode()
        
        # Get embedding
        response = requests.post(
            f"{fastapi_url}/retrieval/SigLIP/embed-image",
            json={"image": img_base64},
            timeout=10
        )
        
        if response.status_code == 200:
            embedding = response.json().get("embedding", [])
            dimension = len(embedding)
            print(f"✓ Detected embedding dimension: {dimension}")
            return dimension
        else:
            print(f"✗ FastAPI returned status {response.status_code}")
    except Exception as e:
        print(f"✗ Could not connect to FastAPI: {e}")
    
    # Default dimension
    print("Using default dimension: 512")
    return 512

def create_collection(dimension):
    """Create Milvus collection with detected dimension"""
    collection_name = "image_embeddings"
    
    # Check if collection exists
    if utility.has_collection(collection_name):
        print(f"Collection '{collection_name}' already exists")
        collection = Collection(collection_name)
        
        # Check dimension matches
        for field in collection.schema.fields:
            if field.name == "embedding":
                existing_dim = field.params.get('dim', 0)
                if existing_dim != dimension:
                    print(f"⚠ Dimension mismatch! Existing: {existing_dim}, New: {dimension}")
                    print("Dropping and recreating collection...")
                    collection.drop()
                    break
                else:
                    print(f"✓ Collection dimension matches: {dimension}")
                    return collection
    
    # Create new collection
    print(f"Creating collection '{collection_name}' with dimension {dimension}...")
    
    fields = [
        FieldSchema(name="id", dtype=DataType.VARCHAR, is_primary=True, max_length=100),
        FieldSchema(name="embedding", dtype=DataType.FLOAT_VECTOR, dim=dimension),
        FieldSchema(name="filename", dtype=DataType.VARCHAR, max_length=255),
        FieldSchema(name="timestamp", dtype=DataType.INT64),
    ]
    
    schema = CollectionSchema(
        fields=fields,
        description=f"Image embeddings from SigLIP (dim={dimension})"
    )
    
    collection = Collection(name=collection_name, schema=schema)
    print(f"✓ Created collection '{collection_name}'")
    
    # Create index for similarity search
    print("Creating IVF_FLAT index...")
    index_params = {
        "metric_type": "L2",  # or "IP" for inner product
        "index_type": "IVF_FLAT",
        "params": {"nlist": 128}
    }
    collection.create_index(field_name="embedding", index_params=index_params)
    print("✓ Index created")
    
    # Load collection to memory
    collection.load()
    print("✓ Collection loaded to memory")
    
    return collection

def main():
    print("\n=== MILVUS INITIALIZATION ===\n")
    
    # Configuration
    milvus_host = os.getenv("MILVUS_HOST", "localhost")
    milvus_port = int(os.getenv("MILVUS_PORT", "19530"))
    
    # Wait for Milvus
    if not wait_for_milvus(milvus_host, milvus_port):
        print("✗ Failed to connect to Milvus")
        sys.exit(1)
    
    # Detect embedding dimension from FastAPI
    dimension = detect_embedding_dimension()
    
    # Create collection
    collection = create_collection(dimension)
    
    # Show collection info
    print("\n=== COLLECTION INFO ===")
    print(f"Name: {collection.name}")
    print(f"Entities: {collection.num_entities}")
    print(f"Schema: {collection.schema}")
    
    print("\n✓ Milvus initialization complete!")

if __name__ == "__main__":
    main()
