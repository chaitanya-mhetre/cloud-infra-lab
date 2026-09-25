# Runbook

## First-time setup (once per AWS account)
1. `cd bootstrap && cp terraform.tfvars.example terraform.tfvars && terraform init && terraform apply`
   → note `state_bucket` and `lock_table`. Keep `bootstrap/terraform.tfstate` safe (it's local state by design).
2. For each env: `cp envs/<env>/backend.hcl.example envs/<env>/backend.hcl` and fill in the bucket, table and region.
3. `make plan ENV=shared && make apply ENV=shared` → ECR repos, PR plan role, budget.
4. GitHub (infra repo): repo variables `AWS_REGION`, `TF_STATE_BUCKET`, `TF_LOCK_TABLE`, `AWS_PLAN_ROLE_ARN`;
   environments `infra-dev`, `infra-staging`, `infra-prod-like` (with required reviewers), each with `AWS_APPLY_ROLE_ARN`.
5. GitHub (app repo): copy `ci-templates/app-deploy.yml`; set `ECR_REPOSITORY`, `AWS_DEPLOY_ROLE_ARN`, `DEV_INSTANCE_ID`, `ECS_CLUSTER`, `BASE_URL`.

## Bring up dev (low-cost)
```bash
make plan ENV=dev && make apply ENV=dev
# secrets (see secrets.md), then first deploy of an image that CI already pushed:
make deploy ENV=dev IMAGE_TAG=<sha>          # SSM Run Command → host-deploy.sh → smoke test
aws ssm start-session --target "$(cd envs/dev && terraform output -raw instance_id)"   # shell, no SSH
```

## Bring up staging
```bash
terraform -chdir=envs/staging apply -var image_tag=<sha>     # or: infra-apply workflow (reviewed)
# secrets; create DB roles (db-roles.sh with the RDS master secret); set DATABASE_URLs
make deploy ENV=staging IMAGE_TAG=<sha>
```

## Tear down (every session)
`make destroy ENV=staging` → type the env name → `cost-check.sh` must report ✔ for everything.

---

## Alarms
### <a id="5xx"></a>5xx rate
1. Dashboard: did it start at a deploy? → `make rollback ENV=<env> TO=<previous sha>` first, investigate second.
2. Logs Insights on `/slotwise/<env>`: `fields @timestamp, level, msg, path | filter level="error" | sort @timestamp desc | limit 50`.
3. `/readyz` failing → check the RDS and Redis alarms (dependency down?).

### <a id="latency"></a>p95 latency
1. RDS CPU high? → Performance Insights / `pg_stat_statements` for the top query.
2. API CPU at max with HPA/autoscaling at max? → raise `max`, then look for the hot endpoint.
3. Redis memory near full? → queue backlog; scale workers.

### Deploy stuck / circuit breaker rolled back
`aws ecs describe-services --cluster <c> --services api --query 'services[0].events[:10]'` shows why tasks failed
(health check, OOM, or a secret that's still PLACEHOLDER). Stopped task reason: `aws ecs describe-tasks ... --query 'tasks[0].stoppedReason'`.

### Terraform state lock stuck
Only if you're certain no apply is running: `terraform force-unlock <LOCK_ID>` (the ID is shown in the error).
