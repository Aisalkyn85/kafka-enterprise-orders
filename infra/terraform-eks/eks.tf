module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.8.4"

  cluster_name    = var.cluster_name
  cluster_version = "1.30"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = concat(module.vpc.private_subnets, module.vpc.public_subnets)

  enable_irsa = true

  # ----------------------------------------------------
  # CONTROL PLANE ENDPOINT ACCESS (IMPORTANT!)
  # ----------------------------------------------------
  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true

  cluster_endpoint_public_access_cidrs = ["0.0.0.0/0"]

  # ----------------------------------------------------
  # CLUSTER ACCESS - Allow current IAM user/role
  # ----------------------------------------------------
  enable_cluster_creator_admin_permissions = true

  # ----------------------------------------------------
  # NODE GROUP
  # ----------------------------------------------------
  eks_managed_node_groups = {
    general = {
      min_size     = 2
      max_size     = 4
      desired_size = 2

      instance_types = ["t3.medium"]

      # Node placement (reliable choice)
      subnet_ids = module.vpc.public_subnets

      tags = {
        Name = "eks-node"
      }
    }
  }
}

