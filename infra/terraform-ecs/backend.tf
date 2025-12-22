terraform {
  backend "s3" {
    bucket         = "kafka-enterprise-orders-tfstate"
    key            = "terraform.tfstate"
    region         = "us-east-2"
    dynamodb_table = "kafka-enterprise-orders-lock"
    encrypt        = true
  }
}
