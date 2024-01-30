################################################################################
# Discovery and Common Locals
################################################################################
data "aws_availability_zones" "available" {}
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  name        = "reproduction"
  region      = "us-gov-east-1"
  eks_version = "1.29"

  vpc_cidr = "10.0.0.0/16"
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)
  part     = data.aws_partition.current.partition

  tags = {
    Repository = "github.com/bryantbiggs/how-to-create-reproduction"
  }
}

################################################################################
# Cluster: ~8m7s
# https://registry.terraform.io/modules/terraform-aws-modules/eks/aws/latest
################################################################################

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "19.21.0" # https://github.com/terraform-aws-modules/terraform-aws-eks/releases

  cluster_name                   = local.name
  cluster_version                = local.eks_version
  cluster_endpoint_public_access = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  aws_auth_roles = [
    # We need to add in the Karpenter node IAM role for nodes launched by Karpenter
    {
      rolearn  = module.eks_blueprints_addons.karpenter.node_iam_role_arn
      username = "system:node:{{EC2PrivateDNSName}}"
      groups = [
        "system:bootstrappers",
        "system:nodes",
      ]
    },
  ]

  tags = local.tags
}

################################################################################
# Managed Node Group: ~4m43s
# https://registry.terraform.io/modules/terraform-aws-modules/eks/aws/latest/submodules/eks-managed-node-group
################################################################################

module "eks_managed_node_group" {
  source  = "terraform-aws-modules/eks/aws//modules/eks-managed-node-group"
  version = "19.21.0" # https://github.com/terraform-aws-modules/terraform-aws-eks/releases

  name            = "separate"
  cluster_name    = module.eks.cluster_name
  cluster_version = module.eks.cluster_version

  subnet_ids = module.vpc.private_subnets
  vpc_security_group_ids = [
    module.eks.cluster_primary_security_group_id,
    module.eks.cluster_security_group_id,
  ]

  create_iam_role = false
  iam_role_arn    = aws_iam_role.this.arn

  min_size     = 1
  max_size     = 3
  desired_size = 1

  tags = local.tags
}

################################################################################
# VPC
# https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws/latest
################################################################################

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.5.1" # https://github.com/terraform-aws-modules/terraform-aws-vpc/releases

  name = local.name
  cidr = local.vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 48)]
  intra_subnets   = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 52)]

  enable_nat_gateway     = true
  single_nat_gateway     = true
  one_nat_gateway_per_az = false

  manage_default_network_acl    = true
  default_network_acl_tags      = { Name = "${local.name}-default" }
  manage_default_route_table    = true
  default_route_table_tags      = { Name = "${local.name}-default" }
  manage_default_security_group = true

  default_security_group_tags = {
    Name                     = "${local.name}-default",
    "karpenter.sh/discovery" = local.name
  }

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
    "karpenter.sh/discovery"          = local.name
  }

  tags = local.tags
}

################################################################################
# Provider Versions
################################################################################

# https://github.com/hashicorp/terraform/releases
terraform {
  required_version = "~> 1.0"

  required_providers {
    # https://github.com/hashicorp/terraform-provider-aws/releases
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.34.0"
    }
  }
}

provider "aws" {
  region = local.region
}

################################################################################
# External Role
################################################################################
data "aws_iam_policy_document" "assume_role_policy" {
  statement {
    sid     = "EKSNodeAssumeRole"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name_prefix = "${local.name}-"

  assume_role_policy    = data.aws_iam_policy_document.assume_role_policy.json
  force_detach_policies = true

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "this" {
  for_each = { for k, v in toset([
    "arn:${local.part}:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:${local.part}:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:${local.part}:iam::aws:policy/AmazonEKS_CNI_Policy"
  ]) : k => v }

  policy_arn = each.value
  role       = aws_iam_role.this.name
}

################################################################################
# Optional: Support for eks-blueprints-addons
# Helps when you need it, doesn't hurt anything if you don't
################################################################################
data "aws_eks_cluster_auth" "cluster_auth" {
  name = module.eks.cluster_name
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.cluster_auth.token
  }
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    # This requires the awscli to be installed locally where Terraform is executed
    args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}
