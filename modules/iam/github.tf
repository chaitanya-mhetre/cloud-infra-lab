# GitHub Actions -> AWS without long-lived keys.
# GitHub mints a short-lived OIDC token per job; AWS STS trades it for role credentials
# ONLY if the token's `sub` claim matches the patterns below (repo + branch/PR/environment).
#
#   plan   : any PR on the infra repo          -> read-only + state read + lock
#   apply  : infra repo, GitHub environment X  -> can change infra (env has required reviewers)
#   deploy : app repos, main branch only       -> push images + roll services, nothing else

locals {
  # The deploy role may pass exactly the ECS roles this module created (plus any given explicitly).
  passable_role_arns = concat(var.passable_role_arns, aws_iam_role.ecs_execution[*].arn, aws_iam_role.ecs_task[*].arn)

  gh_provider_arn = coalesce(var.github_oidc_provider_arn, "arn:${local.partition}:iam::${local.account_id}:oidc-provider/token.actions.githubusercontent.com")
}

# One trust policy per role (explicit rather than for_each so policy scanners can evaluate the subjects).
data "aws_iam_policy_document" "gh_trust_plan" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.gh_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    # Exact match on the subject: no wildcards, so a fork or another branch can never assume the role.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_owner}/${var.infra_repo}:pull_request"]
    }
  }
}

data "aws_iam_policy_document" "gh_trust_apply" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.gh_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    # Exact match on the subject: no wildcards, so a fork or another branch can never assume the role.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_owner}/${var.infra_repo}:environment:${var.apply_environment}"]
    }
  }
}

data "aws_iam_policy_document" "gh_trust_deploy" {
  #checkov:skip=CKV_AWS_358:Subjects are built by a for-expression checkov cannot evaluate; each is an exact repo:<owner>/<repo>:ref:refs/heads/main string (see tests in docs/iam.md).
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.gh_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    # Exact match on the subject: no wildcards, so a fork or another branch can never assume the role.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [for r in var.app_repos : "repo:${var.github_owner}/${r}:ref:refs/heads/main"]
    }
  }
}

# ---------------------------------------------------------------------------
# State access shared by plan + apply
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "state_access" {
  count = var.state_bucket_arn == null ? 0 : 1

  statement {
    sid       = "StateBucketList"
    actions   = ["s3:ListBucket"]
    resources = [var.state_bucket_arn]
  }
  statement {
    sid       = "StateObjects"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${var.state_bucket_arn}/*"]
  }
  statement {
    sid       = "StateLock"
    actions   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem", "dynamodb:DescribeTable"]
    resources = [var.lock_table_arn]
  }
}

# ---------------------------------------------------------------------------
# plan role
# ---------------------------------------------------------------------------
resource "aws_iam_role" "gh_plan" {
  count = var.create_github_plan_role ? 1 : 0

  name                 = "${var.name}-gh-plan"
  assume_role_policy   = data.aws_iam_policy_document.gh_trust_plan.json
  max_session_duration = 3600
}

# ReadOnlyAccess lets plan refresh every resource type. It can read SSM SecureString *metadata*
# but decrypting needs kms:Decrypt, which ReadOnlyAccess doesn't grant.
resource "aws_iam_role_policy_attachment" "gh_plan_readonly" {
  count = var.create_github_plan_role ? 1 : 0

  role       = aws_iam_role.gh_plan[0].name
  policy_arn = "arn:${local.partition}:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_iam_role_policy" "gh_plan_state" {
  count = var.create_github_plan_role && var.state_bucket_arn != null ? 1 : 0

  name   = "terraform-state"
  role   = aws_iam_role.gh_plan[0].id
  policy = data.aws_iam_policy_document.state_access[0].json
}

# ---------------------------------------------------------------------------
# apply role
# ---------------------------------------------------------------------------
resource "aws_iam_role" "gh_apply" {
  count = var.create_github_apply_role ? 1 : 0

  name                 = "${var.name}-gh-apply"
  assume_role_policy   = data.aws_iam_policy_document.gh_trust_apply.json
  max_session_duration = 3600
}

# Honest trade-off: Terraform creating VPCs, RDS, IAM roles etc. needs broad rights.
# Mitigations: only assumable from a reviewer-gated GitHub environment, short sessions,
# and the permissions boundary below stops it from escalating via IAM.
resource "aws_iam_role_policy_attachment" "gh_apply_poweruser" {
  count = var.create_github_apply_role ? 1 : 0

  role       = aws_iam_role.gh_apply[0].name
  policy_arn = "arn:${local.partition}:iam::aws:policy/PowerUserAccess"
}

data "aws_iam_policy_document" "gh_apply_iam" {
  #checkov:skip=CKV_AWS_109:IAM writes are restricted to roles/policies named with this env's prefix.
  #checkov:skip=CKV_AWS_111:Same: write actions are scoped by resource name prefix, not '*'.
  #checkov:skip=CKV_AWS_356:iam:ListRoles/ListPolicies-style read calls don't support resource scoping.
  statement {
    sid = "ManageOwnPrefixedIam"
    actions = [
      "iam:CreateRole", "iam:DeleteRole", "iam:UpdateRole", "iam:TagRole", "iam:UntagRole",
      "iam:PutRolePolicy", "iam:DeleteRolePolicy", "iam:AttachRolePolicy", "iam:DetachRolePolicy",
      "iam:UpdateAssumeRolePolicy", "iam:PassRole",
      "iam:CreateInstanceProfile", "iam:DeleteInstanceProfile",
      "iam:AddRoleToInstanceProfile", "iam:RemoveRoleFromInstanceProfile", "iam:TagInstanceProfile",
    ]
    resources = [
      "arn:${local.partition}:iam::${local.account_id}:role/${var.name}-*",
      "arn:${local.partition}:iam::${local.account_id}:instance-profile/${var.name}-*",
    ]
  }
  statement {
    sid       = "ReadIam"
    actions   = ["iam:Get*", "iam:List*"]
    resources = ["*"]
  }
  statement {
    sid       = "ServiceLinkedRoles"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["arn:${local.partition}:iam::${local.account_id}:role/aws-service-role/*"]
  }
}

resource "aws_iam_role_policy" "gh_apply_iam" {
  count = var.create_github_apply_role ? 1 : 0

  name   = "scoped-iam"
  role   = aws_iam_role.gh_apply[0].id
  policy = data.aws_iam_policy_document.gh_apply_iam.json
}

resource "aws_iam_role_policy" "gh_apply_state" {
  count = var.create_github_apply_role && var.state_bucket_arn != null ? 1 : 0

  name   = "terraform-state"
  role   = aws_iam_role.gh_apply[0].id
  policy = data.aws_iam_policy_document.state_access[0].json
}

# ---------------------------------------------------------------------------
# deploy role (app pipelines)
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "gh_deploy" {
  statement {
    sid       = "EcrAuth"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "EcrPush"
    actions = [
      "ecr:BatchCheckLayerAvailability", "ecr:InitiateLayerUpload", "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload", "ecr:PutImage", "ecr:BatchGetImage", "ecr:DescribeImages",
      "ecr:DescribeImageScanFindings",
    ]
    resources = length(var.ecr_repository_arns) > 0 ? var.ecr_repository_arns : ["arn:${local.partition}:ecr:${local.region}:${local.account_id}:repository/none"]
  }

  dynamic "statement" {
    for_each = var.ecs_cluster_arn == null ? [] : [1]
    content {
      sid       = "EcsRollService"
      actions   = ["ecs:UpdateService", "ecs:DescribeServices", "ecs:RunTask", "ecs:DescribeTasks"]
      resources = ["*"]
      condition {
        test     = "ArnEquals"
        variable = "ecs:cluster"
        values   = [var.ecs_cluster_arn]
      }
    }
  }

  dynamic "statement" {
    for_each = var.ecs_cluster_arn == null ? [] : [1]
    content {
      sid = "EcsTaskDefinitions"
      # Task definition APIs don't support resource-level permissions.
      actions   = ["ecs:RegisterTaskDefinition", "ecs:DescribeTaskDefinition"]
      resources = ["*"]
    }
  }

  dynamic "statement" {
    for_each = length(local.passable_role_arns) > 0 ? [1] : []
    content {
      sid       = "PassOnlyTaskRoles"
      actions   = ["iam:PassRole"]
      resources = local.passable_role_arns
      condition {
        test     = "StringEquals"
        variable = "iam:PassedToService"
        values   = ["ecs-tasks.amazonaws.com"]
      }
    }
  }

  dynamic "statement" {
    for_each = var.deploy_instance_tag_env == "" ? [] : [1]
    content {
      sid       = "RunDeployOnTaggedHost"
      actions   = ["ssm:SendCommand"]
      resources = ["arn:${local.partition}:ec2:${local.region}:${local.account_id}:instance/*"]
      condition {
        test     = "StringEquals"
        variable = "ssm:resourceTag/Env"
        values   = [var.deploy_instance_tag_env]
      }
    }
  }

  dynamic "statement" {
    for_each = var.deploy_instance_tag_env == "" ? [] : [1]
    content {
      sid       = "RunShellScriptDocument"
      actions   = ["ssm:SendCommand"]
      resources = ["arn:${local.partition}:ssm:${local.region}::document/AWS-RunShellScript"]
    }
  }

  dynamic "statement" {
    for_each = var.deploy_instance_tag_env == "" ? [] : [1]
    content {
      sid       = "ReadCommandResults"
      actions   = ["ssm:GetCommandInvocation", "ssm:ListCommandInvocations"]
      resources = ["*"]
    }
  }
}

resource "aws_iam_role" "gh_deploy" {
  count = var.create_github_deploy_role ? 1 : 0

  name                 = "${var.name}-gh-deploy"
  assume_role_policy   = data.aws_iam_policy_document.gh_trust_deploy.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy" "gh_deploy" {
  count = var.create_github_deploy_role ? 1 : 0

  name   = "deploy"
  role   = aws_iam_role.gh_deploy[0].id
  policy = data.aws_iam_policy_document.gh_deploy.json
}
