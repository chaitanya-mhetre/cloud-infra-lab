variable "name" {
  description = "Name prefix, e.g. cil-dev."
  type        = string
}

variable "ssm_path_prefix" {
  description = "SSM path the app may read, e.g. /slotwise/dev."
  type        = string
}

variable "ecr_repository_arns" {
  description = "ECR repositories the runtime may pull from (and CI may push to)."
  type        = list(string)
  default     = []
}

variable "uploads_bucket_arn" {
  description = "S3 bucket the app writes uploads to (null = no S3 permissions)."
  type        = string
  default     = null
}

variable "log_group_arns" {
  description = "CloudWatch log groups the runtime may write to."
  type        = list(string)
  default     = []
}

# --- which roles to create ---------------------------------------------------
variable "create_ec2_role" {
  description = "Create the instance profile for the low-cost EC2 host."
  type        = bool
  default     = false
}
