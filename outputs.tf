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