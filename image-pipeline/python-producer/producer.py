#!/usr/bin/env python3
import os
import json
import base64
import time
import hashlib
from datetime import datetime
from pathlib import Path
import sys

try:
    from kafka import KafkaProducer
    import requests
    from PIL import Image
    import io
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
        
        # Check FastAPI FIRST - fail if not available
        if not self.verify_fastapi_connection():
            print("\n❌ FATAL: Cannot connect to FastAPI embedding service")
            print("   The model server must be running to process images.")
            print("   Start it with: docker run --name model-serving-app --network ml-network -p 8003:8003 crossmodal-model-serving")
            sys.exit(1)
        
        self.producer = self.connect_kafka()
    
    def verify_fastapi_connection(self) -> bool:
        """Verify FastAPI and model are accessible - no mocks allowed"""
        print("Verifying model service connection...")
        
        try:
            # Check base connectivity
            response = requests.get(self.fastapi_url, timeout=5)
            print(f"  ✓ FastAPI reachable at {self.fastapi_url}")
            
            # Test with actual embedding request
            test_img = Image.new('RGB', (384, 384), 'blue')
            buf = io.BytesIO()
            test_img.save(buf, format='JPEG')
            test_b64 = base64.b64encode(buf.getvalue()).decode()
            
            test_response = requests.post(
                f"{self.fastapi_url}/retrieval/SigLIP/embed-image",
                json={"data": [test_b64]},
                timeout=10
            )
            
            if test_response.status_code == 200:
                result = test_response.json()
                embedding = result[0]["embedding"]
                if len(embedding) == 1152:
                    print(f"  ✓ Model service verified - getting real {len(embedding)}D embeddings")
                    return True
                else:
                    print(f"  ✗ Unexpected embedding dimension: {len(embedding)}")
                    return False
            else:
                print(f"  ✗ Model endpoint returned error: {test_response.status_code}")
                return False
                
        except requests.exceptions.ConnectionError:
            print(f"  ✗ Cannot connect to {self.fastapi_url}")
            return False
        except requests.exceptions.Timeout:
            print(f"  ✗ Request timed out - model may not be loaded")
            return False
        except Exception as e:
            print(f"  ✗ Verification failed: {e}")
            return False
    
    def connect_kafka(self):
        print("\nConnecting to Kafka...")
        for attempt in range(30):
            try:
                producer = KafkaProducer(
                    bootstrap_servers=self.kafka_broker,
                    value_serializer=lambda v: json.dumps(v).encode('utf-8'),
                    max_request_size=52428800  # 50MB to handle large images
                )
                print("✓ Connected to Kafka broker")
                return producer
            except Exception as e:
                print(f"  Waiting for Kafka... attempt {attempt + 1}/30")
                time.sleep(2)
        raise Exception("Failed to connect to Kafka after 30 attempts")
    
    def get_embedding(self, image_path):
        """Get embedding from FastAPI - no mocks"""
        # Read and potentially resize image to avoid Kafka size issues
        with Image.open(image_path) as img:
            # Resize if too large
            max_dim = 1920
            if img.width > max_dim or img.height > max_dim:
                img.thumbnail((max_dim, max_dim), Image.Resampling.LANCZOS)
                print(f"    Resized to {img.width}x{img.height} to fit message size")
            
            buf = io.BytesIO()
            img.save(buf, format='JPEG', quality=90)
            image_bytes = buf.getvalue()
        
        image_base64 = base64.b64encode(image_bytes).decode('utf-8')
        
        try:
            response = requests.post(
                f"{self.fastapi_url}/retrieval/SigLIP/embed-image",
                json={"data": [image_base64]},
                timeout=30
            )
            
            if response.status_code == 200:
                result = response.json()
                embedding = result[0]["embedding"]
                if len(embedding) == 1152:
                    return embedding, image_bytes
                else:
                    raise ValueError(f"Invalid embedding dimension: {len(embedding)}")
            else:
                raise Exception(f"API returned {response.status_code}: {response.text[:200]}")
                
        except requests.exceptions.Timeout:
            raise Exception("Model request timed out - Triton may be overloaded")
        except Exception as e:
            raise Exception(f"Failed to get embedding: {e}")
    
    def process_image(self, image_path):
        """Process single image - fail if no real embedding"""
        filename = os.path.basename(image_path)
        print(f"\nProcessing: {filename}")
        
        # Get embedding (will raise exception if fails)
        try:
            embedding, image_bytes = self.get_embedding(image_path)
            print(f"  ✓ Got embedding: {len(embedding)} dimensions")
        except Exception as e:
            print(f"  ✗ Failed to get embedding: {e}")
            raise
        
        # Create metadata
        metadata = {
            "filename": filename,
            "file_size": len(image_bytes),
            "file_hash": hashlib.md5(image_bytes).hexdigest(),
            "timestamp": datetime.now().isoformat(),
            "processed_at": int(time.time())
        }
        
        try:
            with Image.open(image_path) as img:
                metadata["width"] = img.width
                metadata["height"] = img.height
                metadata["format"] = img.format
                print(f"  Image: {img.width}x{img.height} {img.format}")
        except Exception as e:
            print(f"  Warning: Could not read image properties: {e}")
        
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
        
        processed = 0
        failed = 0
        
        for image_path in images:
            try:
                if self.process_image(str(image_path)):
                    processed += 1
                time.sleep(0.2)  # Small delay to not overwhelm the model
            except Exception as e:
                print(f"✗ ERROR processing {image_path.name}: {e}")
                failed += 1
                # Optionally: decide if you want to continue or stop on first failure
                # sys.exit(1)  # Uncomment to stop on first failure
        
        self.producer.flush()
        
        print("\n" + "="*40)
        print(f"PROCESSING COMPLETE")
        print(f"  ✓ Processed: {processed} with real embeddings")
        print(f"  ✗ Failed: {failed}")
        print(f"  Total: {len(images)}")
        if failed > 0:
            print(f"\n  ⚠ Some images failed - check model server status")
        print("="*40)

if __name__ == "__main__":
    try:
        producer = ImageProducer()
        producer.run()
    except KeyboardInterrupt:
        print("\n\nInterrupted by user")
        sys.exit(0)
    except Exception as e:
        print(f"\nFATAL ERROR: {e}")
        sys.exit(1)
