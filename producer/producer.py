import json
import os
import random
import time
from datetime import datetime
from faker import Faker
from kafka import KafkaProducer

# Supports both local (KAFKA_BOOTSTRAP) and Confluent Cloud (KAFKA_BOOTSTRAP_SERVERS)
BOOTSTRAP = os.environ.get("KAFKA_BOOTSTRAP", os.environ.get("KAFKA_BOOTSTRAP_SERVERS", "kafka:9092"))
API_KEY = os.environ.get("CONFLUENT_API_KEY", "")
API_SECRET = os.environ.get("CONFLUENT_API_SECRET", "")
TOPIC_NAME = os.getenv("TOPIC_NAME", "orders")
SLEEP_SECONDS = float(os.getenv("SLEEP_SECONDS", "2"))

fake = Faker()

def create_producer():
    if API_KEY and API_SECRET:
        # Confluent Cloud
        return KafkaProducer(
            bootstrap_servers=BOOTSTRAP,
            security_protocol="SASL_SSL",
            sasl_mechanism="PLAIN",
            sasl_plain_username=API_KEY,
            sasl_plain_password=API_SECRET,
            value_serializer=lambda v: json.dumps(v).encode("utf-8"),
            key_serializer=lambda k: str(k).encode("utf-8"),
        )
    else:
        # Local Kafka - specify api_version to avoid auto-detection issues
        return KafkaProducer(
            bootstrap_servers=BOOTSTRAP,
            api_version=(2, 5, 0),  # Works with Kafka 2.5+
            value_serializer=lambda v: json.dumps(v).encode("utf-8"),
            key_serializer=lambda k: str(k).encode("utf-8"),
        )

def generate_order(order_id):
    return {
        "order_id": order_id,
        "customer_id": fake.random_int(min=1000, max=9999),
        "amount": round(random.uniform(10, 500), 2),
        "currency": "USD",
        "country": random.choice(["US", "CA", "DE", "IN", "GB", "FR", "CN", "BR"]),
        "status": random.choice(["CREATED", "CONFIRMED", "CANCELLED"]),
        "created_at": datetime.utcnow().isoformat() + "Z",
    }

def main():
    print(f"Connecting to {BOOTSTRAP}...")
    producer = create_producer()
    print(f"Publishing to '{TOPIC_NAME}'")

    order_id = 1
    while True:
        order = generate_order(order_id)
        future = producer.send(TOPIC_NAME, key=order["order_id"], value=order)

        try:
            meta = future.get(timeout=20)
            print(f"order {order_id} → partition {meta.partition}")
        except Exception as e:
            print(f"Error: {e}")

        order_id += 1
        time.sleep(SLEEP_SECONDS)

if __name__ == "__main__":
    main()
