output "primary_endpoint" {
  description = "Primary endpoint hostname."
  value       = aws_elasticache_replication_group.this.primary_endpoint_address
}

output "url_base" {
  description = "rediss:// base URL (TLS). Append /<db>."
  value       = "rediss://${aws_elasticache_replication_group.this.primary_endpoint_address}:6379"
}

output "replication_group_id" {
  description = "ID (for alarms)."
  value       = aws_elasticache_replication_group.this.id
}
