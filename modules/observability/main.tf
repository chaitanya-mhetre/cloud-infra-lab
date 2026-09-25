# Alarms as code. Symptom-first: alert on what users feel (5xx rate, latency),
# then on saturation that predicts it (CPU, memory, storage, Redis memory).
data "aws_region" "current" {}

resource "aws_sns_topic" "alarms" {
  name              = "${var.name}-alarms"
  kms_master_key_id = "alias/aws/sns"
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.alarm_email == "" ? 0 : 1
  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

locals {
  alb   = var.alb_arn_suffix != null
  ecs   = var.ecs_cluster != null
  rds   = var.rds_instance_id != null
  redis = var.redis_group_id != null
  logs  = var.app_log_group_name != null
  ec2   = var.ec2_instance_id != null
  t     = var.thresholds
  topic = [aws_sns_topic.alarms.arn]
}

# ---------------------------------------------------------------------------
# User-facing symptoms (ALB)
# ---------------------------------------------------------------------------
# 5xx RATE, not count: 10 errors in 100 requests is an outage, 10 in 1M is noise.
resource "aws_cloudwatch_metric_alarm" "http_5xx_rate" {
  count               = local.alb ? 1 : 0
  alarm_name          = "${var.name}-http-5xx-rate"
  alarm_description   = "Target 5xx responses above ${local.t.http_5xx_rate_pct}% of requests for 5 minutes. Runbook: docs/runbook.md#5xx"
  comparison_operator = "GreaterThanThreshold"
  threshold           = local.t.http_5xx_rate_pct
  evaluation_periods  = 5
  datapoints_to_alarm = 3
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.topic
  ok_actions          = local.topic

  metric_query {
    id          = "rate"
    expression  = "IF(requests > 20, 100 * errors / requests, 0)" # ignore tiny-traffic noise
    label       = "5xx %"
    return_data = true
  }
  metric_query {
    id = "errors"
    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "HTTPCode_Target_5XX_Count"
      dimensions  = { LoadBalancer = var.alb_arn_suffix }
      stat        = "Sum"
      period      = 60
    }
  }
  metric_query {
    id = "requests"
    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "RequestCount"
      dimensions  = { LoadBalancer = var.alb_arn_suffix }
      stat        = "Sum"
      period      = 60
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "p95_latency" {
  count               = local.alb ? 1 : 0
  alarm_name          = "${var.name}-p95-latency"
  alarm_description   = "p95 target response time above ${local.t.p95_latency_seconds}s. Runbook: docs/runbook.md#latency"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "TargetResponseTime"
  dimensions          = { LoadBalancer = var.alb_arn_suffix }
  extended_statistic  = "p95"
  period              = 60
  evaluation_periods  = 5
  datapoints_to_alarm = 3
  threshold           = local.t.p95_latency_seconds
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.topic
  ok_actions          = local.topic
}

resource "aws_cloudwatch_metric_alarm" "unhealthy_targets" {
  count               = local.alb && var.target_group_arn_suffix != null ? 1 : 0
  alarm_name          = "${var.name}-unhealthy-targets"
  alarm_description   = "At least one API task failing /readyz for 3 minutes."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "UnHealthyHostCount"
  dimensions          = { LoadBalancer = var.alb_arn_suffix, TargetGroup = var.target_group_arn_suffix }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 3
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.topic
  ok_actions          = local.topic
}

# ---------------------------------------------------------------------------
# Saturation
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "ecs_api_cpu" {
  count               = local.ecs ? 1 : 0
  alarm_name          = "${var.name}-api-cpu"
  alarm_description   = "API CPU above ${local.t.ecs_cpu_pct}% for 10 min — autoscaling at max or not keeping up."
  namespace           = "AWS/ECS"
  metric_name         = "CPUUtilization"
  dimensions          = { ClusterName = var.ecs_cluster, ServiceName = "api" }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = local.t.ecs_cpu_pct
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = local.topic
}

resource "aws_cloudwatch_metric_alarm" "ecs_memory" {
  for_each            = local.ecs ? toset(["api", "worker"]) : toset([])
  alarm_name          = "${var.name}-${each.key}-memory"
  alarm_description   = "${each.key} memory above ${local.t.ecs_memory_pct}% — OOM kills are next."
  namespace           = "AWS/ECS"
  metric_name         = "MemoryUtilization"
  dimensions          = { ClusterName = var.ecs_cluster, ServiceName = each.key }
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 2
  threshold           = local.t.ecs_memory_pct
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = local.topic
}

resource "aws_cloudwatch_metric_alarm" "rds_cpu" {
  count               = local.rds ? 1 : 0
  alarm_name          = "${var.name}-rds-cpu"
  alarm_description   = "RDS CPU above ${local.t.rds_cpu_pct}% for 15 min. Check pg_stat_statements for the top query."
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  dimensions          = { DBInstanceIdentifier = var.rds_instance_id }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 3
  threshold           = local.t.rds_cpu_pct
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = local.topic
}

resource "aws_cloudwatch_metric_alarm" "rds_storage" {
  count               = local.rds ? 1 : 0
  alarm_name          = "${var.name}-rds-free-storage"
  alarm_description   = "RDS free storage below threshold (storage autoscaling has a ceiling)."
  namespace           = "AWS/RDS"
  metric_name         = "FreeStorageSpace"
  dimensions          = { DBInstanceIdentifier = var.rds_instance_id }
  statistic           = "Minimum"
  period              = 300
  evaluation_periods  = 1
  threshold           = local.t.rds_free_storage_bytes
  comparison_operator = "LessThanThreshold"
  alarm_actions       = local.topic
}

resource "aws_cloudwatch_metric_alarm" "redis_memory" {
  count               = local.redis ? 1 : 0
  alarm_name          = "${var.name}-redis-memory"
  alarm_description   = "Redis memory above ${local.t.redis_memory_pct}%. With noeviction, a full Redis rejects new jobs."
  namespace           = "AWS/ElastiCache"
  metric_name         = "DatabaseMemoryUsagePercentage"
  dimensions          = { ReplicationGroupId = var.redis_group_id }
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 2
  threshold           = local.t.redis_memory_pct
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = local.topic
}

# ---------------------------------------------------------------------------
# Application errors from structured logs
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_metric_filter" "app_errors" {
  count          = local.logs ? 1 : 0
  name           = "${var.name}-app-errors"
  log_group_name = var.app_log_group_name
  pattern        = "{ $.level = \"error\" }"

  metric_transformation {
    name          = "AppErrors"
    namespace     = "Slotwise/${var.name}"
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_metric_alarm" "app_errors" {
  count               = local.logs ? 1 : 0
  alarm_name          = "${var.name}-app-errors"
  alarm_description   = "More than ${local.t.app_errors_per_5min} error-level log lines in 5 minutes."
  namespace           = "Slotwise/${var.name}"
  metric_name         = "AppErrors"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = local.t.app_errors_per_5min
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.topic

  depends_on = [aws_cloudwatch_log_metric_filter.app_errors]
}

# ---------------------------------------------------------------------------
# Low-cost host: auto-recover on hardware failure + alert
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "host_status" {
  count               = local.ec2 ? 1 : 0
  alarm_name          = "${var.name}-host-status"
  alarm_description   = "EC2 system status check failed — AWS moves the instance to healthy hardware."
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed_System"
  dimensions          = { InstanceId = var.ec2_instance_id }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = concat(local.topic, ["arn:aws:automate:${data.aws_region.current.name}:ec2:recover"])
}

resource "aws_cloudwatch_metric_alarm" "host_cpu" {
  count               = local.ec2 ? 1 : 0
  alarm_name          = "${var.name}-host-cpu"
  alarm_description   = "Host CPU above 90% for 15 min (burstable credits may be exhausted)."
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  dimensions          = { InstanceId = var.ec2_instance_id }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 3
  threshold           = 90
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = local.topic
}

# ---------------------------------------------------------------------------
# Dashboard (only widgets whose inputs exist)
# ---------------------------------------------------------------------------
locals {
  region = data.aws_region.current.name
  # Each widget is tagged with whether its inputs exist; the for-expression keeps only enabled ones.
  # (A `cond ? [..] : []` per group fails: both branches of a conditional must have the same type.)
  widget_specs = [
    { on = local.alb, widget = { type = "metric", width = 12, height = 6, properties = { title = "Requests / 5xx", region = local.region, stat = "Sum", period = 60, metrics = [
      ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", var.alb_arn_suffix],
      [".", "HTTPCode_Target_5XX_Count", ".", "."],
    ] } } },
    { on = local.alb, widget = { type = "metric", width = 12, height = 6, properties = { title = "Latency p50 / p95 / p99", region = local.region, period = 60, metrics = [
      ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", var.alb_arn_suffix, { stat = "p50" }],
      ["...", { stat = "p95" }],
      ["...", { stat = "p99" }],
    ] } } },
    { on = local.ecs, widget = { type = "metric", width = 12, height = 6, properties = { title = "ECS CPU / memory", region = local.region, stat = "Average", period = 300, metrics = [
      ["AWS/ECS", "CPUUtilization", "ClusterName", var.ecs_cluster, "ServiceName", "api"],
      [".", "MemoryUtilization", ".", ".", ".", "."],
      [".", "CPUUtilization", ".", ".", ".", "worker"],
    ] } } },
    { on = local.rds, widget = { type = "metric", width = 12, height = 6, properties = { title = "RDS", region = local.region, stat = "Average", period = 300, metrics = [
      ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", var.rds_instance_id],
      [".", "DatabaseConnections", ".", "."],
    ] } } },
    { on = local.redis, widget = { type = "metric", width = 12, height = 6, properties = { title = "Redis memory %", region = local.region, stat = "Maximum", period = 300, metrics = [
      ["AWS/ElastiCache", "DatabaseMemoryUsagePercentage", "ReplicationGroupId", var.redis_group_id],
    ] } } },
    { on = local.ec2, widget = { type = "metric", width = 12, height = 6, properties = { title = "Host CPU / credits", region = local.region, stat = "Average", period = 300, metrics = [
      ["AWS/EC2", "CPUUtilization", "InstanceId", var.ec2_instance_id],
      [".", "CPUCreditBalance", ".", "."],
    ] } } },
  ]
  widgets = [for w in local.widget_specs : w.widget if w.on]
}

resource "aws_cloudwatch_dashboard" "this" {
  dashboard_name = var.name
  dashboard_body = jsonencode({ widgets = local.widgets })
}
