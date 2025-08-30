#!/usr/bin/env python3
"""
Enhanced Producer with Text and Image Embeddings
Uses both FastAPI endpoints:
- /retrieval/SigLIP/embed-text
- /retrieval/SigLIP/embed-image
"""

import os
import json
import base64
import time
import hashlib
from datetime import datetime
from pathlib import Path
from typing import List, Dict, Optional

try:
    from kafka import KafkaProducer
    import requests
    from PIL import Image
    print("✓ Libraries loaded")
except ImportError as e:
    print(f"Missing library: {e}")
    exit(1)

class EnhancedImageProducer:
    def __init__(self):
        self.kafka_broker = os.getenv("KAFKA_BROKER", "kafka:29092")
        self.fastapi_url = os.getenv("FASTAPI_URL", "http://model-serving-app:8003")
        self.source_dir = os.getenv("SOURCE_DIR", "/app/images")
        
        print("\n=== ENHANCED PRODUCER WITH DUAL EMBEDDINGS ===")
        print(f"Kafka Broker: {self.kafka_broker}")
        print(f"FastAPI URL: {self.fastapi_url}")
        print(f"  - Image endpoint: {self.fastapi_url}/retrieval/SigLIP/embed-image")
        print(f"  - Text endpoint: {self.fastapi_url}/retrieval/SigLIP/embed-text")
        print(f"Image Source: {self.source_dir}")
        print("="*50 + "\n")
        
        self.producer = self.connect_kafka()
        self.fastapi_available = self.check_fastapi_endpoints()
        self.embedding_dim = self.detect_embedding_dimension()
    
    def connect_kafka(self) -> KafkaProducer:
        """Connect to Kafka with retry logic"""
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
    
    def check_fastapi_endpoints(self) -> bool:
        """Check if both FastAPI endpoints are available"""
        print("\nChecking FastAPI endpoints...")
        
        try:
            # Check base URL
            response = requests.get(self.fastapi_url + "/health", timeout=3)
            print(f"✓ FastAPI service is running at {self.fastapi_url}")
            
            # Test image embedding endpoint with correct format
            test_image = self.create_test_image()
            img_response = requests.post(
                f"{self.fastapi_url}/retrieval/SigLIP/embed-image",
                json={"data": [test_image]},  # data as list
                timeout=10
            )
            if img_response.status_code == 200:
                print(f"✓ Image embedding endpoint is working")
            else:
                print(f"✗ Image endpoint returned status {img_response.status_code}")
                return False
            
            # Test text embedding endpoint with correct format
            text_response = requests.post(
                f"{self.fastapi_url}/retrieval/SigLIP/embed-text",
                json={"data": ["test"]},  # data as list
                timeout=10
            )
            if text_response.status_code == 200:
                print(f"✓ Text embedding endpoint is working")
            else:
                print(f"✗ Text endpoint returned status {text_response.status_code}")
                return False
            
            return True
            
        except Exception as e:
            print(f"✗ FastAPI not available: {e}")
            print("  Will use mock embeddings")
            return False
    
    def create_test_image(self) -> str:
        """Create a small test image"""
        img = Image.new('RGB', (384, 384), color='white')
        import io
        buffered = io.BytesIO()
        img.save(buffered, format="JPEG")
        return base64.b64encode(buffered.getvalue()).decode()
    
    def detect_embedding_dimension(self) -> int:
        """Detect embedding dimension from FastAPI"""
        if not self.fastapi_available:
            return 1152  # Default SigLIP dimension
        
        try:
            test_image = self.create_test_image()
            response = requests.post(
                f"{self.fastapi_url}/retrieval/SigLIP/embed-image",
                json={"data": [test_image]},  # data as list
                timeout=10
            )
            if response.status_code == 200:
                result = response.json()
                if 'embeddings' in result and result['embeddings']:
                    dim = len(result['embeddings'][0])
                    print(f"✓ Detected embedding dimension: {dim}")
                    return dim
        except:
            pass
        
        print("Using default dimension: 1152")
        return 1152
    
    def get_image_embedding(self, image_base64: str) -> List[float]:
        """Get image embedding from FastAPI"""
        if self.fastapi_available:
            try:
                response = requests.post(
                    f"{self.fastapi_url}/retrieval/SigLIP/embed-image",
                    json={"data": [image_base64]},  # data as list
                    timeout=30
                )
                if response.status_code == 200:
                    result = response.json()
                    if 'embeddings' in result and result['embeddings']:
                        return result['embeddings'][0]  # Get first embedding from batch
                    return []
            except Exception as e:
                print(f"  Image embedding error: {e}")
        
        # Mock embedding
        import random
        return [random.random() for _ in range(self.embedding_dim)]
    
    def get_text_embedding(self, text: str) -> List[float]:
        """Get text embedding from FastAPI"""
        if self.fastapi_available:
            try:
                response = requests.post(
                    f"{self.fastapi_url}/retrieval/SigLIP/embed-text",
                    json={"data": [text]},  # data as list
                    timeout=30
                )
                if response.status_code == 200:
                    result = response.json()
                    if 'embeddings' in result and result['embeddings']:
                        return result['embeddings'][0]  # Get first embedding from batch
                    return []
            except Exception as e:
                print(f"  Text embedding error: {e}")
        
        # Mock embedding
        import random
        return [random.random() for _ in range(self.embedding_dim)]
    
    def generate_image_caption(self, filename: str, metadata: Dict) -> str:
        """Generate a text description for the image"""
        # Create a descriptive caption based on metadata
        parts = []
        
        # Add filename without extension
        name = os.path.splitext(filename)[0].replace('_', ' ').replace('-', ' ')
        parts.append(f"Image of {name}")
        
        # Add size info if available
        if metadata.get("width") and metadata.get("height"):
            parts.append(f"{metadata['width']}x{metadata['height']} pixels")
        
        # Add format
        if metadata.get("format"):
            parts.append(f"{metadata['format']} format")
        
        caption = ". ".join(parts)
        return caption
    
    def process_image(self, image_path: Path) -> bool:
        """Process single image with both text and image embeddings"""
        filename = image_path.name
        print(f"\n{'='*50}")
        print(f"Processing: {filename}")
        
        # Read image
        with open(image_path, 'rb') as f:
            image_bytes = f.read()
        
        image_base64 = base64.b64encode(image_bytes).decode('utf-8')
        
        # Create metadata
        metadata = {
            "filename": filename,
            "file_size": len(image_bytes),
            "file_hash": hashlib.md5(image_bytes).hexdigest(),
            "timestamp": datetime.now().isoformat(),
            "processed_at": int(time.time())
        }
        
        # Get image properties
        try:
            with Image.open(image_path) as img:
                metadata["width"] = img.width
                metadata["height"] = img.height
                metadata["format"] = img.format
                metadata["mode"] = img.mode
                print(f"  Image: {img.width}x{img.height} {img.format}")
        except Exception as e:
            print(f"  Could not read image properties: {e}")
        
        # Get IMAGE embedding
        print(f"  Getting image embedding...")
        image_embedding = self.get_image_embedding(image_base64)
        print(f"    ✓ Image embedding dimension: {len(image_embedding)}")
        
        # Generate caption and get TEXT embedding
        caption = self.generate_image_caption(filename, metadata)
        print(f"  Caption: '{caption}'")
        print(f"  Getting text embedding...")
        text_embedding = self.get_text_embedding(caption)
        print(f"    ✓ Text embedding dimension: {len(text_embedding)}")
        
        # Add caption to metadata
        metadata["caption"] = caption
        
        # Create message with BOTH embeddings
        message = {
            "image_binary": image_base64,
            "image_embedding": image_embedding,
            "text_embedding": text_embedding,
            "metadata": metadata,
            "embedding_dim": len(image_embedding),
            "has_dual_embeddings": True
        }
        
        # Send to Kafka
        future = self.producer.send("image-topic", value=message)
        result = future.get(timeout=10)
        print(f"  ✓ Sent to Kafka (partition: {result.partition}, offset: {result.offset})")
        print(f"  ✓ Dual embeddings stored")
        
        return True
    
    def run(self):
        """Process all images in the source directory"""
        print(f"\nScanning directory: {self.source_dir}")
        
        if not os.path.exists(self.source_dir):
            print(f"ERROR: Directory {self.source_dir} does not exist!")
            # Create some test images
            print("Creating test images...")
            os.makedirs(self.source_dir, exist_ok=True)
            colors = ['red', 'green', 'blue', 'yellow', 'purple']
            for color in colors:
                img = Image.new('RGB', (256, 256), color=color)
                img.save(f"{self.source_dir}/test_{color}.jpg")
            print(f"Created {len(colors)} test images")
        
        # Find all images
        image_extensions = ('.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp')
        images = []
        for ext in image_extensions:
            images.extend(Path(self.source_dir).glob(f"*{ext}"))
            images.extend(Path(self.source_dir).glob(f"*{ext.upper()}"))
        
        if not images:
            print("No images found in directory!")
            return
        
        print(f"Found {len(images)} images to process")
        print("="*50)
        
        # Process each image
        processed = 0
        failed = 0
        
        for image_path in images:
            try:
                if self.process_image(image_path):
                    processed += 1
                time.sleep(0.5)
            except Exception as e:
                print(f"ERROR processing {image_path}: {e}")
                failed += 1
        
        self.producer.flush()
        
        print("\n" + "="*50)
        print(f"PROCESSING COMPLETE")
        print(f"  ✓ Processed: {processed} images")
        print(f"  ✓ Created: {processed * 2} embeddings (image + text)")
        print(f"  ✗ Failed: {failed}")
        print("="*50)

if __name__ == "__main__":
    try:
        producer = EnhancedImageProducer()
        producer.run()
    except Exception as e:
        print(f"FATAL ERROR: {e}")
        exit(1)