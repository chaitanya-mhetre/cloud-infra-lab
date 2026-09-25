output "target_group_arn" {
  description = "API target group (ECS service attaches here)."
  value       = aws_lb_target_group.api.arn
}

output "listener_arn" {
  description = "The listener serving traffic (HTTPS if TLS, else HTTP)."
  value       = local.tls ? aws_lb_listener.https[0].arn : aws_lb_listener.http.arn
}

output "alb_arn_suffix" {
  description = "For CloudWatch ALB metrics dimensions."
  value       = aws_lb.this.arn_suffix
}

output "target_group_arn_suffix" {
  description = "For CloudWatch target group metrics dimensions."
  value       = aws_lb_target_group.api.arn_suffix
}

output "base_url" {
  description = "Public base URL."
  value       = local.tls ? "https://${var.domain_name}" : "http://${aws_lb.this.dns_name}"
}

output "alb_arn" {
  description = "ALB ARN (for the WAF association)."
  value       = aws_lb.this.arn
}
