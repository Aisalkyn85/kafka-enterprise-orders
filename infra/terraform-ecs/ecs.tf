# cluster
resource "aws_ecs_cluster" "this" {
  name = "${var.project_name}-cluster"
}

# iam role for ecs tasks
resource "aws_iam_role" "ecs_task_execution" {
  name = "${var.project_name}-ecs-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "ecs-tasks.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_1" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "ecs_secrets_policy" {
  name = "${var.project_name}-ecs-secrets-policy"
  role = aws_iam_role.ecs_task_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["secretsmanager:GetSecretValue"]
      Resource = [
        aws_secretsmanager_secret.ghcr.arn,
        aws_secretsmanager_secret.confluent.arn,
        aws_secretsmanager_secret.couchbase.arn
      ]
    }]
  })
}

# security group for workers (no inbound)
resource "aws_security_group" "ecs_tasks" {
  name        = "${var.project_name}-ecs-tasks-sg"
  description = "Security group for ECS tasks"
  vpc_id      = local.vpc_id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["127.0.0.1/32"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# security group for webapp (alb traffic)
resource "aws_security_group" "webapp_tasks" {
  name   = "${var.project_name}-webapp-tasks-sg"
  vpc_id = local.vpc_id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [local.alb_sg]
  }

  ingress {
    from_port       = 8000
    to_port         = 8000
    protocol        = "tcp"
    security_groups = [local.alb_sg]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# log groups
resource "aws_cloudwatch_log_group" "producer_lg" {
  name              = "/ecs/${var.project_name}-producer"
  retention_in_days = 1
}

resource "aws_cloudwatch_log_group" "fraud_lg" {
  name              = "/ecs/${var.project_name}-fraud"
  retention_in_days = 1
}

resource "aws_cloudwatch_log_group" "payment_lg" {
  name              = "/ecs/${var.project_name}-payment"
  retention_in_days = 1
}

resource "aws_cloudwatch_log_group" "analytics_lg" {
  name              = "/ecs/${var.project_name}-analytics"
  retention_in_days = 1
}

resource "aws_cloudwatch_log_group" "frontend_lg" {
  name              = "/ecs/${var.project_name}-frontend"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "backend_lg" {
  name              = "/ecs/${var.project_name}-backend"
  retention_in_days = 7
}

# producer task
resource "aws_ecs_task_definition" "producer" {
  family                   = "${var.project_name}-producer"
  cpu                      = "256"
  memory                   = "512"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn

  container_definitions = jsonencode([{
    name      = "producer"
    image     = var.container_image_producer
    essential = true

    repositoryCredentials = {
      credentialsParameter = aws_secretsmanager_secret.ghcr.arn
    }

    environment = [
      { name = "SERVICE_NAME", value = "producer" },
      { name = "TOPIC_NAME", value = "orders" },
      { name = "SLEEP_SECONDS", value = "2" }
    ]

    secrets = [
      { name = "KAFKA_BOOTSTRAP_SERVERS", valueFrom = "${aws_secretsmanager_secret.confluent.arn}:bootstrap_servers::" },
      { name = "CONFLUENT_API_KEY", valueFrom = "${aws_secretsmanager_secret.confluent.arn}:api_key::" },
      { name = "CONFLUENT_API_SECRET", valueFrom = "${aws_secretsmanager_secret.confluent.arn}:api_secret::" }
    ]

    logConfiguration = {
      logDriver = "awslogs",
      options = {
        awslogs-group         = aws_cloudwatch_log_group.producer_lg.name
        awslogs-region        = var.aws_region
        awslogs-stream-prefix = "ecs"
      }
    }
  }])
}

# fraud service task
resource "aws_ecs_task_definition" "fraud" {
  family                   = "${var.project_name}-fraud"
  cpu                      = "256"
  memory                   = "512"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn

  container_definitions = jsonencode([{
    name      = "fraud"
    image     = var.container_image_fraud
    essential = true

    repositoryCredentials = {
      credentialsParameter = aws_secretsmanager_secret.ghcr.arn
    }

    environment = [
      { name = "SERVICE_NAME", value = "fraud-service" },
      { name = "INPUT_TOPIC", value = "orders" }
    ]

    secrets = [
      { name = "KAFKA_BOOTSTRAP_SERVERS", valueFrom = "${aws_secretsmanager_secret.confluent.arn}:bootstrap_servers::" },
      { name = "CONFLUENT_API_KEY", valueFrom = "${aws_secretsmanager_secret.confluent.arn}:api_key::" },
      { name = "CONFLUENT_API_SECRET", valueFrom = "${aws_secretsmanager_secret.confluent.arn}:api_secret::" }
    ]

    logConfiguration = {
      logDriver = "awslogs",
      options = {
        awslogs-group         = aws_cloudwatch_log_group.fraud_lg.name
        awslogs-region        = var.aws_region
        awslogs-stream-prefix = "ecs"
      }
    }
  }])
}

# payment service task
resource "aws_ecs_task_definition" "payment" {
  family                   = "${var.project_name}-payment"
  cpu                      = "256"
  memory                   = "512"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn

  container_definitions = jsonencode([{
    name      = "payment"
    image     = var.container_image_payment
    essential = true

    repositoryCredentials = {
      credentialsParameter = aws_secretsmanager_secret.ghcr.arn
    }

    environment = [
      { name = "SERVICE_NAME", value = "payment-service" },
      { name = "INPUT_TOPIC", value = "orders" }
    ]

    secrets = [
      { name = "KAFKA_BOOTSTRAP_SERVERS", valueFrom = "${aws_secretsmanager_secret.confluent.arn}:bootstrap_servers::" },
      { name = "CONFLUENT_API_KEY", valueFrom = "${aws_secretsmanager_secret.confluent.arn}:api_key::" },
      { name = "CONFLUENT_API_SECRET", valueFrom = "${aws_secretsmanager_secret.confluent.arn}:api_secret::" }
    ]

    logConfiguration = {
      logDriver = "awslogs",
      options = {
        awslogs-group         = aws_cloudwatch_log_group.payment_lg.name
        awslogs-region        = var.aws_region
        awslogs-stream-prefix = "ecs"
      }
    }
  }])
}

# analytics service task
resource "aws_ecs_task_definition" "analytics" {
  family                   = "${var.project_name}-analytics"
  cpu                      = "256"
  memory                   = "512"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn

  container_definitions = jsonencode([{
    name      = "analytics"
    image     = var.container_image_analytics
    essential = true

    repositoryCredentials = {
      credentialsParameter = aws_secretsmanager_secret.ghcr.arn
    }

    environment = [
      { name = "SERVICE_NAME", value = "analytics-service" },
      { name = "INPUT_TOPIC", value = "orders" }
    ]

    secrets = [
      { name = "KAFKA_BOOTSTRAP_SERVERS", valueFrom = "${aws_secretsmanager_secret.confluent.arn}:bootstrap_servers::" },
      { name = "CONFLUENT_API_KEY", valueFrom = "${aws_secretsmanager_secret.confluent.arn}:api_key::" },
      { name = "CONFLUENT_API_SECRET", valueFrom = "${aws_secretsmanager_secret.confluent.arn}:api_secret::" },
      { name = "COUCHBASE_HOST", valueFrom = "${aws_secretsmanager_secret.couchbase.arn}:host::" },
      { name = "COUCHBASE_BUCKET", valueFrom = "${aws_secretsmanager_secret.couchbase.arn}:bucket::" },
      { name = "COUCHBASE_USERNAME", valueFrom = "${aws_secretsmanager_secret.couchbase.arn}:username::" },
      { name = "COUCHBASE_PASSWORD", valueFrom = "${aws_secretsmanager_secret.couchbase.arn}:password::" }
    ]

    logConfiguration = {
      logDriver = "awslogs",
      options = {
        awslogs-group         = aws_cloudwatch_log_group.analytics_lg.name
        awslogs-region        = var.aws_region
        awslogs-stream-prefix = "ecs"
      }
    }
  }])
}

# worker services (no alb)
resource "aws_ecs_service" "producer" {
  name            = "${var.project_name}-producer-svc"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.producer.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = local.public_subnets
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = true
  }

  depends_on = [
    aws_iam_role_policy_attachment.ecs_task_execution_1,
    aws_cloudwatch_log_group.producer_lg
  ]
}

resource "aws_ecs_service" "fraud" {
  name            = "${var.project_name}-fraud-svc"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.fraud.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = local.public_subnets
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = true
  }

  depends_on = [
    aws_iam_role_policy_attachment.ecs_task_execution_1,
    aws_cloudwatch_log_group.fraud_lg
  ]
}

resource "aws_ecs_service" "payment" {
  name            = "${var.project_name}-payment-svc"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.payment.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = local.public_subnets
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = true
  }

  depends_on = [
    aws_iam_role_policy_attachment.ecs_task_execution_1,
    aws_cloudwatch_log_group.payment_lg
  ]
}

resource "aws_ecs_service" "analytics" {
  name            = "${var.project_name}-analytics-svc"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.analytics.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = local.public_subnets
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = true
  }

  depends_on = [
    aws_iam_role_policy_attachment.ecs_task_execution_1,
    aws_cloudwatch_log_group.analytics_lg
  ]
}

# frontend task
resource "aws_ecs_task_definition" "frontend" {
  family                   = "${var.project_name}-frontend"
  cpu                      = "256"
  memory                   = "512"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn

  container_definitions = jsonencode([{
    name      = "frontend"
    image     = var.container_image_frontend
    essential = true

    repositoryCredentials = {
      credentialsParameter = aws_secretsmanager_secret.ghcr.arn
    }

    portMappings = [{
      containerPort = 80
      hostPort      = 80
      protocol      = "tcp"
    }]

    logConfiguration = {
      logDriver = "awslogs",
      options = {
        awslogs-group         = aws_cloudwatch_log_group.frontend_lg.name
        awslogs-region        = var.aws_region
        awslogs-stream-prefix = "ecs"
      }
    }
  }])
}

# backend task
resource "aws_ecs_task_definition" "backend" {
  family                   = "${var.project_name}-backend"
  cpu                      = "512"
  memory                   = "1024"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn

  container_definitions = jsonencode([{
    name      = "backend"
    image     = var.container_image_backend
    essential = true

    repositoryCredentials = {
      credentialsParameter = aws_secretsmanager_secret.ghcr.arn
    }

    secrets = [
      { name = "COUCHBASE_HOST", valueFrom = "${aws_secretsmanager_secret.couchbase.arn}:host::" },
      { name = "COUCHBASE_BUCKET", valueFrom = "${aws_secretsmanager_secret.couchbase.arn}:bucket::" },
      { name = "COUCHBASE_USERNAME", valueFrom = "${aws_secretsmanager_secret.couchbase.arn}:username::" },
      { name = "COUCHBASE_PASSWORD", valueFrom = "${aws_secretsmanager_secret.couchbase.arn}:password::" }
    ]

    portMappings = [{
      containerPort = 8000
      hostPort      = 8000
      protocol      = "tcp"
    }]

    logConfiguration = {
      logDriver = "awslogs",
      options = {
        awslogs-group         = aws_cloudwatch_log_group.backend_lg.name
        awslogs-region        = var.aws_region
        awslogs-stream-prefix = "ecs"
      }
    }
  }])
}

# webapp services with alb
resource "aws_ecs_service" "frontend" {
  name            = "${var.project_name}-frontend-svc"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.frontend.arn
  desired_count   = 2
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = local.public_subnets
    security_groups  = [aws_security_group.webapp_tasks.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.webapp_tg.arn
    container_name   = "frontend"
    container_port   = 80
  }

  depends_on = [
    aws_iam_role_policy_attachment.ecs_task_execution_1,
    aws_cloudwatch_log_group.frontend_lg,
    aws_lb_listener.http
  ]
}

resource "aws_ecs_service" "backend" {
  name            = "${var.project_name}-backend-svc"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.backend.arn
  desired_count   = 2
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = local.public_subnets
    security_groups  = [aws_security_group.webapp_tasks.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.backend_tg.arn
    container_name   = "backend"
    container_port   = 8000
  }

  depends_on = [
    aws_iam_role_policy_attachment.ecs_task_execution_1,
    aws_cloudwatch_log_group.backend_lg,
    aws_lb_listener.http
  ]
}
