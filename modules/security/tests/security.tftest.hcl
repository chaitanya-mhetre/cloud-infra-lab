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

run "open_egress_is_the_default" {
  command = plan

  assert {
    condition     = length(aws_vpc_security_group_egress_rule.app_https_out) == 1 && aws_vpc_security_group_egress_rule.app_https_out[0].cidr_ipv4 == "0.0.0.0/0"
    error_message = "open mode keeps 443 to anywhere"
  }

  assert {
    condition     = length(aws_vpc_security_group_egress_rule.app_https_vpc) == 0 && length(aws_vpc_security_group_egress_rule.app_https_s3) == 0
    error_message = "open mode creates no restricted rules"
  }
}

run "restricted_egress_has_no_open_443" {
  command = plan

  variables {
    egress_mode          = "restricted"
    vpc_cidr             = "10.40.0.0/16"
    s3_prefix_list_id    = "pl-123"
    egress_allowed_cidrs = ["203.0.113.10/32"]
  }

  assert {
    condition     = length(aws_vpc_security_group_egress_rule.app_https_out) == 0
    error_message = "restricted mode must not allow 443 to 0.0.0.0/0"
  }

  assert {
    condition     = aws_vpc_security_group_egress_rule.app_https_vpc[0].cidr_ipv4 == "10.40.0.0/16"
    error_message = "restricted mode must reach interface endpoints in the VPC"
  }

  assert {
    condition     = aws_vpc_security_group_egress_rule.app_https_s3[0].prefix_list_id == "pl-123"
    error_message = "restricted mode must reach S3 through the gateway endpoint prefix list"
  }

  assert {
    condition     = keys(aws_vpc_security_group_egress_rule.app_https_allowed) == ["203.0.113.10/32"]
    error_message = "allow-listed CIDRs get one rule each"
  }
}

run "restricted_egress_rejected_on_lowcost_host" {
  command = plan

  variables {
    mode              = "lowcost"
    egress_mode       = "restricted"
    vpc_cidr          = "10.40.0.0/16"
    s3_prefix_list_id = "pl-123"
  }

  expect_failures = [var.egress_mode]
}

run "restricted_egress_needs_endpoint_inputs" {
  command = plan

  variables {
    egress_mode = "restricted"
  }

  expect_failures = [var.egress_mode]
}

run "allow_list_cannot_be_the_whole_internet" {
  command = plan

  variables {
    egress_mode          = "restricted"
    vpc_cidr             = "10.40.0.0/16"
    s3_prefix_list_id    = "pl-123"
    egress_allowed_cidrs = ["0.0.0.0/0"]
  }

  expect_failures = [var.egress_allowed_cidrs]
}
