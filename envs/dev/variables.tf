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
  description = "Image tag deployed on first boot."
  type        = string
  default     = "latest-main"
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
