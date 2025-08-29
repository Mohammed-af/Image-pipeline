#!/usr/bin/env python3
import os
import json
import base64
import time
import hashlib
from datetime import datetime
from pathlib import Path

# Import required libraries
try:
    from kafka import KafkaProducer
    import requests
    from PIL import Image
    print("✓ Libraries loaded")
except ImportError as e:
    print(f"Missing library: {e}")
    exit(1)

class ImageProducer:
    def __init__(self):
        self.kafka_broker = os.getenv("KAFKA_BROKER", "kafka:29092")
        self.fastapi_url = os.getenv("FASTAPI_URL", "http://host.docker.internal:8003")
        self.source_dir = os.getenv("SOURCE_DIR", "/app/images")
        
        print("\n=== IMAGE PRODUCER CONFIGURATION ===")
        print(f"Kafka Broker: {self.kafka_broker}")
        print(f"FastAPI URL: {self.fastapi_url}")
        print(f"Image Source: {self.source_dir}")
        print("="*40 + "\n")
        
        self.producer = self.connect_kafka()
        self.fastapi_available = self.check_fastapi()
    
    def connect_kafka(self):
        print("Connecting to Kafka...")
        for attempt in range(30):
            try:
                producer = KafkaProducer(
                    bootstrap_servers=self.kafka_broker,
                    value_serializer=lambda v: json.dumps(v).encode('utf-8'),
                    max_request_size=104857600  # 100MB
                )
                print("✓ Connected to Kafka broker")
                return producer
            except Exception as e:
                print(f"  Waiting for Kafka... attempt {attempt + 1}/30")
                time.sleep(2)
        raise Exception("Failed to connect to Kafka after 30 attempts")
    
    def check_fastapi(self):
        print("\nChecking FastAPI service...")
        try:
            response = requests.get(self.fastapi_url, timeout=3)
            print(f"✓ FastAPI is available at {self.fastapi_url}")
            return True
        except:
            print(f"✗ FastAPI not available - will use mock embeddings")
            return False
    
    def get_embedding(self, image_path):
        """Get embedding from FastAPI or generate mock embedding"""
        with open(image_path, 'rb') as f:
            image_bytes = f.read()
        
        image_base64 = base64.b64encode(image_bytes).decode('utf-8')
        
        if self.fastapi_available:
            try:
                response = requests.post(
                    f"{self.fastapi_url}/retrieval/SigLIP/embed-image",
                    json={"image": image_base64},
                    timeout=10
                )
                if response.status_code == 200:
                    result = response.json()
                    embedding = result.get("embedding", [])
                    if embedding:
                        return embedding
            except Exception as e:
                print(f"  Error getting embedding: {e}")
        
        # Generate mock embedding
        import random
        return [random.random() for _ in range(512)]
    
    def process_image(self, image_path):
        """Process single image and send to Kafka"""
        filename = os.path.basename(image_path)
        print(f"\nProcessing: {filename}")
        
        # Read image
        with open(image_path, 'rb') as f:
            image_bytes = f.read()
        
        # Get embedding
        embedding = self.get_embedding(image_path)
        print(f"  Embedding dimension: {len(embedding)}")
        
        # Create metadata
        metadata = {
            "filename": filename,
            "file_size": len(image_bytes),
            "file_hash": hashlib.md5(image_bytes).hexdigest(),
            "timestamp": datetime.now().isoformat(),
            "processed_at": int(time.time())
        }
        
        # Try to get image dimensions
        try:
            with Image.open(image_path) as img:
                metadata["width"] = img.width
                metadata["height"] = img.height
                metadata["format"] = img.format
                print(f"  Image: {img.width}x{img.height} {img.format}")
        except Exception as e:
            print(f"  Could not read image properties: {e}")
        
        # Create message
        message = {
            "image_binary": base64.b64encode(image_bytes).decode('utf-8'),
            "embedding": embedding,
            "metadata": metadata,
            "embedding_dim": len(embedding)
        }
        
        # Send to Kafka
        future = self.producer.send("image-topic", value=message)
        result = future.get(timeout=10)
        print(f"  ✓ Sent to Kafka (partition: {result.partition}, offset: {result.offset})")
        
        return True
    
    def run(self):
        """Process all images in the source directory"""
        print(f"\nScanning directory: {self.source_dir}")
        
        # Check if directory exists
        if not os.path.exists(self.source_dir):
            print(f"ERROR: Directory {self.source_dir} does not exist!")
            return
        
        # Find all images
        image_extensions = ('.jpg', '.jpeg', '.png', '.gif', '.bmp')
        images = []
        for ext in image_extensions:
            images.extend(Path(self.source_dir).glob(f"*{ext}"))
            images.extend(Path(self.source_dir).glob(f"*{ext.upper()}"))
        
        if not images:
            print("No images found in directory!")
            return
        
        print(f"Found {len(images)} images to process")
        print("="*40)
        
        # Process each image
        processed = 0
        failed = 0
        
        for image_path in images:
            try:
                if self.process_image(str(image_path)):
                    processed += 1
                time.sleep(0.5)  # Small delay between messages
            except Exception as e:
                print(f"ERROR processing {image_path}: {e}")
                failed += 1
        
        # Flush any remaining messages
        self.producer.flush()
        
        print("\n" + "="*40)
        print(f"PROCESSING COMPLETE")
        print(f"  ✓ Processed: {processed}")
        print(f"  ✗ Failed: {failed}")
        print(f"  Total: {len(images)}")
        print("="*40)

if __name__ == "__main__":
    try:
        producer = ImageProducer()
        producer.run()
    except Exception as e:
        print(f"FATAL ERROR: {e}")
        exit(1)
