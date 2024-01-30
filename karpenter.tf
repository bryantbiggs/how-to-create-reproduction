module "eks_blueprints_addons" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "~> 1.13.0"

  enable_karpenter                           = true
  karpenter_enable_instance_profile_creation = true
  # Added configuration show below
  karpenter = {
    irsa_tag_key    = "aws:ResourceTag/kubernetes.io/cluster/reproduction"
    irsa_tag_values = ["*"]
  }

  enable_metrics_server = true

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn
}
