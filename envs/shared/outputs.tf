output "repository_urls" {
  description = "ECR repository URLs."
  value       = module.registry.repository_urls
}

output "github_plan_role_arn" {
  description = "Set as repo variable AWS_PLAN_ROLE_ARN in the infra repo."
  value       = module.github_plan.github_plan_role_arn
}
