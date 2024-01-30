################################################################################
# TEST Cluster COMMs by deploying the Metrics Server Addon
################################################################################
#module "eks_blueprints_addons" {
#  source  = "aws-ia/eks-blueprints-addons/aws"
#  version = "~> 1.12.0" #ensure to update this to the latest/desired version
#
#  enable metrics_server = true
#}