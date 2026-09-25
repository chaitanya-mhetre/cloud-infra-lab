variable "path_prefix" {
  description = "SSM path prefix, e.g. /slotwise/dev. Apps read everything under it."
  type        = string

  validation {
    condition     = startswith(var.path_prefix, "/") && !endswith(var.path_prefix, "/")
    error_message = "path_prefix must start with / and not end with /."
  }
}

variable "secret_names" {
  description = "SecureString parameters to create with a PLACEHOLDER value. Real values are set out-of-band (scripts/put-secret.sh) so they never enter Terraform state."
  type        = list(string)
  default     = []
}

variable "plain_parameters" {
  description = "Non-secret config (String parameters) whose values Terraform owns, e.g. REDIS_URL built from other outputs."
  type        = map(string)
  default     = {}
}
