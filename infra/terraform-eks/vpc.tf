module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.1.2"

  name = "${var.cluster_name}-vpc"
  cidr = var.vpc_cidr

  # 2 AZs
  azs             = ["us-east-2a", "us-east-2b"]

  # Worker nodes will live in PUBLIC subnets
  public_subnets = var.public_subnets

  # Private subnets ONLY used by control plane endpoint
  private_subnets = var.private_subnets

  enable_nat_gateway = false   # IMPORTANT
  enable_vpn_gateway = false

  map_public_ip_on_launch = true  # Nodes get public IPs

  tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }

  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }
}

