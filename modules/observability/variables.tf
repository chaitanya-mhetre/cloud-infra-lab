variable "name" {
  description = "Name prefix."
  type        = string
}

variable "alarm_email" {
  description = "Email subscribed to the alarm topic (AWS sends a confirmation mail). Empty = topic only."
  type        = string
  default     = ""
}

variable "alb_arn_suffix" {
  description = "ALB ARN suffix (null = skip ALB alarms)."
  type        = string
  default     = null
}

variable "target_group_arn_suffix" {
  description = "Target group ARN suffix."
  type        = string
  default     = null
}

variable "ecs_cluster" {
  description = "ECS cluster name (null = skip ECS alarms)."
  type        = string
  default     = null
}

variable "rds_instance_id" {
  description = "RDS identifier (null = skip RDS alarms)."
  type        = string
  default     = null
}

variable "redis_group_id" {
  description = "ElastiCache replication group ID (null = skip Redis alarms)."
  type        = string
  default     = null
}

variable "app_log_group_name" {
  description = "App log group for the error-rate metric filter (JSON logs with a `level` field)."
  type        = string
  default     = null
}

variable "ec2_instance_id" {
  description = "Low-cost host instance ID (null = skip host alarms)."
  type        = string
  default     = null
}

variable "thresholds" {
  description = "Alarm thresholds. Starting points, tune from real traffic."
  type = object({
    http_5xx_rate_pct      = number
    p95_latency_seconds    = number
    ecs_cpu_pct            = number
    ecs_memory_pct         = number
    rds_cpu_pct            = number
    rds_free_storage_bytes = number
    redis_memory_pct       = number
    app_errors_per_5min    = number
  })
  default = {
    http_5xx_rate_pct      = 2
    p95_latency_seconds    = 1.5
    ecs_cpu_pct            = 85
    ecs_memory_pct         = 85
    rds_cpu_pct            = 80
    rds_free_storage_bytes = 2147483648 # 2 GiB
    redis_memory_pct       = 75
    app_errors_per_5min    = 20
  }
}
