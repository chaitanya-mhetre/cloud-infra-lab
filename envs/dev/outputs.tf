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
