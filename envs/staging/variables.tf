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
  description = "GitHub owner for OIDC trust."
  type        = string
  default     = "CHANGE-ME"
}

variable "image_tag" {
  description = "Git SHA already pushed to ECR, used for the first task definitions."
  type        = string
}

variable "domain_name" {
  description = "Public hostname (empty = HTTP on ALB DNS; demo only)."
  type        = string
  default     = ""
}

variable "route53_zone_id" {
  description = "Hosted zone for domain_name."
  type        = string
  default     = ""
}

variable "alarm_email" {
  description = "Alarm notification email."
  type        = string
  default     = ""
}
