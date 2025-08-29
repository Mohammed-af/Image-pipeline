FROM python:3.11-slim
WORKDIR /app
RUN pip install --no-cache-dir pymilvus==2.3.3 requests==2.31.0 Pillow==10.1.0
COPY init_milvus_dual.py init_milvus.py
CMD ["python", "-u", "init_milvus.py"]
