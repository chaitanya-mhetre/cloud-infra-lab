variable "name" {
  description = "Name prefix (ALB names max 32 chars)."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID."
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnets in >= 2 AZs."
  type        = list(string)
}

variable "security_group_ids" {
  description = "ALB security group(s)."
  type        = list(string)
}

variable "app_port" {
  description = "Container port targets listen on."
  type        = number
  default     = 8000
}

variable "health_check_path" {
  description = "Readiness endpoint. /readyz checks DB + Redis, so a task that lost its DB leaves rotation."
  type        = string
  default     = "/readyz"
}

variable "domain_name" {
  description = "Hostname for the ACM certificate (e.g. staging.example.com). Empty = HTTP-only listener (demo only)."
  type        = string
  default     = ""
}

variable "route53_zone_id" {
  description = "Hosted zone for DNS validation + alias record. Required with domain_name."
  type        = string
  default     = ""
}

variable "deletion_protection" {
  description = "Protect the ALB from deletion (prod-like)."
  type        = bool
  default     = false
}

variable "idle_timeout" {
  description = "Seconds; must exceed the longest SSE/streaming response."
  type        = number
  default     = 120
}
