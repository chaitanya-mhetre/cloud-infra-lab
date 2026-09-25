output "cluster_name" {
  description = "ECS cluster name."
  value       = aws_ecs_cluster.this.name
}

output "cluster_arn" {
  description = "ECS cluster ARN (scopes the deploy role)."
  value       = aws_ecs_cluster.this.arn
}

output "log_group_name" {
  description = "Container log group."
  value       = aws_cloudwatch_log_group.app.name
}

output "log_group_arn" {
  description = "Container log group ARN."
  value       = aws_cloudwatch_log_group.app.arn
}

output "service_names" {
  description = "ECS service names."
  value       = [aws_ecs_service.api.name, aws_ecs_service.worker.name, aws_ecs_service.beat.name, aws_ecs_service.relay.name]
}

output "migrate_task_family" {
  description = "Task definition family for the one-off migration task."
  value       = aws_ecs_task_definition.this["migrate"].family
}

output "network_config" {
  description = "awsvpc config used by ecs-deploy.sh to run the migration task."
  value = {
    subnets         = var.app_subnet_ids
    security_groups = var.app_security_group_ids
  }
}
