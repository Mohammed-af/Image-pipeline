#!/usr/bin/env python3
"""
Initialize Milvus with separate collections for image and text embeddings
"""
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
            connections.connect(alias="default", host=host, port=port, timeout=5)
            print("✓ Connected to Milvus")
            return True
        except Exception as e:
            print(f"  Attempt {i+1}/{max_retries}")
            time.sleep(5)
    return False

def detect_embedding_dimension():
    """Detect embedding dimension from FastAPI"""
    fastapi_url = os.getenv("FASTAPI_URL", "http://host.docker.internal:8003")
    print(f"\nDetecting embedding dimension from {fastapi_url}...")
    
    try:
        # Test image embedding
        from PIL import Image
        import io
        import base64
        
        img = Image.new('RGB', (1, 1), color='white')
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
            dimension = len(embedding)
            print(f"✓ Image embedding dimension: {dimension}")
            
            # Test text embedding
            text_response = requests.post(
                f"{fastapi_url}/retrieval/SigLIP/embed-text",
                json={"text": "test"},
                timeout=10
            )
            
            if text_response.status_code == 200:
                text_embedding = text_response.json().get("embedding", [])
                text_dim = len(text_embedding)
                print(f"✓ Text embedding dimension: {text_dim}")
                
                if dimension != text_dim:
                    print(f"⚠ Warning: Image and text dimensions differ!")
            
            return dimension
    except Exception as e:
        print(f"✗ Could not connect to FastAPI: {e}")
    
    print("Using default dimension: 512")
    return 512

def create_collection(name, description, dimension):
    """Create a Milvus collection"""
    print(f"\nCreating collection '{name}'...")
    
    # Check if exists
    if utility.has_collection(name):
        print(f"  Collection already exists, checking dimension...")
        collection = Collection(name)
        
        for field in collection.schema.fields:
            if field.name == "embedding":
                existing_dim = field.params.get('dim', 0)
                if existing_dim != dimension:
                    print(f"  Dimension mismatch! Dropping and recreating...")
                    collection.drop()
                    break
                else:
                    print(f"  ✓ Dimension matches: {dimension}")
                    return collection
    
    # Define schema
    fields = [
        FieldSchema(name="id", dtype=DataType.VARCHAR, is_primary=True, max_length=100),
        FieldSchema(name="embedding", dtype=DataType.FLOAT_VECTOR, dim=dimension),
        FieldSchema(name="filename", dtype=DataType.VARCHAR, max_length=255),
        FieldSchema(name="caption", dtype=DataType.VARCHAR, max_length=500),
        FieldSchema(name="timestamp", dtype=DataType.INT64),
    ]
    
    schema = CollectionSchema(fields=fields, description=description)
    collection = Collection(name=name, schema=schema)
    
    # Create index
    print(f"  Creating index...")
    index_params = {
        "metric_type": "L2",
        "index_type": "IVF_FLAT",
        "params": {"nlist": 128}
    }
    collection.create_index(field_name="embedding", index_params=index_params)
    
    # Load to memory
    collection.load()
    print(f"  ✓ Collection '{name}' created and loaded")
    
    return collection

def main():
    print("\n=== MILVUS DUAL EMBEDDING SETUP ===\n")
    
    # Configuration
    milvus_host = os.getenv("MILVUS_HOST", "localhost")
    milvus_port = int(os.getenv("MILVUS_PORT", "19530"))
    
    # Wait for Milvus
    if not wait_for_milvus(milvus_host, milvus_port):
        print("✗ Failed to connect to Milvus")
        sys.exit(1)
    
    # Detect dimension
    dimension = detect_embedding_dimension()
    
    # Create TWO collections
    image_collection = create_collection(
        "image_embeddings",
        f"Image embeddings from SigLIP (dim={dimension})",
        dimension
    )
    
    text_collection = create_collection(
        "text_embeddings",
        f"Text embeddings from SigLIP (dim={dimension})",
        dimension
    )
    
    # Show info
    print("\n=== COLLECTIONS CREATED ===")
    print(f"1. Image Collection: {image_collection.name}")
    print(f"   - Entities: {image_collection.num_entities}")
    print(f"2. Text Collection: {text_collection.name}")
    print(f"   - Entities: {text_collection.num_entities}")
    
    print("\n✓ Milvus setup complete with dual embeddings!")

if __name__ == "__main__":
    main()
