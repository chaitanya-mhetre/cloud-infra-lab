# IAM model

Principle: **one role per actor, scoped to what that actor does**. No IAM users and no long-lived access keys anywhere.

| Role | Assumed by | Can | Cannot | Defined in |
|---|---|---|---|---|
| `<env>-host` (instance profile) | low-cost EC2 | SSM agent, read `/slotwise/<env>/*`, pull the slotwise image, write its log group | read other envs' params, push images, touch IAM | `modules/iam/ec2.tf` |
| `<env>-ecs-exec` | ECS agent | pull image, read `/slotwise/<env>/*` (decrypt via SSM only), write logs | anything at runtime inside the app | `modules/iam/ecs.tf` |
| `<env>-ecs-task` | the app code | `s3:Get/Put/DeleteObject` on `uploads/*` of its bucket, ECS Exec channels | read secrets directly, list buckets | `modules/iam/ecs.tf` |
| `cil-gh-plan` | GitHub Actions, **PRs of the infra repo** | ReadOnlyAccess + state read/lock | decrypt secrets (no kms:Decrypt), change anything | `modules/iam/github.tf` |
| `<env>-gh-apply` | GitHub Actions, **infra repo + environment `infra-<env>`** (required reviewers) | PowerUser + IAM limited to roles named `<env>-*` | create/modify IAM outside its prefix (no escalation to admin) | `modules/iam/github.tf` |
| `<env>-gh-deploy` | GitHub Actions, **app repos, `main` branch only** | push to the ECR repo, register task defs, update services **in its cluster**, PassRole to its 2 ECS roles only; dev: SSM RunCommand on instances tagged `Env=<env>` | change infrastructure, read state, pass any other role | `modules/iam/github.tf` |
| `<env>-rds-monitoring` | RDS | Enhanced Monitoring | — | `modules/database` |
| `<env>-flow-logs` | VPC Flow Logs | write to its log group | — | `modules/network` |

## How GitHub → AWS works without keys (OIDC)
1. The workflow requests `id-token: write`. GitHub mints a JWT for this job, with claims like
   `sub = repo:<owner>/cloud-infra-lab:environment:infra-staging` and `aud = sts.amazonaws.com`.
2. `aws-actions/configure-aws-credentials` calls `sts:AssumeRoleWithWebIdentity` with that JWT.
3. The role's trust policy requires `aud == sts.amazonaws.com` **and** an exact `sub` match (StringEquals, no wildcards).
   A fork, another branch, or a PR can't satisfy the apply/deploy subjects.
4. STS returns credentials that last ≤ 1 hour. Nothing is stored in GitHub secrets.

## Techniques worth naming in interviews
- **Separate execution and task roles.** The agent's secret-reading rights aren't available to app code.
- **Confused-deputy guard.** The ECS trust policy requires `aws:SourceAccount = <this account>`.
- **`kms:ViaService` condition.** A role can decrypt only through SSM, not arbitrary KMS ciphertext.
- **`iam:PassedToService` condition.** The deploy role can pass its roles only to `ecs-tasks.amazonaws.com`.
- **Resource-tag condition.** The dev deploy role can RunCommand only on instances tagged `Env=dev`.
- **Name-prefix scoping instead of a permissions boundary.** Simpler, and it covers the lab. The upgrade is a real permissions boundary
  attached to every role the apply role creates (listed in security.md as a gap).

## Known trade-offs
- The apply role is broad (PowerUserAccess). Applying infrastructure needs broad rights. The mitigations are the reviewer-gated
  environment, 1-hour sessions, IAM prefix scoping, and CloudTrail. It's never used from laptops for staging or prod-like.
- `ecr:GetAuthorizationToken`, `ecs:RegisterTaskDefinition` and `ssmmessages:*` require `Resource: "*"`. That's an AWS limitation, noted inline.
