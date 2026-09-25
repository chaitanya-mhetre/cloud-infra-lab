output "instance_id" {
  description = "EC2 instance ID (use with `aws ssm start-session --target`)."
  value       = aws_instance.host.id
}

output "public_ip" {
  description = "Elastic IP of the host. Point domain_name's A record here."
  value       = aws_eip.host.public_ip
}

output "base_url" {
  description = "URL for smoke tests."
  value       = var.domain_name == "" ? "http://${aws_eip.host.public_ip}" : "https://${var.domain_name}"
}

output "log_group_name" {
  description = "CloudWatch log group receiving container logs."
  value       = aws_cloudwatch_log_group.host.name
}

output "log_group_arn" {
  description = "ARN of the container log group (for IAM scoping)."
  value       = aws_cloudwatch_log_group.host.arn
}
