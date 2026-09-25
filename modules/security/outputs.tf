output "alb_sg_id" {
  description = "ALB security group (null in low-cost mode)."
  value       = one(aws_security_group.alb[*].id)
}

output "app_sg_id" {
  description = "App tier security group."
  value       = aws_security_group.app.id
}

output "db_sg_id" {
  description = "Database security group."
  value       = aws_security_group.db.id
}

output "cache_sg_id" {
  description = "Cache security group (null in low-cost mode)."
  value       = one(aws_security_group.cache[*].id)
}
