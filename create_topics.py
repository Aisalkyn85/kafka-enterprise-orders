from kafka.admin import KafkaAdminClient, NewTopic
from kafka.errors import TopicAlreadyExistsError
import sys

# Confluent Cloud credentials
BOOTSTRAP_SERVERS = "pkc-921jm.us-east-2.aws.confluent.cloud:9092"
API_KEY = "LUTQDYGP3XTVJE5V"
API_SECRET = "cfltQUDfj0BQVr3A4KQEJEbfRJkC5Q0RP8h6yphUqcPa99azMYfWB+VogzXfTG1A"

print("Connecting to Confluent Cloud...")
sys.stdout.flush()

try:
    admin_client = KafkaAdminClient(
        bootstrap_servers=BOOTSTRAP_SERVERS,
        security_protocol="SASL_SSL",
        sasl_mechanism="PLAIN",
        sasl_plain_username=API_KEY,
        sasl_plain_password=API_SECRET,
        api_version=(2, 6, 0),
        request_timeout_ms=60000,
    )
    print("Connected!")
    sys.stdout.flush()

    topics_to_create = [
        NewTopic(name="orders", num_partitions=6, replication_factor=3),
        NewTopic(name="payments", num_partitions=6, replication_factor=3),
        NewTopic(name="fraud-alerts", num_partitions=6, replication_factor=3),
        NewTopic(name="order-analytics", num_partitions=6, replication_factor=3),
    ]

    print("Creating topics...")
    sys.stdout.flush()
    
    for topic in topics_to_create:
        try:
            admin_client.create_topics([topic], validate_only=False)
            print(f"Created: {topic.name}")
        except TopicAlreadyExistsError:
            print(f"Already exists: {topic.name}")
        except Exception as e:
            print(f"Error creating {topic.name}: {e}")
        sys.stdout.flush()

    print("\nListing all topics...")
    sys.stdout.flush()
    topics = admin_client.list_topics()
    for t in topics:
        print(f"  - {t}")
    
    admin_client.close()
    print("\nDone!")
    
except Exception as e:
    print(f"Connection error: {e}")
    sys.stdout.flush()
