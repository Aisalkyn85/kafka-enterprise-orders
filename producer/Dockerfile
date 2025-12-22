FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY producer.py .

ENV KAFKA_BOOTSTRAP_SERVERS=kafka:9092
ENV TOPIC_NAME=orders
ENV SLEEP_SECONDS=2
ENV PYTHONUNBUFFERED=1

CMD ["python", "-u", "producer.py"]

