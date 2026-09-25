variable "name" {
  description = "Name prefix."
  type        = string
}

variable "app_subnet_ids" {
  description = "Private app subnets for tasks."
  type        = list(string)
}

variable "app_security_group_ids" {
  description = "App tier SG(s)."
  type        = list(string)
}

variable "target_group_arn" {
  description = "ALB target group for the API service."
  type        = string
}

variable "execution_role_arn" {
  description = "Task execution role (modules/iam)."
  type        = string
}

variable "task_role_arn" {
  description = "Task role (modules/iam)."
  type        = string
}

variable "image_repo" {
  description = "ECR repository URL."
  type        = string
}

variable "image_tag" {
  description = "Initial image tag (git SHA). Later deploys register new revisions via scripts/ecs-deploy.sh; Terraform ignores task_definition drift on services."
  type        = string
}

variable "secret_arns" {
  description = "Map ENV_SUFFIX -> SSM parameter ARN, injected as SLOTWISE_<SUFFIX>."
  type        = map(string)
}

variable "environment" {
  description = "Plain environment variables."
  type        = map(string)
  default     = {}
}

variable "log_retention_days" {
  description = "Container log retention."
  type        = number
  default     = 14
}

variable "app_port" {
  description = "API container port."
  type        = number
  default     = 8000
}

variable "api" {
  description = "API service sizing + autoscaling."
  type = object({
    cpu        = number
    memory     = number
    desired    = number
    min        = number
    max        = number
    target_cpu = number
  })
  default = { cpu = 512, memory = 1024, desired = 2, min = 2, max = 6, target_cpu = 60 }
}

variable "worker" {
  description = "Worker service sizing + autoscaling."
  type = object({
    cpu     = number
    memory  = number
    desired = number
    min     = number
    max     = number
  })
  default = { cpu = 512, memory = 1024, desired = 1, min = 1, max = 3 }
}

variable "commands" {
  description = "Container commands (match production-fastapi's docker-compose.yml)."
  type = object({
    api     = list(string)
    worker  = list(string)
    beat    = list(string)
    relay   = list(string)
    migrate = list(string)
  })
  default = {
    api     = ["uvicorn", "slotwise.main:app", "--host", "0.0.0.0", "--port", "8000", "--proxy-headers", "--forwarded-allow-ips", "*", "--timeout-graceful-shutdown", "20"]
    worker  = ["celery", "-A", "slotwise.worker.celery_app", "worker", "--pool", "threads", "--concurrency", "8", "-l", "info"]
    beat    = ["celery", "-A", "slotwise.worker.celery_app", "beat", "-l", "info", "--schedule", "/tmp/celerybeat-schedule"]
    relay   = ["python", "-m", "slotwise.outbox.relay"]
    migrate = ["alembic", "upgrade", "head"]
  }
}

variable "use_spot_for_workers" {
  description = "Run worker/beat on FARGATE_SPOT (~up to 70% cheaper, can be interrupted; Celery acks-late makes that safe)."
  type        = bool
  default     = true
}

variable "container_insights" {
  description = "ECS Container Insights (extra CloudWatch cost)."
  type        = bool
  default     = false
}
