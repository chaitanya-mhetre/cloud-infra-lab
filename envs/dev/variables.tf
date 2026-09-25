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

variable "public_ingress_cidrs" {
  description = "Who may reach the dev host on 80/443. Narrow this to your own IP when demoing."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "instance_type" {
  description = "Host size. t4g.small is the default; t4g.micro works for smoke tests only."
  type        = string
  default     = "t4g.small"
}

variable "initial_image_tag" {
  description = "Git SHA deployed on first boot (empty = wait for the first deploy)."
  type        = string
  default     = ""
}

variable "domain_name" {
  description = "Optional hostname for TLS (leave empty for HTTP on the Elastic IP)."
  type        = string
  default     = ""
}

variable "acme_email" {
  description = "Let's Encrypt contact email (needed with domain_name)."
  type        = string
  default     = ""
}

variable "github_owner" {
  description = "GitHub user/org that owns the infra and app repos (OIDC trust)."
  type        = string
  default     = "CHANGE-ME"
}

variable "alarm_email" {
  description = "Alarm notification email (empty = no subscription)."
  type        = string
  default     = ""
}
