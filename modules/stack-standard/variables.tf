variable "project" {
  description = "Project short name."
  type        = string
}

variable "env" {
  description = "Environment name (staging, prod-like)."
  type        = string
}

variable "cidr_block" {
  description = "VPC CIDR (different per env so VPCs could be peered later)."
  type        = string
}

variable "image_tag" {
  description = "Initial image tag for task definitions (git SHA already in ECR)."
  type        = string
}

variable "domain_name" {
  description = "Public hostname (empty = HTTP on the ALB DNS name, demo only)."
  type        = string
  default     = ""
}

variable "route53_zone_id" {
  description = "Hosted zone for domain_name."
  type        = string
  default     = ""
}

variable "enable_interface_endpoints" {
  description = "Interface VPC endpoints (ECR/SSM/Logs). Cuts NAT data charges, adds hourly cost."
  type        = bool
  default     = false
}

variable "db" {
  description = "RDS settings."
  type = object({
    instance_class        = string
    multi_az              = bool
    backup_retention_days = number
    deletion_protection   = bool
    skip_final_snapshot   = bool
  })
}

variable "cache_node_type" {
  description = "ElastiCache node type."
  type        = string
  default     = "cache.t4g.micro"
}

variable "cache_replicas" {
  description = "Redis replicas (>=1 enables failover)."
  type        = number
  default     = 0
}

variable "api" {
  description = "API sizing/autoscaling (see modules/compute-ecs)."
  type = object({
    cpu        = number
    memory     = number
    desired    = number
    min        = number
    max        = number
    target_cpu = number
  })
}

variable "worker" {
  description = "Worker sizing/autoscaling."
  type = object({
    cpu     = number
    memory  = number
    desired = number
    min     = number
    max     = number
  })
}

variable "log_retention_days" {
  description = "App log retention."
  type        = number
  default     = 14
}

variable "alarm_email" {
  description = "Email subscribed to alarms (confirm the SNS subscription email)."
  type        = string
  default     = ""
}

variable "disposable" {
  description = "True = teardown-friendly (force_destroy buckets, no final snapshot)."
  type        = bool
  default     = true
}

variable "github_owner" {
  description = "GitHub owner for OIDC trust."
  type        = string
}

variable "app_repos" {
  description = "App repos allowed to deploy here."
  type        = list(string)
  default     = ["production-fastapi"]
}
