# Long-lived, cheap resources shared by every environment.
# Images are built ONCE per commit and promoted dev -> staging -> prod-like by tag,
# so the registry must outlive any single environment.
module "registry" {
  source = "../../modules/registry"

  name         = var.project
  repositories = ["slotwise", "rag-engine"]
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  # Names follow bootstrap/main.tf conventions.
  state_bucket_arn = "arn:${data.aws_partition.current.partition}:s3:::${data.aws_caller_identity.current.account_id}-${var.project}-tfstate"
  lock_table_arn   = "arn:${data.aws_partition.current.partition}:dynamodb:${var.region}:${data.aws_caller_identity.current.account_id}:table/${var.project}-tf-locks"
}

# Account-wide read-only role used by `terraform plan` on every infra PR.
module "github_plan" {
  source = "../../modules/iam"

  name                    = var.project
  ssm_path_prefix         = "/none"
  github_owner            = var.github_owner
  create_github_plan_role = true
  state_bucket_arn        = local.state_bucket_arn
  lock_table_arn          = local.lock_table_arn
}
