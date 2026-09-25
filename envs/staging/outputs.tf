output "base_url" {
  description = "Public base URL."
  value       = module.stack.base_url
}

output "ecs_cluster_name" {
  description = "ECS cluster name."
  value       = module.stack.ecs_cluster_name
}

output "ssm_path_prefix" {
  description = "Secrets path."
  value       = module.stack.ssm_path_prefix
}

output "db_master_secret_arn" {
  description = "RDS master credentials secret."
  value       = module.stack.db_master_secret_arn
}

output "github_apply_role_arn" {
  description = "Apply role for GitHub environment infra-<env>."
  value       = module.stack.github_apply_role_arn
}

output "github_deploy_role_arn" {
  description = "Deploy role for the app repo."
  value       = module.stack.github_deploy_role_arn
}
