import json
import os
import time
from kafka import KafkaConsumer, KafkaProducer
from kafka.errors import NoBrokersAvailable

BOOTSTRAP = os.environ.get("KAFKA_BOOTSTRAP", os.environ.get("KAFKA_BOOTSTRAP_SERVERS", "kafka:9092"))
API_KEY = os.environ.get("CONFLUENT_API_KEY", "")
API_SECRET = os.environ.get("CONFLUENT_API_SECRET", "")

ORDERS_TOPIC = "orders"
ALERTS_TOPIC = "fraud-alerts"

# Build Kafka config
if API_KEY and API_SECRET:
    KAFKA_CONFIG = {
        "bootstrap_servers": BOOTSTRAP,
        "security_protocol": "SASL_SSL",
        "sasl_mechanism": "PLAIN",
        "sasl_plain_username": API_KEY,
        "sasl_plain_password": API_SECRET,
    }
else:
    KAFKA_CONFIG = {"bootstrap_servers": BOOTSTRAP}

# Retry logic to wait for Kafka to be ready
def create_consumer_with_retry(max_retries=30, retry_delay=2):
    """Create Kafka consumer with retry logic"""
    for attempt in range(max_retries):
        try:
            print(f"Connecting to {BOOTSTRAP}... (attempt {attempt + 1}/{max_retries})")
            consumer = KafkaConsumer(
                ORDERS_TOPIC,
                **KAFKA_CONFIG,
                group_id="fraud-group",
                value_deserializer=lambda m: json.loads(m.decode("utf-8")),
                auto_offset_reset="earliest",
                consumer_timeout_ms=10000,  # Timeout for polling
            )
            print(f"Successfully connected to Kafka at {BOOTSTRAP}")
            return consumer
        except NoBrokersAvailable:
            if attempt < max_retries - 1:
                print(f"Kafka not available yet, waiting {retry_delay} seconds...")
                time.sleep(retry_delay)
            else:
                raise
    raise Exception("Failed to connect to Kafka after all retries")

def create_producer_with_retry(max_retries=30, retry_delay=2):
    """Create Kafka producer with retry logic"""
    for attempt in range(max_retries):
        try:
            producer = KafkaProducer(
                **KAFKA_CONFIG,
                value_serializer=lambda v: json.dumps(v).encode("utf-8"),
            )
            print(f"Successfully created Kafka producer")
            return producer
        except NoBrokersAvailable:
            if attempt < max_retries - 1:
                print(f"Kafka not available yet, waiting {retry_delay} seconds...")
                time.sleep(retry_delay)
            else:
                raise
    raise Exception("Failed to create Kafka producer after all retries")

# Create consumer and producer with retry logic
consumer = create_consumer_with_retry()
producer = create_producer_with_retry()

def is_fraud(order):
    return order.get("amount", 0) > 300 and order.get("country") not in ["US", "CA"]

print("Fraud service started. Listening for orders...")

try:
    for msg in consumer:
        try:
            order = msg.value
            oid = order.get("order_id")

            if is_fraud(order):
                alert = {
                    "order_id": oid,
                    "reason": "HIGH_AMOUNT_RISKY_COUNTRY",
                    "amount": order["amount"],
                    "country": order["country"],
                }
                producer.send(ALERTS_TOPIC, value=alert)
                print(f"[fraud] ALERT order {oid}: ${order['amount']} from {order['country']}")
            else:
                print(f"[fraud] order {oid} OK")
        except Exception as e:
            print(f"[fraud] Error processing message: {e}")
            continue
except KeyboardInterrupt:
    print("[fraud] Shutting down...")
except Exception as e:
    print(f"[fraud] Fatal error: {e}")
    raise
finally:
    if consumer:
        consumer.close()
    if producer:
        producer.close()
