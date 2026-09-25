# Offline tests for the SG graph: internet -> alb -> app -> {db, cache}.
mock_provider "aws" {}

variables {
  name   = "t"
  vpc_id = "vpc-123"
}

run "standard_mode_graph" {
  command = plan

  assert {
    condition     = length(aws_security_group.alb) == 1 && length(aws_security_group.cache) == 1
    error_message = "standard mode needs ALB and cache SGs"
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.host_https) == 0
    error_message = "app tier must not be internet-reachable in standard mode"
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.app_from_alb[0].from_port == 8000
    error_message = "app should accept only the app port from the ALB"
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.db_from_app.from_port == 5432
    error_message = "db must accept Postgres from the app tier"
  }
}

run "lowcost_mode_has_no_ssh" {
  command = plan

  variables {
    mode = "lowcost"
  }

  assert {
    condition     = length(aws_security_group.alb) == 0 && length(aws_security_group.cache) == 0
    error_message = "low-cost mode has no ALB or ElastiCache"
  }

  assert {
    condition = alltrue([
      for r in values(aws_vpc_security_group_ingress_rule.host_https) : r.from_port == 443
    ])
    error_message = "host exposes only 443 (and 80); never 22"
  }
}

run "rejects_unknown_mode" {
  command = plan

  variables {
    mode = "kubernetes"
  }

  expect_failures = [var.mode]
}
