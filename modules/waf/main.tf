# AWS WAFv2 web ACL in front of the ALB.
#
# Rule order (lower priority number = evaluated first):
#   0  per-IP rate limit        cheap, stops floods before the managed rules are billed per request
#   10 IP reputation list       known botnets / scanners
#   20 common rule set (CRS)    OWASP-style XSS, LFI, bad user agents, oversize bodies
#   30 known bad inputs         Log4Shell, Java deserialisation, localhost Host headers
#   40 SQL injection            SQLi patterns in query, body, cookies
#
# `mode = "count"` makes every rule count instead of block. Roll out in count mode, read the logs for
# false positives, then switch to "block". The same switch covers the rate rule and the managed groups.

locals {
  block = var.mode == "block"

  managed_groups = {
    for idx, g in var.managed_rule_groups : g.name => merge(g, { priority = 10 + idx * 10 })
  }
}

resource "aws_wafv2_web_acl" "this" {
  name        = "${var.name}-alb"
  description = "Edge protection for the ${var.name} ALB"
  scope       = "REGIONAL" # REGIONAL = ALB/API Gateway; CLOUDFRONT scope only exists in us-east-1

  default_action {
    allow {}
  }

  rule {
    name     = "rate-limit-per-ip"
    priority = 0

    action {
      dynamic "block" {
        for_each = local.block ? [1] : []
        content {
          custom_response {
            response_code = 429
          }
        }
      }
      dynamic "count" {
        for_each = local.block ? [] : [1]
        content {}
      }
    }

    statement {
      rate_based_statement {
        limit                 = var.rate_limit_per_5min
        aggregate_key_type    = "IP"
        evaluation_window_sec = 300
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name}-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  dynamic "rule" {
    for_each = local.managed_groups
    content {
      name     = rule.key
      priority = rule.value.priority

      # Managed groups use override_action, not action: "none" keeps each rule's own block/count,
      # "count" forces the whole group to count (used for rollout).
      override_action {
        dynamic "none" {
          for_each = local.block ? [1] : []
          content {}
        }
        dynamic "count" {
          for_each = local.block ? [] : [1]
          content {}
        }
      }

      statement {
        managed_rule_group_statement {
          vendor_name = "AWS"
          name        = rule.key

          # Rules inside a group that are known to break this app are downgraded to count, not deleted,
          # so they still show up in the logs.
          dynamic "rule_action_override" {
            for_each = rule.value.count_rules
            content {
              name = rule_action_override.value
              action_to_use {
                count {}
              }
            }
          }
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${var.name}-${rule.key}"
        sampled_requests_enabled   = true
      }
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.name}-alb"
    sampled_requests_enabled   = true
  }

  lifecycle {
    precondition {
      condition     = contains([for g in var.managed_rule_groups : g.name], "AWSManagedRulesKnownBadInputsRuleSet")
      error_message = "Keep AWSManagedRulesKnownBadInputsRuleSet: it is the Log4Shell (CVE-2021-44228) protection."
    }
  }
}

# WAF logging destinations must be named aws-waf-logs-*.
resource "aws_cloudwatch_log_group" "waf" {
  #checkov:skip=CKV_AWS_338:Lab retention is a variable (default 30 d); 1-year retention is a compliance requirement we don't have.
  #checkov:skip=CKV_AWS_158:KMS key is optional (log_kms_key_arn); AWS-managed encryption applies otherwise. CMKs are a listed gap.
  name              = "aws-waf-logs-${var.name}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.log_kms_key_arn != "" ? var.log_kms_key_arn : null
}

resource "aws_wafv2_web_acl_logging_configuration" "this" {
  resource_arn            = aws_wafv2_web_acl.this.arn
  log_destination_configs = [aws_cloudwatch_log_group.waf.arn]

  # Never write credentials to logs.
  redacted_fields {
    single_header {
      name = "authorization"
    }
  }
  redacted_fields {
    single_header {
      name = "cookie"
    }
  }

  # Only keep requests WAF acted on (block or count). Allowed traffic is already in the app/ALB logs,
  # and logging every request is the main WAF log cost.
  logging_filter {
    default_behavior = "DROP"

    filter {
      behavior    = "KEEP"
      requirement = "MEETS_ANY"
      condition {
        action_condition {
          action = "BLOCK"
        }
      }
      condition {
        action_condition {
          action = "COUNT"
        }
      }
    }
  }
}

resource "aws_wafv2_web_acl_association" "alb" {
  resource_arn = var.alb_arn
  web_acl_arn  = aws_wafv2_web_acl.this.arn
}
