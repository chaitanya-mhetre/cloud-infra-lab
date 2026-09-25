data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name
  partition  = data.aws_partition.current.partition

  ssm_param_arn = "arn:${local.partition}:ssm:${local.region}:${local.account_id}:parameter${var.ssm_path_prefix}/*"
}

# Reading secrets: exact path only. kms:Decrypt is limited to the aws/ssm key via the
# ViaService condition, so this role can't decrypt anything else with it.
data "aws_iam_policy_document" "read_app_config" {
  statement {
    sid       = "ReadAppParameters"
    actions   = ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath"]
    resources = [local.ssm_param_arn]
  }

  statement {
    sid       = "DecryptViaSsmOnly"
    actions   = ["kms:Decrypt"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["ssm.${local.region}.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "pull_images" {
  count = length(var.ecr_repository_arns) > 0 ? 1 : 0

  statement {
    sid = "EcrAuth"
    # GetAuthorizationToken does not support resource-level permissions.
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid       = "EcrPull"
    actions   = ["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer", "ecr:BatchCheckLayerAvailability"]
    resources = var.ecr_repository_arns
  }
}

data "aws_iam_policy_document" "write_logs" {
  count = length(var.log_group_arns) > 0 ? 1 : 0

  statement {
    sid       = "WriteLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = [for arn in var.log_group_arns : "${arn}:*"]
  }
}

data "aws_iam_policy_document" "uploads" {
  count = var.uploads_bucket_arn == null ? 0 : 1

  statement {
    sid       = "UploadsObjects"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${var.uploads_bucket_arn}/uploads/*"] # prefix-scoped, not the whole bucket
  }
}
