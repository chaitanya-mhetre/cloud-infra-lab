variable "name" {
  description = "Name prefix."
  type        = string
}

variable "subnet_ids" {
  description = "Isolated data subnets (>= 2 AZs)."
  type        = list(string)
}

variable "security_group_ids" {
  description = "DB security group(s) from modules/security."
  type        = list(string)
}

variable "engine_version" {
  description = "Postgres major.minor."
  type        = string
  default     = "16.4"
}

variable "instance_class" {
  description = "db.t4g.micro for staging; db.t4g.medium+ for prod-like."
  type        = string
  default     = "db.t4g.micro"
}

variable "allocated_storage_gb" {
  description = "Initial gp3 storage."
  type        = number
  default     = 20
}

variable "max_allocated_storage_gb" {
  description = "Storage autoscaling ceiling (0 disables)."
  type        = number
  default     = 50
}

variable "multi_az" {
  description = "Standby in a second AZ (roughly doubles cost). prod-like only."
  type        = bool
  default     = false
}

variable "backup_retention_days" {
  description = "Automated backup retention (1-35)."
  type        = number
  default     = 1
}

variable "deletion_protection" {
  description = "Block accidental deletes. False for disposable envs so teardown works."
  type        = bool
  default     = false
}

variable "skip_final_snapshot" {
  description = "Skip the final snapshot on destroy (disposable envs only)."
  type        = bool
  default     = true
}

variable "database_name" {
  description = "Initial database."
  type        = string
  default     = "slotwise"
}

variable "master_username" {
  description = "Admin user (used only for migrations/bootstrap; the app uses least-privilege roles created by migrations)."
  type        = string
  default     = "slotwise"
}

variable "performance_insights" {
  description = "Enable Performance Insights (free tier: 7 days)."
  type        = bool
  default     = true
}
