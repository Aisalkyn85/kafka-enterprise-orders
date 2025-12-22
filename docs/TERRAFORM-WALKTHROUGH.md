# Terraform Infrastructure Walkthrough

This document provides a detailed walkthrough of both **ECS** and **EKS** Terraform configurations for the Kafka Enterprise Orders application.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [ECS Terraform Walkthrough](#ecs-terraform-walkthrough)
3. [EKS Terraform Walkthrough](#eks-terraform-walkthrough)
4. [Comparison: ECS vs EKS](#comparison-ecs-vs-eks)
5. [Deployment Instructions](#deployment-instructions)

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                         AWS Cloud                                    │
│  ┌────────────────────────────────────────────────────────────────┐ │
│  │                         VPC (10.x.0.0/16)                       │ │
│  │  ┌─────────────────────┐    ┌─────────────────────┐            │ │
│  │  │  Public Subnet 1    │    │  Public Subnet 2    │            │ │
│  │  │  (10.x.1.0/24)      │    │  (10.x.2.0/24)      │            │ │
│  │  │  ┌──────────────┐   │    │  ┌──────────────┐   │            │ │
│  │  │  │ ALB          │◄──┼────┼──│ Internet GW  │   │            │ │
│  │  │  └──────┬───────┘   │    │  └──────────────┘   │            │ │
│  │  │         │           │    │                      │            │ │
│  │  │  ┌──────▼───────┐   │    │  ┌──────────────┐   │            │ │
│  │  │  │ ECS/EKS      │   │    │  │ ECS/EKS      │   │            │ │
│  │  │  │ Tasks/Pods   │   │    │  │ Tasks/Pods   │   │            │ │
│  │  │  └──────────────┘   │    │  └──────────────┘   │            │ │
│  │  └─────────────────────┘    └─────────────────────┘            │ │
│  └────────────────────────────────────────────────────────────────┘ │
│                                                                      │
│  External Services:                                                  │
│  • Confluent Cloud (Kafka)                                          │
│  • Couchbase Capella (Database)                                     │
│  • GitHub Container Registry (Images)                               │
└─────────────────────────────────────────────────────────────────────┘
```

---

## ECS Terraform Walkthrough

**Location:** `infra/terraform-ecs/`

### File Structure

```
terraform-ecs/
├── provider.tf          # AWS provider configuration
├── backend.tf           # S3 remote state backend
├── variables.tf         # Input variables
├── locals.tf            # Local values
├── vpc.tf               # VPC and security groups
├── secrets.tf           # AWS Secrets Manager
├── ecs.tf               # ECS cluster, tasks, services
├── alb.tf               # Application Load Balancer
├── monitoring.tf        # CloudWatch dashboards
├── outputs.tf           # Output values
├── values.auto.tfvars   # Non-sensitive variables
└── terraform.tfvars     # Sensitive variables (gitignored)
```

---

### 1. Provider Configuration (`provider.tf`)

```hcl
terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region  # us-east-2
}
```

**Purpose:** Configures Terraform to use AWS provider version 5.x in the us-east-2 region.

---

### 2. Remote State Backend (`backend.tf`)

```hcl
terraform {
  backend "s3" {
    bucket         = "kafka-enterprise-orders-tfstate"
    key            = "terraform.tfstate"
    region         = "us-east-2"
    dynamodb_table = "kafka-enterprise-orders-lock"
    encrypt        = true
  }
}
```

**Purpose:** Stores Terraform state in S3 with DynamoDB locking for team collaboration.

**Benefits:**
- State is shared across team members
- DynamoDB prevents concurrent modifications
- Encryption protects sensitive data

---

### 3. VPC Configuration (`vpc.tf`)

```hcl
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.0.0"

  create_vpc = var.existing_vpc_id == ""  # Skip if VPC already exists

  name = "${var.project_name}-vpc"
  cidr = "10.30.0.0/16"

  azs             = ["us-east-2a", "us-east-2b"]
  private_subnets = ["10.30.1.0/24", "10.30.2.0/24"]
  public_subnets  = ["10.30.3.0/24", "10.30.4.0/24"]

  enable_nat_gateway = true   # For private subnet internet access
  single_nat_gateway = true   # Cost optimization

  tags = { Project = var.project_name }
}
```

**What This Creates:**
| Resource | Purpose |
|----------|---------|
| VPC | Isolated network (10.30.0.0/16) |
| 2 Public Subnets | For ALB and tasks with public IPs |
| 2 Private Subnets | For internal resources |
| Internet Gateway | Public internet access |
| NAT Gateway | Private subnet outbound access |
| Route Tables | Traffic routing rules |

**Security Group for ALB:**
```hcl
resource "aws_security_group" "alb" {
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Allow HTTP from anywhere
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Allow HTTPS from anywhere
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]  # Allow all outbound
  }
}
```

---

### 4. Secrets Management (`secrets.tf`)

```hcl
# GHCR credentials for pulling Docker images
resource "aws_secretsmanager_secret" "ghcr" {
  name                    = "${var.project_name}-ghcr-credentials"
  recovery_window_in_days = 0  # Allow immediate deletion
}

resource "aws_secretsmanager_secret_version" "ghcr" {
  secret_id = aws_secretsmanager_secret.ghcr.id
  secret_string = jsonencode({
    username = var.ghcr_username
    password = var.ghcr_pat      # GitHub PAT
  })
}

# Confluent Kafka credentials
resource "aws_secretsmanager_secret" "confluent" {
  name = "${var.project_name}-confluent-credentials"
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

# Couchbase database credentials
resource "aws_secretsmanager_secret" "couchbase" {
  name = "${var.project_name}-couchbase-credentials"
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
```

**Secrets Stored:**
| Secret Name | Contents |
|-------------|----------|
| ghcr-credentials | GitHub username + PAT |
| confluent-credentials | Bootstrap servers + API key/secret |
| couchbase-credentials | Host, bucket, username, password |

---

### 5. ECS Cluster & Services (`ecs.tf`)

#### IAM Role for ECS Tasks

```hcl
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

# Attach standard ECS execution policy
resource "aws_iam_role_policy_attachment" "ecs_task_execution_1" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Custom policy for Secrets Manager access
resource "aws_iam_role_policy" "ecs_secrets_policy" {
  role = aws_iam_role.ecs_task_execution.id
  policy = jsonencode({
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = [
        aws_secretsmanager_secret.ghcr.arn,
        aws_secretsmanager_secret.confluent.arn,
        aws_secretsmanager_secret.couchbase.arn
      ]
    }]
  })
}
```

#### Task Definition Example (Producer)

```hcl
resource "aws_ecs_task_definition" "producer" {
  family                   = "${var.project_name}-producer"
  cpu                      = "256"           # 0.25 vCPU
  memory                   = "512"           # 512 MB
  network_mode             = "awsvpc"        # Required for Fargate
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn

  container_definitions = jsonencode([{
    name      = "producer"
    image     = var.container_image_producer
    essential = true

    # Pull from private GHCR using Secrets Manager
    repositoryCredentials = {
      credentialsParameter = aws_secretsmanager_secret.ghcr.arn
    }

    # Environment variables (non-sensitive)
    environment = [
      { name = "SERVICE_NAME", value = "producer" },
      { name = "TOPIC_NAME", value = "orders" },
      { name = "SLEEP_SECONDS", value = "2" }
    ]

    # Secrets from Secrets Manager (sensitive)
    secrets = [
      { name = "KAFKA_BOOTSTRAP_SERVERS", 
        valueFrom = "${aws_secretsmanager_secret.confluent.arn}:bootstrap_servers::" },
      { name = "CONFLUENT_API_KEY", 
        valueFrom = "${aws_secretsmanager_secret.confluent.arn}:api_key::" },
      { name = "CONFLUENT_API_SECRET", 
        valueFrom = "${aws_secretsmanager_secret.confluent.arn}:api_secret::" }
    ]

    # CloudWatch logging
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
```

#### ECS Service

```hcl
resource "aws_ecs_service" "producer" {
  name            = "${var.project_name}-producer-svc"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.producer.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = local.public_subnets
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = true  # Required for pulling images & external access
  }
}
```

**Services Deployed:**
| Service | CPU | Memory | Replicas | Purpose |
|---------|-----|--------|----------|---------|
| producer | 256 | 512 | 1 | Generate orders to Kafka |
| fraud | 256 | 512 | 1 | Consume & process fraud checks |
| payment | 256 | 512 | 1 | Consume & process payments |
| analytics | 256 | 512 | 1 | Consume & save to Couchbase |
| frontend | 256 | 512 | 2 | React UI (port 80) |
| backend | 512 | 1024 | 2 | FastAPI (port 8000) |

---

### 6. Application Load Balancer (`alb.tf`)

```hcl
resource "aws_lb" "ecs_alb" {
  name               = "${var.project_name}-alb-main"
  internal           = false              # Internet-facing
  load_balancer_type = "application"
  security_groups    = [local.alb_sg]
  subnets            = local.public_subnets
  idle_timeout       = 120                # Prevent 504 errors
}

# Frontend target group (port 80)
resource "aws_lb_target_group" "webapp_tg" {
  name        = "${var.project_name}-web-tg"
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"          # For Fargate
  vpc_id      = local.vpc_id

  health_check {
    path    = "/"
    matcher = "200,301,302"
  }
}

# Backend target group (port 8000)
resource "aws_lb_target_group" "backend_tg" {
  name        = "${var.project_name}-api-tg"
  port        = 8000
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = local.vpc_id

  health_check {
    path    = "/healthz"
    matcher = "200"
  }
}

# HTTP listener (default → frontend)
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.ecs_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.webapp_tg.arn
  }
}

# Route /api/* to backend
resource "aws_lb_listener_rule" "api_routing" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend_tg.arn
  }

  condition {
    path_pattern {
      values = ["/api/*", "/healthz", "/docs", "/openapi.json"]
    }
  }
}
```

**Traffic Flow:**
```
Internet → ALB:80 → /api/* → Backend:8000
                  → /*     → Frontend:80
```

---

## EKS Terraform Walkthrough

**Location:** `infra/terraform-eks/`

### File Structure

```
terraform-eks/
├── providers.tf         # AWS, Helm, Kubernetes, kubectl providers
├── backend.tf           # S3 remote state backend
├── variables.tf         # Input variables
├── vpc.tf               # VPC configuration
├── eks.tf               # EKS cluster and node groups
├── alb-controller.tf    # AWS Load Balancer Controller
├── argocd.tf            # ArgoCD + webapp deployment
├── route53.tf           # DNS configuration
├── cleanup.tf           # Pre-destroy cleanup script
├── outputs.tf           # Output values
└── terraform.tfvars     # Sensitive variables (gitignored)
```

---

### 1. Providers Configuration (`providers.tf`)

```hcl
terraform {
  required_providers {
    aws        = { source = "hashicorp/aws", version = "~> 5.0" }
    helm       = { source = "hashicorp/helm", version = "~> 2.12" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.25" }
    kubectl    = { source = "gavinbunney/kubectl", version = "~> 1.14" }
    time       = { source = "hashicorp/time", version = "~> 0.9" }
  }
}

provider "aws" {
  region = var.aws_region
}

# Helm provider - uses EKS cluster credentials
provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", var.cluster_name, "--region", var.aws_region]
    }
  }
}

# Kubernetes provider - same authentication
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", var.cluster_name, "--region", var.aws_region]
  }
}
```

**Key Points:**
- Uses `exec` authentication to get temporary tokens from AWS
- All providers connect to the same EKS cluster
- `kubectl` provider is for applying raw YAML manifests (ArgoCD Application)

---

### 2. VPC Configuration (`vpc.tf`)

```hcl
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.1.2"

  name = "${var.cluster_name}-vpc"
  cidr = "10.20.0.0/16"

  azs            = ["us-east-2a", "us-east-2b"]
  public_subnets = ["10.20.1.0/24", "10.20.2.0/24"]
  private_subnets = ["10.20.3.0/24", "10.20.4.0/24"]

  enable_nat_gateway = false   # Nodes use public IPs directly
  map_public_ip_on_launch = true

  # Required tags for EKS to discover subnets
  tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }

  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"  # For internet-facing ALB
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"  # For internal ALB
  }
}
```

**Cost Optimization:**
- No NAT Gateway (saves ~$30/month)
- Worker nodes get public IPs directly
- Subnets tagged for ALB auto-discovery

---

### 3. EKS Cluster (`eks.tf`)

```hcl
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.8.4"

  cluster_name    = var.cluster_name      # "keo-eks"
  cluster_version = "1.30"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = concat(module.vpc.private_subnets, module.vpc.public_subnets)

  enable_irsa = true  # IAM Roles for Service Accounts (required for ALB controller)

  # API endpoint access
  cluster_endpoint_public_access  = true   # Access from internet
  cluster_endpoint_private_access = true   # Access from VPC
  cluster_endpoint_public_access_cidrs = ["0.0.0.0/0"]

  # Auto-grant admin access to the user running Terraform
  enable_cluster_creator_admin_permissions = true

  # Managed node group
  eks_managed_node_groups = {
    general = {
      min_size     = 2
      max_size     = 4
      desired_size = 2

      instance_types = ["t3.medium"]  # 2 vCPU, 4GB RAM each
      subnet_ids     = module.vpc.public_subnets

      tags = { Name = "eks-node" }
    }
  }
}
```

**What This Creates:**
| Resource | Details |
|----------|---------|
| EKS Cluster | Kubernetes 1.30, managed control plane |
| Node Group | 2x t3.medium instances (auto-scaling 2-4) |
| OIDC Provider | For IRSA (service account → IAM role mapping) |
| Security Groups | Node-to-control-plane communication |
| IAM Roles | Node instance role, cluster role |

---

### 4. AWS Load Balancer Controller (`alb-controller.tf`)

The ALB Controller watches for Ingress resources and creates/manages AWS ALBs.

#### IAM Policy (Comprehensive permissions)

```hcl
resource "aws_iam_policy" "alb_controller" {
  name   = "${var.cluster_name}-alb-controller-policy"
  policy = jsonencode({
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:Describe*",
          "elasticloadbalancing:*",
          "acm:ListCertificates",
          "acm:DescribeCertificate",
          # ... many more permissions
        ]
        Resource = "*"
      }
    ]
  })
}
```

#### IAM Role with IRSA (Web Identity)

```hcl
resource "aws_iam_role" "alb_controller" {
  name = "${var.cluster_name}-alb-controller-role"

  assume_role_policy = jsonencode({
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = module.eks.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${oidc_url}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
          "${oidc_url}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}
```

#### Helm Installation

```hcl
resource "helm_release" "alb_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = "1.7.1"
  timeout    = 600

  set {
    name  = "clusterName"
    value = var.cluster_name
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.alb_controller.arn
  }

  set {
    name  = "vpcId"
    value = module.vpc.vpc_id
  }
}
```

**How IRSA Works:**
```
1. Pod runs with ServiceAccount "aws-load-balancer-controller"
2. AWS SDK in pod finds projected token via env vars
3. SDK calls STS AssumeRoleWithWebIdentity
4. STS validates token against OIDC provider
5. Pod gets temporary AWS credentials
```

---

### 5. ArgoCD & Application Deployment (`argocd.tf`)

#### ArgoCD Installation

```hcl
resource "kubernetes_namespace" "argocd" {
  metadata { name = "argocd" }
  lifecycle { ignore_changes = all }
}

resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  namespace  = kubernetes_namespace.argocd.metadata[0].name
  version    = "5.51.6"
  timeout    = 600

  set {
    name  = "server.service.type"
    value = "LoadBalancer"  # Expose ArgoCD UI
  }

  set {
    name  = "server.extraArgs[0]"
    value = "--insecure"    # HTTP only (no TLS)
  }
}
```

#### GHCR Pull Secret

```hcl
resource "kubernetes_secret" "ghcr" {
  metadata {
    name      = "ghcr"
    namespace = "default"
  }
  type = "kubernetes.io/dockerconfigjson"
  data = {
    ".dockerconfigjson" = jsonencode({
      auths = {
        "ghcr.io" = {
          username = var.ghcr_username
          password = var.ghcr_pat
          auth     = base64encode("${var.ghcr_username}:${var.ghcr_pat}")
        }
      }
    })
  }
}
```

#### ArgoCD Application (GitOps)

```hcl
resource "kubectl_manifest" "webapp_application" {
  yaml_body = <<-YAML
    apiVersion: argoproj.io/v1alpha1
    kind: Application
    metadata:
      name: webapp
      namespace: argocd
    spec:
      project: default
      source:
        repoURL: https://github.com/Aisalkyn85/kafka-enterprise-orders.git
        targetRevision: main
        path: k8s/charts/webapp           # Helm chart location
        helm:
          values: |
            frontendImage: ghcr.io/aisalkyn85/kafka-enterprise-orders/web-frontend:latest
            backendImage: ghcr.io/aisalkyn85/kafka-enterprise-orders/web-backend:latest
            backendPort: 8000
            replicaCount: 1
            ingress:
              enabled: false              # Terraform manages ingress
            couchbase:
              host: ${var.couchbase_host}
              bucket: ${var.couchbase_bucket}
              username: ${var.couchbase_username}
              password: ${var.couchbase_password}
      destination:
        server: https://kubernetes.default.svc
        namespace: default
      syncPolicy:
        automated:
          prune: true                     # Delete removed resources
          selfHeal: true                  # Revert manual changes
  YAML
}
```

**GitOps Flow:**
```
1. ArgoCD watches GitHub repo (k8s/charts/webapp)
2. On changes, ArgoCD syncs to cluster
3. Helm chart renders → Deployments, Services, ConfigMaps
4. selfHeal ensures desired state matches repo
```

#### Kubernetes Ingress (ALB)

```hcl
resource "kubernetes_ingress_v1" "webapp" {
  metadata {
    name      = "webapp"
    namespace = "default"
    annotations = {
      "kubernetes.io/ingress.class"                = "alb"
      "alb.ingress.kubernetes.io/scheme"           = "internet-facing"
      "alb.ingress.kubernetes.io/target-type"      = "ip"
      "alb.ingress.kubernetes.io/listen-ports"     = "[{\"HTTP\":80},{\"HTTPS\":443}]"
      "alb.ingress.kubernetes.io/ssl-redirect"     = "443"
      "alb.ingress.kubernetes.io/certificate-arn"  = var.certificate_arn
      "alb.ingress.kubernetes.io/healthcheck-path" = "/"
    }
  }

  spec {
    # Default rule (direct ALB access)
    rule {
      http {
        path {
          path      = "/api"
          path_type = "Prefix"
          backend {
            service {
              name = "webapp"
              port { number = 8000 }
            }
          }
        }
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "webapp"
              port { number = 80 }
            }
          }
        }
      }
    }

    # Domain-specific rule
    rule {
      host = var.app_domain  # orders.jumptotech.net
      http {
        # Same paths...
      }
    }
  }
}
```

**ALB Features Enabled:**
- HTTPS on port 443 with ACM certificate
- HTTP→HTTPS redirect
- Path-based routing (/api → backend, / → frontend)
- IP target type (direct pod IPs)

---

### 6. Route53 DNS (`route53.tf`)

```hcl
data "aws_route53_zone" "main" {
  name = var.domain_zone  # jumptotech.net
}

# Wait for ALB to provision (90 seconds)
resource "time_sleep" "wait_for_alb" {
  depends_on      = [kubernetes_ingress_v1.webapp]
  create_duration = "90s"
}

# Read ingress to get ALB hostname
data "kubernetes_ingress_v1" "webapp" {
  metadata {
    name      = kubernetes_ingress_v1.webapp.metadata[0].name
    namespace = "default"
  }
  depends_on = [time_sleep.wait_for_alb]
}

# Create A record pointing to ALB
resource "aws_route53_record" "webapp" {
  zone_id         = data.aws_route53_zone.main.zone_id
  name            = var.app_domain  # orders.jumptotech.net
  type            = "A"
  allow_overwrite = true

  alias {
    name                   = data.kubernetes_ingress_v1.webapp.status[0].load_balancer[0].ingress[0].hostname
    zone_id                = "Z3AADJGX6KTTL2"  # us-east-2 ALB zone
    evaluate_target_health = true
  }
}
```

**DNS Flow:**
```
orders.jumptotech.net → Route53 A Record (Alias) → ALB → Pods
```

---

### 7. Cleanup Script (`cleanup.tf`)

Handles resources created by Kubernetes that Terraform doesn't know about:

```hcl
resource "null_resource" "cleanup_k8s_resources" {
  triggers = {
    vpc_id  = module.vpc.vpc_id
    region  = var.aws_region
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      # Delete ALBs created by ingress controller
      aws elbv2 describe-load-balancers --query "LoadBalancers[?VpcId=='${vpc_id}']..."
      
      # Delete target groups
      aws elbv2 delete-target-group...
      
      # Clean security groups
      aws ec2 delete-security-group...
      
      # Release EIPs
      aws ec2 release-address...
      
      # Delete NAT gateways
      aws ec2 delete-nat-gateway...
    EOT
    interpreter = ["powershell", "-Command"]
  }
}
```

**Why Needed:**
- ALB Controller creates ALBs outside of Terraform
- These must be deleted before VPC can be destroyed
- Prevents "DependencyViolation" errors

---

## Comparison: ECS vs EKS

| Aspect | ECS | EKS |
|--------|-----|-----|
| **Complexity** | Simpler | More complex |
| **Cost** | Lower (no control plane fee) | Higher ($0.10/hr control plane) |
| **Scaling** | Per-service | Pod autoscaling + node autoscaling |
| **Deployment** | Terraform directly | ArgoCD (GitOps) |
| **Ingress** | ALB listener rules | Kubernetes Ingress + ALB Controller |
| **Secrets** | AWS Secrets Manager | Kubernetes Secrets |
| **Logging** | CloudWatch native | CloudWatch or external |
| **Use Case** | Simple containerized apps | Complex microservices, K8s expertise |

---

## Deployment Instructions

### ECS Deployment

```powershell
cd infra/terraform-ecs

# 1. Edit terraform.tfvars with secrets
notepad terraform.tfvars

# 2. Initialize and apply
terraform init
terraform plan
terraform apply

# 3. Access the app
# Output: webapp_url = "http://kafka-enterprise-orders-alb-main-xxx.us-east-2.elb.amazonaws.com"
```

### EKS Deployment

```powershell
cd infra/terraform-eks

# 1. Edit terraform.tfvars with secrets
notepad terraform.tfvars

# 2. Initialize and apply
terraform init
terraform plan
terraform apply

# 3. Configure kubectl
aws eks update-kubeconfig --name keo-eks --region us-east-2

# 4. Access the app
# Output: webapp_url = "https://orders.jumptotech.net"

# 5. Get ArgoCD password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
```

### Clean Destroy (EKS)

```powershell
cd infra/terraform-eks

# This triggers the cleanup script automatically
terraform destroy -auto-approve
```

---

## Summary

Both ECS and EKS configurations deploy the same application with different approaches:

- **ECS**: Direct container orchestration with Terraform, simpler but less flexible
- **EKS**: Kubernetes-native with GitOps (ArgoCD), more powerful but requires K8s knowledge

Choose ECS for straightforward deployments, EKS for teams with Kubernetes expertise or needing advanced features like service mesh, custom operators, or multi-cloud portability.

