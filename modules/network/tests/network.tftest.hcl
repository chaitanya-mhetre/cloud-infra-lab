# Offline unit tests: `terraform test` with a mocked AWS provider (no credentials, no API calls).
# Run: cd modules/network && terraform test   (or `make test`)

mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = {
      names = ["ap-south-1a", "ap-south-1b", "ap-south-1c"]
    }
  }
  # Mocked data sources return random strings; policy documents must look like JSON for validation.
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
  mock_data "aws_region" {
    defaults = {
      name = "ap-south-1"
    }
  }
}

variables {
  name       = "t"
  cidr_block = "10.20.0.0/16"
}

run "lowcost_defaults" {
  command = plan

  assert {
    condition     = length(aws_subnet.public) == 2 && length(aws_subnet.app) == 2 && length(aws_subnet.data) == 2
    error_message = "expected 2 subnets per tier by default"
  }

  assert {
    condition     = aws_subnet.public[0].availability_zone != aws_subnet.public[1].availability_zone
    error_message = "public subnets must be spread over different AZs (ALB requirement)"
  }

  assert {
    condition     = [for s in aws_subnet.app : s.cidr_block] == ["10.20.10.0/24", "10.20.11.0/24"]
    error_message = "app subnet CIDR plan changed"
  }

  assert {
    condition     = [for s in aws_subnet.data : s.cidr_block] == ["10.20.20.0/24", "10.20.21.0/24"]
    error_message = "data subnet CIDR plan changed"
  }

  assert {
    condition     = alltrue([for s in concat(aws_subnet.public, aws_subnet.app, aws_subnet.data) : s.map_public_ip_on_launch == false])
    error_message = "no subnet may auto-assign public IPs"
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 0 && length(aws_route.app_nat) == 0
    error_message = "NAT gateway must be off unless requested (cost)"
  }

  assert {
    condition     = length(aws_vpc_endpoint.interface) == 0
    error_message = "interface endpoints must be off by default (cost)"
  }
}

run "standard_with_nat_and_endpoints" {
  command = plan

  variables {
    enable_nat_gateway         = true
    enable_interface_endpoints = true
    az_count                   = 3
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 1
    error_message = "exactly one NAT gateway (documented single-AZ cost trade-off)"
  }

  assert {
    condition     = length(aws_route.app_nat) == 1
    error_message = "app route table must default-route through the NAT"
  }

  assert {
    condition     = length(aws_subnet.data) == 3
    error_message = "az_count=3 should create 3 data subnets"
  }

  assert {
    condition     = length(aws_vpc_endpoint.interface) == 6
    error_message = "expected ECR api/dkr, SSM, SSM messages, EC2 messages and Logs endpoints"
  }
}

run "rejects_single_az" {
  command = plan

  variables {
    az_count = 1
  }

  expect_failures = [var.az_count]
}
