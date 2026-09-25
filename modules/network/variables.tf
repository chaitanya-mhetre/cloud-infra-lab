variable "name" {
  description = "Name prefix, e.g. cil-dev."
  type        = string
}

variable "cidr_block" {
  description = "VPC CIDR. A /16 leaves room for 256 /24 subnets."
  type        = string
  default     = "10.20.0.0/16"

  validation {
    condition     = can(cidrhost(var.cidr_block, 0))
    error_message = "cidr_block must be a valid IPv4 CIDR."
  }
}

variable "az_count" {
  description = "Number of availability zones to spread subnets over. ALB and RDS subnet groups need at least 2."
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3
    error_message = "az_count must be 2 or 3."
  }
}

variable "enable_nat_gateway" {
  description = "Create ONE NAT gateway (in the first AZ) so private subnets get outbound internet. Largest fixed cost in small setups; off in low-cost dev."
  type        = bool
  default     = false
}

variable "enable_interface_endpoints" {
  description = "Create interface VPC endpoints (ECR, SSM, Logs) so private tasks don't need NAT for AWS APIs. Each endpoint costs per hour per AZ."
  type        = bool
  default     = false
}

variable "enable_flow_logs" {
  description = "Ship VPC flow logs (REJECT only) to CloudWatch."
  type        = bool
  default     = true
}

variable "flow_logs_retention_days" {
  description = "Retention for the flow log group."
  type        = number
  default     = 7
}

variable "flow_logs_kms_key_arn" {
  description = "Optional KMS key for the flow log group. Null = CloudWatch default encryption."
  type        = string
  default     = null
}
