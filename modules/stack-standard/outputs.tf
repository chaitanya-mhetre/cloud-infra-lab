output "base_url" {
  description = "Public base URL (smoke tests)."
  value       = module.loadbalancer.base_url
}

output "ecs_cluster_name" {
  description = "ECS cluster (scripts/ecs-deploy.sh)."
  value       = module.ecs.cluster_name
}

output "db_endpoint" {
  description = "RDS endpoint (private)."
  value       = module.database.endpoint
}

output "db_master_secret_arn" {
  description = "Secrets Manager ARN of the generated master credentials."
  value       = module.database.master_secret_arn
}

output "ssm_path_prefix" {
  description = "Where app secrets live."
  value       = module.secrets.path_prefix
}

output "uploads_bucket" {
  description = "Uploads bucket."
  value       = module.storage.bucket_name
}

output "github_apply_role_arn" {
  description = "AWS_APPLY_ROLE_ARN for GitHub environment infra-<env>."
  value       = module.iam.github_apply_role_arn
}

output "github_deploy_role_arn" {
  description = "AWS_DEPLOY_ROLE_ARN for the app repo."
  value       = module.iam.github_deploy_role_arn
}

# Handy for observability wiring.
output "ids" {
  description = "Resource identifiers for alarms/dashboards."
  value = {
    alb_arn_suffix          = module.loadbalancer.alb_arn_suffix
    target_group_arn_suffix = module.loadbalancer.target_group_arn_suffix
    ecs_cluster             = module.ecs.cluster_name
    rds_instance_id         = module.database.instance_id
    redis_group_id          = module.cache.replication_group_id
    log_group_name          = module.ecs.log_group_name
  }
}
