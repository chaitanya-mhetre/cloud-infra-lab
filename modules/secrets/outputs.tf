output "path_prefix" {
  description = "SSM path prefix the app reads."
  value       = var.path_prefix
}

output "secret_arns" {
  description = "Map of name -> SSM parameter ARN (for ECS task definition `secrets`)."
  value       = merge({ for k, p in aws_ssm_parameter.secret : k => p.arn }, { for k, p in aws_ssm_parameter.plain : k => p.arn })
}
