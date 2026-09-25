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

# Cost guard for the whole account: email at 50% and 80% of actual spend, and when the
# month is FORECAST to exceed the budget (earliest warning).
resource "aws_budgets_budget" "monthly" {
  count        = var.budget_email == "" ? 0 : 1
  name         = "${var.project}-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  dynamic "notification" {
    for_each = [50, 80]
    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = notification.value
      threshold_type             = "PERCENTAGE"
      notification_type          = "ACTUAL"
      subscriber_email_addresses = [var.budget_email]
    }
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.budget_email]
  }
}
