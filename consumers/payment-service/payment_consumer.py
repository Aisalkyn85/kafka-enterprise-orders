import json
import os
import time
from kafka import KafkaConsumer, KafkaProducer

BOOTSTRAP = os.environ.get("KAFKA_BOOTSTRAP", os.environ.get("KAFKA_BOOTSTRAP_SERVERS", "kafka:9092"))
API_KEY = os.environ.get("CONFLUENT_API_KEY", "")
API_SECRET = os.environ.get("CONFLUENT_API_SECRET", "")

ORDERS_TOPIC = "orders"
PAYMENTS_TOPIC = "payments"

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

print(f"Connecting to {BOOTSTRAP}...")
consumer = KafkaConsumer(
    ORDERS_TOPIC,
    **KAFKA_CONFIG,
    group_id="payments-group",
    value_deserializer=lambda m: json.loads(m.decode("utf-8")),
    auto_offset_reset="earliest",
)

producer = KafkaProducer(
    **KAFKA_CONFIG,
    value_serializer=lambda v: json.dumps(v).encode("utf-8"),
)

print("Payment service started...")

for msg in consumer:
    order = msg.value
    oid = order.get("order_id")

    time.sleep(0.1)  # simulate processing

    payment = {
        "order_id": oid,
        "status": "PAID",
        "amount": order["amount"],
        "country": order["country"],
    }
    producer.send(PAYMENTS_TOPIC, value=payment)
    print(f"[payment] order {oid} processed: ${order['amount']}")
