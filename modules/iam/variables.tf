variable "name" {
  description = "Name prefix, e.g. cil-dev."
  type        = string
}

variable "ssm_path_prefix" {
  description = "SSM path the app may read, e.g. /slotwise/dev."
  type        = string
}

variable "ecr_repository_arns" {
  description = "ECR repositories the runtime may pull from (and CI may push to)."
  type        = list(string)
  default     = []
}

variable "uploads_bucket_arn" {
  description = "S3 bucket the app writes uploads to (null = no S3 permissions)."
  type        = string
  default     = null
}

variable "log_group_arns" {
  description = "CloudWatch log groups the runtime may write to."
  type        = list(string)
  default     = []
}

# --- which roles to create ---------------------------------------------------
variable "create_ec2_role" {
  description = "Create the instance profile for the low-cost EC2 host."
  type        = bool
  default     = false
}

# --- GitHub Actions OIDC roles ----------------------------------------------
variable "github_oidc_provider_arn" {
  description = "ARN of token.actions.githubusercontent.com provider (from bootstrap). Required for any GitHub role."
  type        = string
  default     = null
}

variable "github_owner" {
  description = "GitHub user/org owning the repos."
  type        = string
  default     = ""
}

variable "infra_repo" {
  description = "Repo name of this infrastructure code (for plan/apply roles)."
  type        = string
  default     = "cloud-infra-lab"
}

variable "app_repos" {
  description = "App repos allowed to use the deploy role (build + push image + roll the service)."
  type        = list(string)
  default     = []
}

variable "create_github_plan_role" {
  description = "Read-only role for `terraform plan` on pull requests of the infra repo."
  type        = bool
  default     = false
}

variable "create_github_apply_role" {
  description = "Role for `terraform apply`/destroy, assumable only from the GitHub environment named apply_environment (which has required reviewers)."
  type        = bool
  default     = false
}

variable "apply_environment" {
  description = "GitHub environment name gating the apply role, e.g. infra-staging."
  type        = string
  default     = ""
}

variable "create_github_deploy_role" {
  description = "Deploy-only role for app pipelines on the main branch."
  type        = bool
  default     = false
}

variable "state_bucket_arn" {
  description = "Terraform state bucket (plan/apply roles need it)."
  type        = string
  default     = null
}

variable "lock_table_arn" {
  description = "Terraform lock table (plan/apply roles need it)."
  type        = string
  default     = null
}

variable "ecs_cluster_arn" {
  description = "ECS cluster the deploy role may update services in (standard mode)."
  type        = string
  default     = null
}

variable "passable_role_arns" {
  description = "Task/execution roles the deploy role may pass to ECS when registering task definitions."
  type        = list(string)
  default     = []
}

variable "deploy_instance_tag_env" {
  description = "Low-cost mode: deploy role may SSM Run Command only on instances tagged Env=<this>."
  type        = string
  default     = ""
}
