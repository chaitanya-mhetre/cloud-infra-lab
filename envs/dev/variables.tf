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
