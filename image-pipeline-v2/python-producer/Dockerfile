FROM python:3.11-slim

WORKDIR /app

RUN pip install --no-cache-dir \
    kafka-python==2.0.2 \
    requests==2.31.0 \
    Pillow==10.1.0

COPY producer_enhanced.py producer.py

CMD ["python", "-u", "producer.py"]
