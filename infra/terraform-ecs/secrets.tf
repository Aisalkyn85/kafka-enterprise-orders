# GHCR credentials
resource "aws_secretsmanager_secret" "ghcr" {
  name                    = "${var.project_name}-ghcr-credentials"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "ghcr" {
  secret_id = aws_secretsmanager_secret.ghcr.id
  secret_string = jsonencode({
    username = var.ghcr_username
    password = var.ghcr_pat
  })
}

# Kafka credentials
resource "aws_secretsmanager_secret" "confluent" {
  name                    = "${var.project_name}-confluent-credentials"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "confluent" {
  secret_id = aws_secretsmanager_secret.confluent.id
  secret_string = jsonencode({
    bootstrap_servers = var.confluent_bootstrap_servers
    api_key           = var.confluent_api_key
    api_secret        = var.confluent_api_secret
  })
}

# Couchbase credentials
resource "aws_secretsmanager_secret" "couchbase" {
  name                    = "${var.project_name}-couchbase-credentials"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "couchbase" {
  secret_id = aws_secretsmanager_secret.couchbase.id
  secret_string = jsonencode({
    host     = var.couchbase_host
    bucket   = var.couchbase_bucket
    username = var.couchbase_username
    password = var.couchbase_password
  })
}
