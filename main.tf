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
  user_arn = split("/", data.aws_caller_identity.current.arn)[0]

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
  version = "20.2.1" # https://github.com/terraform-aws-modules/terraform-aws-eks/releases

  cluster_name                   = local.name
  cluster_version                = local.eks_version
  cluster_endpoint_public_access = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets
  control_plane_subnet_ids = module.vpc.intra_subnets
  cluster_ip_family = "ipv4"
  create_cni_ipv6_iam_policy = false

  # Cluster Access: Break-Glass Accounts
  authentication_mode                      = "API_AND_CONFIG_MAP"
  enable_cluster_creator_admin_permissions = true

  tags = merge(local.tags, {
    "karpenter.sh/discovery" = local.name
  })
}

################################################################################
# Managed Node Group: ~4m43s
# https://registry.terraform.io/modules/terraform-aws-modules/eks/aws/latest/submodules/eks-managed-node-group
################################################################################

module "eks_managed_node_group" {
  source  = "terraform-aws-modules/eks/aws//modules/eks-managed-node-group"
  version = "20.2.1" # https://github.com/terraform-aws-modules/terraform-aws-eks/releases

  name            = "${local.name}-mng"
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

module "eks_blueprints_addons" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "~> 1.15.1"

  # --------------------------------------------------------------------------------------------------------------------
  # Uncomment this block to test Karpenter
  # ALSO:
  #   * Uncomment the aws_auth_roles block below
  #   * Uncomment the related Output at the bottom
#  enable_karpenter                           = true
#  karpenter_enable_instance_profile_creation = true
#  karpenter_enable_spot_termination          = true
#
#  karpenter_node = {
#    iam_role_use_name_prefix = false
#  }
#
#  # Added configuration show below
#  karpenter = {
#    chart_version   = "v0.34.0"
#    irsa_tag_key    = "aws:ResourceTag/kubernetes.io/cluster/reproduction"
#    irsa_tag_values = ["*"]
#    values = [
#      file("${path.module}/karpenter/values.yaml")
#    ]
#  }

  # --------------------------------------------------------------------------------------------------------------------

  enable_metrics_server = false

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn
}


################################################################################
# VPC
# https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws/latest
################################################################################

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.5.2" # https://github.com/terraform-aws-modules/terraform-aws-vpc/releases

  name = local.name
  cidr = local.vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 48)]
  intra_subnets   = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 52)]

  map_public_ip_on_launch = true
  enable_nat_gateway      = true
  single_nat_gateway      = true
  one_nat_gateway_per_az  = false

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
    "karpenter.sh/discovery" = local.name
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
    "karpenter.sh/discovery"          = local.name
  }

  tags = local.tags
}

################################################################################
# aws-auth ConfigMap management
################################################################################
module "aws_auth" {
  source  = "terraform-aws-modules/eks/aws//modules/aws-auth"
  version = "20.2.1"

  # When all else fails, there is still direct access.
  manage_aws_auth_configmap = true

#  aws_auth_roles = [
#    # We need to add in the Karpenter node IAM role for nodes launched by Karpenter
#    {
#      rolearn  = module.eks_blueprints_addons.karpenter.node_iam_role_arn
#      username = "system:node:{{EC2PrivateDNSName}}"
#      groups = [
#        "system:bootstrappers",
#        "system:nodes",
#      ]
#    },
#  ]

  aws_auth_users = [
    {
      userarn  = "${local.user_arn}/tthomas@vivsoft.io"
      username = "tthomas@vivsoft.io"
      groups   = ["system:masters"]
    },
  ]
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
    "arn:${local.part}:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:${local.part}:iam::aws:policy/service-role/AmazonEC2RoleforSSM"
  ]) : k => v }

  policy_arn = each.value
  role       = aws_iam_role.this.name
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
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.25.2"
    }
  }
}

provider "aws" {
  region = local.region
  alias  = "virginia"
}

################################################################################
# Optional: Support for eks-blueprints-addons
# Helps when you need it, doesn't hurt anything if you don't
################################################################################
# Discover the Cluster Token for AuthN
data "aws_eks_cluster_auth" "cluster_auth" {
  name = module.eks.cluster_name
}

### AuthN: Helm <> EKS
# AuthN so Helm Can Install Charts
provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.cluster_auth.token
  }
}

### AuthN: Terraform <> EKS
# https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs
# https://github.com/hashicorp/terraform-provider-kubernetes/releases
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1"
    command     = "aws"
    # This requires the awscli to be installed locally where Terraform is executed
    args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

/*
  ----------------------------------------------------------------------------------------------------------------------
                 ONLY USE FOR EMERGENCIES
  1. Get your current IP: echo "$(curl -s4 icanhazip.com)/32"
  2. Uncomment the security_group resource below
  3. Replace $myHomeIPAddr with Add your IP
  4. terraform apply -no-color -auto-approve
  ----------------------------------------------------------------------------------------------------------------------
*/
#resource "aws_vpc_security_group_ingress_rule" "allow_ssh_ipv4" {
#  security_group_id = module.vpc.default_security_group_id
#  description       = "Allow SSH inbound from home"
#  cidr_ipv4         = "${officeIPAddr}/32"
#  #cidr_ipv6         = "2603:8000:3e00:da:6c35:ef4e:f00a:5e51"
#  from_port   = 22
#  to_port     = 22
#  ip_protocol = "tcp"
#}

#resource "aws_vpc_security_group_ingress_rule" "allow_icmp_ipv4" {
#  security_group_id = module.vpc.default_security_group_id
#  description       = "Allow ICMP/PING inbound from home"
#  cidr_ipv4         = "${officeIPAddr}/32"
#  #cidr_ipv6         = "2603:8000:3e00:da:6c35:ef4e:f00a:5e51"
#  from_port         = 8
#  to_port           = 0
#  ip_protocol       = "icmp"
#}

################################################################################
# Outputs
################################################################################
output "reproduction-region" {
  value = local.region
}

output "reproduction-project" {
  value = local.name
}

output "reproduction-account" {
  value = data.aws_caller_identity.current.account_id
}

output "reproduction-part" {
  value = local.part
}

#output "karpenter_node_iam_role_name" {
#  value = module.eks_blueprints_addons.karpenter.node_iam_role_name
#}