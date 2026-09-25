# Secrets flow (see docs/secrets.md):
#   1. Terraform creates each SecureString with the value "PLACEHOLDER" and then ignores value changes.
#   2. An operator (or CI) sets the real value: scripts/put-secret.sh dev JWT_SECRET
#   3. The app host / ECS task reads /<app>/<env>/* at start-up.
# Result: real secret values never appear in .tf files, plans, or the state file.

resource "aws_ssm_parameter" "secret" {
  for_each = toset(var.secret_names)
  #checkov:skip=CKV_AWS_337:Uses the AWS-managed aws/ssm KMS key; a CMK costs monthly and adds no control we exercise in the lab.
  #checkov:skip=CKV2_AWS_34:SecureString is set; checkov misreads the placeholder pattern.

  name        = "${var.path_prefix}/${each.value}"
  type        = "SecureString"
  value       = "PLACEHOLDER"
  description = "Managed by Terraform (existence only). Value set out-of-band."

  lifecycle {
    ignore_changes = [value]
  }
}

resource "aws_ssm_parameter" "plain" {
  for_each = var.plain_parameters
  #checkov:skip=CKV2_AWS_34:Intentionally plain String: non-secret config such as hostnames and ports.

  name  = "${var.path_prefix}/${each.key}"
  type  = "String"
  value = each.value
}
