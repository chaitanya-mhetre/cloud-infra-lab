variable "region" {
  description = "AWS region."
  type        = string
  default     = "ap-south-1"
}

variable "project" {
  description = "Project short name."
  type        = string
  default     = "cil"
}

variable "owner" {
  description = "Owner tag."
  type        = string
  default     = "chaitanya"
}

variable "github_owner" {
  description = "GitHub user/org that owns the infra and app repos (OIDC trust)."
  type        = string
  default     = "CHANGE-ME"
}

variable "monthly_budget_usd" {
  description = "Monthly spend ceiling for alerts (USD)."
  type        = number
  default     = 20
}

variable "budget_email" {
  description = "Where budget alerts go (empty = no budget created)."
  type        = string
  default     = ""
}
