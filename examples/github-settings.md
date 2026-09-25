# GitHub settings the workflows expect

## Infra repo (cloud-infra-lab)
Repository variables: `AWS_REGION`, `TF_STATE_BUCKET`, `TF_LOCK_TABLE` (bootstrap outputs), `AWS_PLAN_ROLE_ARN` (shared output),
optional `KEEP_DEV=true` to skip the nightly destroy.
Environments: `infra-dev`, `infra-staging`, `infra-prod-like`. Each has **required reviewers** and a variable
`AWS_APPLY_ROLE_ARN` (that env's `github_apply_role_arn` output). Label: `allow-destroy`.

## App repo (production-fastapi)
Variables: `AWS_REGION`, `ECR_REPOSITORY`, `AWS_DEPLOY_ROLE_ARN`, `DEV_INSTANCE_ID`, `ECS_CLUSTER`, `BASE_URL`.
Environments: `app-dev` (no reviewers), `app-staging` and `app-prod-like` (reviewers).
