mock_provider "aws" {
  mock_data "aws_region" {
    defaults = { name = "ap-south-1" }
  }
}

run "only_topic_when_nothing_to_watch" {
  command = plan

  variables {
    name = "t"
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.http_5xx_rate) == 0 && length(aws_cloudwatch_metric_alarm.host_cpu) == 0
    error_message = "no alarms without inputs"
  }

  assert {
    condition     = length(aws_sns_topic_subscription.email) == 0
    error_message = "no subscription without an email"
  }
}

run "standard_stack_alarms" {
  command = plan

  variables {
    name                    = "t"
    alarm_email             = "ops@example.com"
    alb_arn_suffix          = "app/t/123"
    target_group_arn_suffix = "targetgroup/t/456"
    ecs_cluster             = "t"
    rds_instance_id         = "t"
    redis_group_id          = "t"
    app_log_group_name      = "/slotwise/t"
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.http_5xx_rate) == 1 && length(aws_cloudwatch_metric_alarm.p95_latency) == 1
    error_message = "symptom alarms expected"
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.ecs_memory) == 2
    error_message = "memory alarms for api and worker"
  }

  assert {
    condition     = length(jsondecode(aws_cloudwatch_dashboard.this.dashboard_body).widgets) == 5
    error_message = "dashboard should have ALB(2) + ECS + RDS + Redis widgets"
  }
}

run "lowcost_host_alarms" {
  command = plan

  variables {
    name            = "t"
    ec2_instance_id = "i-123"
  }

  assert {
    condition     = contains(aws_cloudwatch_metric_alarm.host_status[0].alarm_actions, "arn:aws:automate:ap-south-1:ec2:recover")
    error_message = "status-check alarm must trigger EC2 auto-recovery"
  }
}
