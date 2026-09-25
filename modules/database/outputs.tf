output "endpoint" {
  description = "host:port"
  value       = aws_db_instance.this.endpoint
}

output "address" {
  description = "Hostname."
  value       = aws_db_instance.this.address
}

output "port" {
  description = "Port."
  value       = aws_db_instance.this.port
}

output "instance_id" {
  description = "RDS identifier (for alarms)."
  value       = aws_db_instance.this.identifier
}

output "master_secret_arn" {
  description = "Secrets Manager ARN holding the generated master credentials."
  value       = aws_db_instance.this.master_user_secret[0].secret_arn
}
