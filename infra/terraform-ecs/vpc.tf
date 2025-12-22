# VPC - created if no existing VPC provided
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.0.0"

  create_vpc = var.existing_vpc_id == ""

  name = "${var.project_name}-vpc"
  cidr = "10.30.0.0/16"

  azs             = ["us-east-2a", "us-east-2b"]
  private_subnets = ["10.30.1.0/24", "10.30.2.0/24"]
  public_subnets  = ["10.30.3.0/24", "10.30.4.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true

  tags = { Project = var.project_name }
}

# ALB Security Group
resource "aws_security_group" "alb" {
  count       = var.existing_alb_sg_id == "" ? 1 : 0
  name        = "${var.project_name}-alb-sg"
  description = "ALB"
  vpc_id      = var.existing_vpc_id != "" ? var.existing_vpc_id : module.vpc.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-alb-sg" }
}
