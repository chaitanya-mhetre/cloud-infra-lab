variable "name" {
  description = "Name prefix."
  type        = string
}

variable "subnet_ids" {
  description = "Isolated data subnets."
  type        = list(string)
}

variable "security_group_ids" {
  description = "Cache security group(s)."
  type        = list(string)
}

variable "node_type" {
  description = "cache.t4g.micro for staging."
  type        = string
  default     = "cache.t4g.micro"
}

variable "replicas" {
  description = "Read replicas (0 = single node; >=1 enables automatic failover)."
  type        = number
  default     = 0
}

variable "engine_version" {
  description = "Redis OSS version."
  type        = string
  default     = "7.1"
}
