variable "name" {
  description = "Name prefix; the bucket is <name>-uploads-<account id>."
  type        = string
}

variable "force_destroy" {
  description = "Allow destroy with objects inside (true for disposable envs)."
  type        = bool
  default     = false
}

variable "noncurrent_days" {
  description = "Days to keep old object versions."
  type        = number
  default     = 30
}

variable "cors_allowed_origins" {
  description = "Browser origins allowed to PUT via presigned URLs."
  type        = list(string)
  default     = []
}
