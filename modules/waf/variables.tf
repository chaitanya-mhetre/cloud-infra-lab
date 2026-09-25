variable "name" {
  description = "Name prefix, e.g. cil-prod-like."
  type        = string
}

variable "alb_arn" {
  description = "ARN of the ALB to protect."
  type        = string
}

variable "mode" {
  description = "block = enforce; count = log only (use while tuning false positives)."
  type        = string
  default     = "count"

  validation {
    condition     = contains(["block", "count"], var.mode)
    error_message = "mode must be block or count."
  }
}

variable "rate_limit_per_5min" {
  description = "Max requests per client IP in a 5-minute window before WAF returns 429. The app has its own per-user limits; this is the flood backstop."
  type        = number
  default     = 2000

  validation {
    # AWS minimum for rate-based rules is 10 (it was 100 before 2023).
    condition     = var.rate_limit_per_5min >= 10 && var.rate_limit_per_5min <= 2000000000
    error_message = "rate_limit_per_5min must be between 10 and 2,000,000,000."
  }
}

variable "managed_rule_groups" {
  description = "AWS managed rule groups, evaluated in list order after the rate rule and the always-on KnownBadInputs group. count_rules = rules inside a group downgraded to count (false positives)."
  type = list(object({
    name        = string
    count_rules = optional(list(string), [])
  }))
  default = [
    { name = "AWSManagedRulesAmazonIpReputationList" },
    # SizeRestrictions_BODY blocks bodies > 8 KB; file uploads go straight to S3 via presigned URLs,
    # but webhook payloads and JSON bookings can exceed it, so it only counts.
    { name = "AWSManagedRulesCommonRuleSet", count_rules = ["SizeRestrictions_BODY"] },
    { name = "AWSManagedRulesSQLiRuleSet" },
  ]

  validation {
    condition     = !contains([for g in var.managed_rule_groups : g.name], "AWSManagedRulesKnownBadInputsRuleSet")
    error_message = "AWSManagedRulesKnownBadInputsRuleSet is always on (fixed rule); don't list it here."
  }
}

variable "log_retention_days" {
  description = "Retention for WAF logs (only blocked/counted requests are logged)."
  type        = number
  default     = 30
}

variable "log_kms_key_arn" {
  description = "Optional CMK for the WAF log group. Empty = AWS-managed encryption."
  type        = string
  default     = ""
}
