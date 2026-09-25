variable "name" {
  description = "Name prefix, e.g. cil-staging."
  type        = string
}

variable "vpc_id" {
  description = "VPC to create security groups in."
  type        = string
}

variable "app_port" {
  description = "Port the API container listens on."
  type        = number
  default     = 8000
}

variable "public_ingress_cidrs" {
  description = "CIDRs allowed to reach the public entry point (ALB or low-cost EC2) on 80/443."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "mode" {
  description = "standard = ALB + private app tier; lowcost = single public EC2 host."
  type        = string
  default     = "standard"

  validation {
    condition     = contains(["standard", "lowcost"], var.mode)
    error_message = "mode must be standard or lowcost."
  }
}

variable "egress_mode" {
  description = "open = app tier may reach any host on 443; restricted = only VPC endpoints, S3 and egress_allowed_cidrs (standard mode only)."
  type        = string
  default     = "open"

  validation {
    condition     = contains(["open", "restricted"], var.egress_mode)
    error_message = "egress_mode must be open or restricted."
  }

  validation {
    condition     = var.egress_mode == "open" || (var.mode == "standard" && var.vpc_cidr != "" && var.s3_prefix_list_id != "")
    error_message = "restricted egress needs standard mode, vpc_cidr and s3_prefix_list_id (the low-cost host needs open egress for OS packages)."
  }
}

variable "vpc_cidr" {
  description = "VPC CIDR (interface endpoints live inside it). Required for restricted egress."
  type        = string
  default     = ""
}

variable "s3_prefix_list_id" {
  description = "Prefix list of the S3 gateway endpoint. Required for restricted egress."
  type        = string
  default     = ""
}

variable "egress_allowed_cidrs" {
  description = "Extra HTTPS destinations for restricted egress (e.g. a partner API with fixed IPs). Keep it short; every entry is reviewed."
  type        = list(string)
  default     = []

  validation {
    condition     = !contains(var.egress_allowed_cidrs, "0.0.0.0/0")
    error_message = "0.0.0.0/0 in the allow-list defeats restricted egress; use egress_mode = \"open\" instead."
  }
}
