aws_region   = "us-east-2"
project_name = "kafka-enterprise-orders"

# GHCR
ghcr_username = "aisalkyn85"

# Network - leave empty to create new VPC, or provide existing IDs
# existing_vpc_id             = ""
# existing_public_subnet_ids  = []
# existing_private_subnet_ids = []
# existing_alb_sg_id          = ""
# existing_ecs_tasks_sg_id    = ""
# existing_rds_sg_id          = ""

# Container images
container_image_producer  = "ghcr.io/aisalkyn85/kafka-enterprise-orders-producer:latest"
container_image_fraud     = "ghcr.io/aisalkyn85/kafka-enterprise-orders-fraud-service:latest"
container_image_payment   = "ghcr.io/aisalkyn85/kafka-enterprise-orders-payment-service:latest"
container_image_analytics = "ghcr.io/aisalkyn85/kafka-enterprise-orders-analytics-service:latest"
container_image_frontend  = "ghcr.io/aisalkyn85/kafka-enterprise-orders/web-frontend:latest"
container_image_backend   = "ghcr.io/aisalkyn85/kafka-enterprise-orders/web-backend:latest"

# Confluent Cloud
confluent_bootstrap_servers = "pkc-921jm.us-east-2.aws.confluent.cloud:9092"

# Couchbase Capella
couchbase_host   = "cb.2s2wqp2fpzi0hanx.cloud.couchbase.com"
couchbase_bucket = "order_analytics"
