FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY analytics_consumer.py .

ENV KAFKA_BOOTSTRAP_SERVERS=kafka:9092

CMD ["python", "analytics_consumer.py"]

