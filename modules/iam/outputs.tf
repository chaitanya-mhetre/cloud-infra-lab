output "ec2_instance_profile_name" {
  description = "Instance profile for the low-cost host (null if not created)."
  value       = one(aws_iam_instance_profile.ec2[*].name)
}

output "ec2_role_arn" {
  description = "Role ARN of the low-cost host."
  value       = one(aws_iam_role.ec2[*].arn)
}
