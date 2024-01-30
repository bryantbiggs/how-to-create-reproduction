/*
  ----------------------------------------------------------------------------------------------------------------------
  TEST Cluster COMMs by deploying the Metrics Server Addon
  https://github.com/aws-ia/terraform-aws-eks-blueprints-addons/releases
  ----------------------------------------------------------------------------------------------------------------------
*/

#module "eks_blueprints_addons" {
#  source  = "aws-ia/eks-blueprints-addons/aws"
#  version = "~> 1.13.0" # update to the latest/desired version
#
#  enable_metrics_server = true
#
#  cluster_name      = module.eks.cluster_name
#  cluster_endpoint  = module.eks.cluster_endpoint
#  cluster_version   = module.eks.cluster_version
#  oidc_provider_arn = module.eks.oidc_provider_arn
#}
