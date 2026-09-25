output "vpc_id" {
  description = "Dev VPC."
  value       = module.network.vpc_id
}

output "instance_id" {
  description = "Host instance ID: aws ssm start-session --target <id>"
  value       = module.host.instance_id
}

output "base_url" {
  description = "Base URL for scripts/smoke.sh."
  value       = module.host.base_url
}

output "ssm_path_prefix" {
  description = "Where to put secrets: scripts/put-secret.sh dev <NAME>"
  value       = module.secrets.path_prefix
}

output "github_apply_role_arn" {
  description = "Set as AWS_APPLY_ROLE_ARN on the GitHub environment infra-dev."
  value       = module.iam.github_apply_role_arn
}

output "github_deploy_role_arn" {
  description = "Set as AWS_DEPLOY_ROLE_ARN in the production-fastapi repo."
  value       = module.iam.github_deploy_role_arn
}
