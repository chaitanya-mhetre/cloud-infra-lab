output "vpc_id" {
  description = "VPC ID."
  value       = aws_vpc.this.id
}

output "vpc_cidr_block" {
  description = "VPC CIDR."
  value       = aws_vpc.this.cidr_block
}

output "azs" {
  description = "Availability zones used."
  value       = local.azs
}

output "public_subnet_ids" {
  description = "Public subnets (ALB, NAT, low-cost EC2)."
  value       = aws_subnet.public[*].id
}

output "app_subnet_ids" {
  description = "Private application subnets (ECS tasks)."
  value       = aws_subnet.app[*].id
}

output "data_subnet_ids" {
  description = "Isolated data subnets (RDS, ElastiCache)."
  value       = aws_subnet.data[*].id
}

output "nat_gateway_enabled" {
  description = "Whether private app subnets have outbound internet."
  value       = var.enable_nat_gateway
}

output "s3_prefix_list_id" {
  description = "Prefix list of the S3 gateway endpoint (for restricted SG egress)."
  value       = aws_vpc_endpoint.s3.prefix_list_id
}
