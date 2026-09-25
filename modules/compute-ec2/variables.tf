variable "name" {
  description = "Name prefix."
  type        = string
}

variable "subnet_id" {
  description = "PUBLIC subnet for the host (low-cost mode has no NAT/ALB)."
  type        = string
}

variable "security_group_ids" {
  description = "Security groups for the host (the app SG from modules/security in lowcost mode)."
  type        = list(string)
}

variable "instance_type" {
  description = "Graviton instance type. t4g.small = 2 vCPU burstable / 2 GiB."
  type        = string
  default     = "t4g.small"
}

variable "root_volume_gb" {
  description = "Root EBS size (gp3)."
  type        = number
  default     = 20
}

variable "instance_profile_name" {
  description = "IAM instance profile (modules/iam create_ec2_role)."
  type        = string
}

variable "app_name" {
  description = "Application name; used in paths and the SSM prefix."
  type        = string
  default     = "slotwise"
}

variable "ssm_path_prefix" {
  description = "Where the host reads its .env from (modules/secrets)."
  type        = string
}

variable "api_image_repo" {
  description = "ECR repository URL for the API/worker image (tag is chosen at deploy time)."
  type        = string
}

variable "initial_image_tag" {
  description = "Git-SHA tag deployed on first boot; empty = boot idle and wait for scripts/deploy.sh. (Tags are immutable, so there is no moving 'latest'.)"
  type        = string
  default     = ""
}

variable "domain_name" {
  description = "Public hostname for TLS (e.g. dev.example.com). Empty = HTTP only on the Elastic IP (demo/smoke only)."
  type        = string
  default     = ""
}

variable "acme_email" {
  description = "Email for Let's Encrypt registration (required when domain_name is set)."
  type        = string
  default     = ""
}

variable "log_retention_days" {
  description = "Retention of the host's container log group."
  type        = number
  default     = 7
}

variable "api_command" {
  description = "Container command for the API. Matches production-fastapi's entrypoint; override if it changes."
  type        = string
  default     = "uvicorn slotwise.main:app --host 0.0.0.0 --port 8000 --proxy-headers"
}

variable "worker_command" {
  description = "Container command for the background worker. VERIFY against production-fastapi once its worker module lands."
  type        = string
  default     = "celery -A slotwise.worker.celery_app worker --loglevel=INFO --concurrency=2"
}

variable "migrate_command" {
  description = "One-off migration command run before switching traffic."
  type        = string
  default     = "alembic upgrade head"
}
