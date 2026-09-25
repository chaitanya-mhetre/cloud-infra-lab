variable "name" {
  description = "Name prefix."
  type        = string
}

variable "repositories" {
  description = "ECR repository names to create (one per deployable image)."
  type        = list(string)
}

variable "keep_last_images" {
  description = "Untagged/old images beyond this count are expired to cap storage cost."
  type        = number
  default     = 15
}

variable "force_delete" {
  description = "Allow terraform destroy to delete repos that still contain images (true for disposable envs)."
  type        = bool
  default     = false
}
