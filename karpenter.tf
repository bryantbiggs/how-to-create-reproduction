module "eks_blueprints_addons" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "~> 1.15.1"

  # --------------------------------------------------------------------------------------------------------------------

  enable_karpenter                           = true
  karpenter_enable_instance_profile_creation = true
  karpenter_enable_spot_termination          = true

  karpenter_node = {
    iam_role_use_name_prefix = false
    # false: karpenter_node_iam_role_name = "karpenter-reproduction"
    # true:  karpenter_node_iam_role_name = "karpenter-reproduction-20240215002156918200000001"
  }

  # Added configuration show below
  karpenter = {
    chart_version   = "v0.34.0"
    irsa_tag_key    = "aws:ResourceTag/kubernetes.io/cluster/reproduction"
    irsa_tag_values = ["*"]
    values = [
      file("${path.module}/karpenter/values.yaml")
    ]
  }

  # --------------------------------------------------------------------------------------------------------------------

  enable_metrics_server = false

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn
}
