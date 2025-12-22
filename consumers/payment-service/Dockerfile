FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY payment_consumer.py .

ENV KAFKA_BOOTSTRAP_SERVERS=kafka:9092

CMD ["python", "payment_consumer.py"]

