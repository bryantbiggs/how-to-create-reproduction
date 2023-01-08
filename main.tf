terraform {
  required_version = "~> 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.47"
    }
  }
}

provider "aws" {
  region = local.region
}

################################################################################
# Common Locals
################################################################################

locals {
  name   = "reproduction"
  region = "us-east-1"

  vpc_cidr = "10.0.0.0/16"
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)

  tags = {
    Repository = "github.com/bryantbiggs/how-to-create-reproduction"
  }
}

data "aws_availability_zones" "available" {}

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
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  ]) : k => v }

  policy_arn = each.value
  role       = aws_iam_role.this.name
}

################################################################################
# Cluster
################################################################################

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "19.5.1"

  cluster_name    = local.name
  cluster_version = "1.24"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  tags = local.tags
}

module "eks_managed_node_group" {
  source  = "terraform-aws-modules/eks/aws//modules/eks-managed-node-group"
  version = "19.5.1"

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
################################################################################

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 3.18"

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
  default_security_group_tags   = { Name = "${local.name}-default" }

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }

  tags = local.tags
}
