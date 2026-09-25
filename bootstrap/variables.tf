variable "region" {
  description = "AWS region for the state bucket and lock table."
  type        = string
  default     = "ap-south-1"
}

variable "project" {
  description = "Project name used in resource names and tags."
  type        = string
  default     = "cil"
}

variable "owner" {
  description = "Owner tag value."
  type        = string
  default     = "chaitanya"
}

variable "create_github_oidc_provider" {
  description = "Set false if the account already has the token.actions.githubusercontent.com provider."
  type        = bool
  default     = true
}
