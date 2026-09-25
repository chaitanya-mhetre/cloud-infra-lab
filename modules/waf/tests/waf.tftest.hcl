# Offline tests for the WAF web ACL (mocked provider, nothing reaches AWS).
mock_provider "aws" {
  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:eu-west-1:123456789012:log-group:aws-waf-logs-t"
    }
  }
  mock_resource "aws_wafv2_web_acl" {
    defaults = {
      arn = "arn:aws:wafv2:eu-west-1:123456789012:regional/webacl/t-alb/abc"
    }
  }
}

variables {
  name    = "t"
  alb_arn = "arn:aws:elasticloadbalancing:eu-west-1:123456789012:loadbalancer/app/t/abc"
}

run "count_mode_is_the_default" {
  command = apply

  assert {
    condition     = length([for r in aws_wafv2_web_acl.this.rule : r if length(try(r.action[0].count, [])) == 1]) == 1
    error_message = "in count mode the rate rule must count, not block"
  }

  assert {
    condition     = alltrue([for r in aws_wafv2_web_acl.this.rule : length(try(r.override_action[0].count, [])) == 1 if !contains(["rate-limit-per-ip", "AWSManagedRulesKnownBadInputsRuleSet"], r.name)])
    error_message = "in count mode every configurable managed group must be overridden to count"
  }

  assert {
    condition     = alltrue([for r in aws_wafv2_web_acl.this.rule : length(r.override_action[0].none) == 1 if r.name == "AWSManagedRulesKnownBadInputsRuleSet"])
    error_message = "KnownBadInputs (Log4Shell) must block even in count mode"
  }
}

run "block_mode_enforces_everything" {
  command = apply

  variables {
    mode = "block"
  }

  assert {
    condition = anytrue([
      for r in aws_wafv2_web_acl.this.rule :
      r.name == "rate-limit-per-ip" && try(r.action[0].block[0].custom_response[0].response_code, 0) == 429
    ])
    error_message = "rate rule must block with 429 in block mode"
  }

  assert {
    condition     = alltrue([for r in aws_wafv2_web_acl.this.rule : length(try(r.override_action[0].none, [])) == 1 if r.name != "rate-limit-per-ip"])
    error_message = "in block mode managed groups keep their own actions (override none)"
  }
}

run "rule_order_and_groups" {
  command = apply

  assert {
    condition     = length(aws_wafv2_web_acl.this.rule) == 5
    error_message = "expected rate rule + 4 managed groups"
  }

  assert {
    condition = alltrue([
      for r in aws_wafv2_web_acl.this.rule : r.priority == 0 if r.name == "rate-limit-per-ip"
    ])
    error_message = "rate rule must be evaluated first"
  }

  assert {
    condition     = aws_wafv2_web_acl.this.scope == "REGIONAL"
    error_message = "ALB web ACLs must be REGIONAL"
  }
}

run "logs_are_named_and_redacted" {
  command = apply

  assert {
    condition     = startswith(aws_cloudwatch_log_group.waf.name, "aws-waf-logs-")
    error_message = "WAF only delivers to log groups named aws-waf-logs-*"
  }

  assert {
    condition     = length(aws_wafv2_web_acl_logging_configuration.this.redacted_fields) == 2
    error_message = "authorization and cookie headers must be redacted"
  }

  assert {
    condition     = aws_wafv2_web_acl_association.alb.resource_arn == var.alb_arn
    error_message = "web ACL must be associated with the ALB"
  }
}

run "log4shell_group_stays_on_with_a_custom_list" {
  command = apply

  variables {
    managed_rule_groups = [{ name = "AWSManagedRulesCommonRuleSet" }]
  }

  assert {
    condition     = contains([for r in aws_wafv2_web_acl.this.rule : r.name], "AWSManagedRulesKnownBadInputsRuleSet")
    error_message = "KnownBadInputs (Log4Shell) must stay on even when the list is overridden"
  }
}

run "known_bad_inputs_cannot_be_listed_twice" {
  command = plan

  variables {
    managed_rule_groups = [{ name = "AWSManagedRulesKnownBadInputsRuleSet" }]
  }

  expect_failures = [var.managed_rule_groups]
}

run "rejects_bad_mode" {
  command = plan

  variables {
    mode = "monitor"
  }

  expect_failures = [var.mode]
}
