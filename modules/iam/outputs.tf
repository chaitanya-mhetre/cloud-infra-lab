output "ec2_instance_profile_name" {
  description = "Instance profile for the low-cost host (null if not created)."
  value       = one(aws_iam_instance_profile.ec2[*].name)
}

output "ec2_role_arn" {
  description = "Role ARN of the low-cost host."
  value       = one(aws_iam_role.ec2[*].arn)
}

output "github_plan_role_arn" {
  description = "Role for PR plans (set as repo variable AWS_PLAN_ROLE_ARN)."
  value       = one(aws_iam_role.gh_plan[*].arn)
}

output "github_apply_role_arn" {
  description = "Role for gated applies (set as environment variable AWS_APPLY_ROLE_ARN)."
  value       = one(aws_iam_role.gh_apply[*].arn)
}

output "github_deploy_role_arn" {
  description = "Role for app deploy pipelines (set as AWS_DEPLOY_ROLE_ARN in the app repo)."
  value       = one(aws_iam_role.gh_deploy[*].arn)
}
