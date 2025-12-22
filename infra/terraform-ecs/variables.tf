variable "aws_region" {
  default = "us-east-2"
}

variable "project_name" {
  default = "kafka-enterprise-orders"
}

# GHCR
variable "ghcr_username" {}
variable "ghcr_pat" {
  sensitive = true
}

# Network - leave empty to create new VPC
variable "existing_vpc_id" {
  default = ""
}
variable "existing_public_subnet_ids" {
  default = []
}
variable "existing_private_subnet_ids" {
  default = []
}
variable "existing_alb_sg_id" {
  default = ""
}
variable "existing_ecs_tasks_sg_id" {
  default = ""
}
variable "existing_rds_sg_id" {
  default = ""
}

# Container images
variable "container_image_producer" {}
variable "container_image_fraud" {}
variable "container_image_payment" {}
variable "container_image_analytics" {}
variable "container_image_frontend" {}
variable "container_image_backend" {}

# Kafka
variable "confluent_bootstrap_servers" {}
variable "confluent_api_key" {
  sensitive = true
}
variable "confluent_api_secret" {
  sensitive = true
}

# Couchbase
variable "couchbase_host" {}
variable "couchbase_bucket" {
  default = "order_analytics"
}
variable "couchbase_username" {
  default = "appuser"
}
variable "couchbase_password" {
  sensitive = true
}
