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
