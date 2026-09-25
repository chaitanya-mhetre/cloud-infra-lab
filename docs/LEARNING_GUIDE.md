# Learning guide: cloud-infra-lab

This guide is for self-study. Read it with the code open. The goal is to be able to **draw every diagram from memory and
defend every decision** in an interview. Nothing here has been applied to a real AWS account yet, so say that plainly when asked
("validated offline with terraform validate/test, tflint, checkov; Kubernetes parts tested live on kind").

---

## 0. Mental model in one paragraph
Terraform describes AWS resources as code. **Modules** are reusable building blocks (network, database, ...).
**Environments** (`envs/dev`, `envs/staging`, ...) are root configurations that call those modules with different inputs and keep
their own **state** in S3, with a DynamoDB **lock**. `dev` is a single cheap EC2 host running Docker Compose; `staging`/`prod-like`
run the "real" architecture: ALB → ECS Fargate → RDS + ElastiCache. GitHub Actions authenticates to AWS with **OIDC** (no keys),
plans on every PR, and applies only through a reviewer-gated environment. The Kubernetes track re-deploys the same apps with Helm on a local kind cluster.

---

## 1. Reading order (file tour)

| # | File | What to learn there |
|---|---|---|
| 1 | `bootstrap/main.tf` | the chicken-and-egg of remote state; versioned + encrypted + TLS-only bucket; the lock table; the OIDC provider |
| 2 | `envs/dev/versions.tf` | partial backend config (`backend.hcl`), `default_tags` on every resource |
| 3 | `modules/network/main.tf` | `cidrsubnet()` subnet plan, 3 route tables, single NAT trade-off, S3 gateway endpoint, flow logs |
| 4 | `modules/network/tests/network.tftest.hcl` | **`terraform test` with `mock_provider`**: unit-testing IaC offline |
| 5 | `modules/security/main.tf` | SG-to-SG rules; standard vs lowcost via a `mode` variable and `count`/`for_each` |
| 6 | `modules/secrets/main.tf` | `lifecycle { ignore_changes = [value] }`: keeping secrets out of state |
| 7 | `modules/iam/data.tf`, `ec2.tf`, `ecs.tf` | policy documents, conditions (`kms:ViaService`, `aws:SourceAccount`), execution vs task role |
| 8 | `modules/iam/github.tf` | OIDC trust policies (exact `sub`), plan/apply/deploy role split |
| 9 | `modules/compute-ec2/` + `files/*.tftpl` | `templatefile()`, cloud-init, IMDSv2, compose stack, `host-deploy.sh` auto-rollback |
| 10 | `scripts/test-render.sh` | rendering templates with `terraform console` and linting the output (shellcheck, `compose config`, `nginx -t`) |
| 11 | `modules/registry/main.tf` | immutable tags, scan on push, lifecycle policy |
| 12 | `modules/database/main.tf` | RDS in isolated subnets, `manage_master_user_password`, parameter group (`rds.force_ssl`) |
| 13 | `modules/cache/main.tf` | why `maxmemory-policy noeviction` for a Celery broker |
| 14 | `modules/loadbalancer/main.tf` | ALB, target group health checks, ACM DNS validation, HTTP→HTTPS, blocking `/metrics` |
| 15 | `modules/compute-ecs/main.tf` | task definitions, Fargate arm64, circuit breaker, beat singleton, Spot workers, target-tracking autoscaling |
| 16 | `modules/stack-standard/main.tf` | composing modules; why there's no dependency cycle between `iam` and `ecs` |
| 17 | `modules/observability/main.tf` | metric-math alarms (rate, not count), percentiles, log metric filters, EC2 auto-recover |
| 18 | `scripts/ecs-deploy.sh` | register revision → migrate → roll → detect circuit-breaker rollback |
| 19 | `.github/workflows/*.yml` | PR plan comments, gated apply, nightly destroy, drift detection |
| 20 | `k8s/charts/slotwise/templates/*` | Deployments, probes, HPA, PDB, NetworkPolicy, Helm hooks for migrations |
| 21 | `scripts/k8s.sh`, `docs/measurements/` | how the kind numbers were produced |

---

## 2. Terraform concepts, with pointers

### State and locking
- **State** maps resources in code to real IDs. Without it, Terraform can't know what exists.
- **Remote state in S3** so CI and laptops share one truth; **versioning** so a bad write can be recovered (`bootstrap/main.tf`).
- **Locking** (DynamoDB `LockID`) stops two applies corrupting state. Terraform ≥ 1.10 can also lock natively in S3
  (`use_lockfile`). This repo pins 1.9 and uses DynamoDB, the classic pattern interviewers expect.
- **Bootstrap uses local state** because it creates the bucket everything else stores state in.
- **`prevent_destroy`** on the state bucket.

### Modules
- Small and single-purpose (network, security, database…), with typed `variables.tf` + `validation` blocks (see `az_count`, `mode`).
- **Composition module** `stack-standard` wires them together so staging and prod-like differ **only in inputs**. That's DRY without
  Terragrunt.
- Outputs are the module's API (`endpoint`, `cluster_arn`, …). Envs read other stacks by **naming convention / data sources**
  (`data.aws_ecr_repository`), not `terraform_remote_state`, which keeps stacks loosely coupled.

### `count` vs `for_each`
- `count` for on/off (`count = var.enable_nat_gateway ? 1 : 0`) and N identical things (subnets).
- `for_each` for sets keyed by name (interface endpoints, SG rules per CIDR). Removing one item doesn't shift the others' addresses.
- `one(resource[*].attr)` turns a 0-or-1 list into a value-or-null output.

### A real bug the tests caught
`modules/observability`: `local.alb ? [w1, w2] : []` fails when the condition is false, because **both branches of a conditional
must have the same type** (a 2-tuple vs a 0-tuple). `terraform validate` didn't catch it, but `terraform test` did on the first plan of the
dev-style inputs. The fix is to tag each widget with `on = ...` and filter with a `for` expression. Good interview story: "why I test IaC".

### Secrets and state
Anything Terraform sets ends up in state. So secrets are created as `PLACEHOLDER` with `ignore_changes = [value]` and set out of band
(`scripts/put-secret.sh`). RDS generates its own master password (`manage_master_user_password`).

### Drift
`plan -detailed-exitcode` → 0 no changes, 1 error, **2 changes = drift**. `.github/workflows/drift.yml` opens an issue.

---

## 3. AWS networking and security

- **CIDR math:** `cidrsubnet("10.20.0.0/16", 8, 10)` = `10.20.10.0/24` (8 extra bits → /24; index 10).
- **Public subnet** = its route table has `0.0.0.0/0 → IGW`. **Private** = no IGW route (maybe NAT). **Isolated (data)** = no default route at all.
- **NAT gateway**: lets private tasks start outbound connections; inbound is impossible. Billed hourly + per GB → single NAT + endpoints.
- **Security group vs NACL**: SGs are stateful and attach to ENIs (return traffic is automatic). NACLs are stateless and apply per subnet.
  Here: SGs only, referencing each other.
- **IMDSv2** (`http_tokens = "required"`): the metadata service needs a session token from a PUT, so a simple SSRF GET can't steal
  instance credentials. Hop limit 2 so containers on the host can still reach it.
- **SSM Session Manager** instead of SSH: no open port, IAM-controlled, logged.

## 4. IAM (see docs/iam.md for the full table)
- **Trust policy** (who can assume) vs **permission policy** (what they can do).
- **OIDC**: GitHub signs a JWT; the AWS role trusts `token.actions.githubusercontent.com` if `aud` and `sub` match exactly.
- **Execution vs task role** in ECS. **PassRole** is how you let CI hand a role to a service without being able to use it yourself.
- Conditions used: `kms:ViaService`, `aws:SourceAccount`, `iam:PassedToService`, `ssm:resourceTag/Env`, `ecs:cluster`.

## 5. Compute and deploys
- **Low-cost**: cloud-init writes files (base64) and starts compose; `host-deploy.sh` = pull → migrate → up → readiness poll → record tags
  or auto-rollback. Tags are immutable, so there's no `latest`; the host boots idle until the first `deploy`.
- **ECS**: task definition = the container spec (image, cpu/mem, secrets, logs); service = keep N copies running, roll them, attach to the ALB.
  - `deployment_minimum_healthy_percent = 100`, `maximum = 200`: surge first, then drain.
  - **Circuit breaker + rollback**: ECS reverts to the last good revision if new tasks keep failing.
  - `lifecycle.ignore_changes = [task_definition, desired_count]`: deploys and autoscaling own those, not Terraform.
  - Beat: `min 0 / max 100` (stop before start) so there's never two schedulers. Workers on **FARGATE_SPOT**, which is safe because
    Celery acks late and `stopTimeout = 120` lets the current task finish.
  - `readonlyRootFilesystem` + a `/tmp` volume; `initProcessEnabled` so PID 1 forwards SIGTERM and reaps zombies.
- **Migrations**: always a separate one-off task **before** rolling services; expand/contract so the old code keeps working.

## 6. Observability
- Alert on **symptoms** (5xx rate, p95), then **saturation** (CPU, memory, storage, Redis memory).
- **Rate via metric math**: `IF(requests > 20, 100*errors/requests, 0)` ignores low-traffic noise.
- **Percentiles** (`extended_statistic = "p95"`) instead of averages: an average hides the slow tail.
- **Log metric filter** on JSON logs: `{ $.level = "error" }`.
- **EC2 auto-recover action** on system status check failure.

## 7. CI/CD
- **infra-ci**: fmt → validate (every stack) → `terraform test` → tflint → checkov → gitleaks → template render tests → helm lint/kubeconform.
- **PR plan** with the read-only role, posted as a comment; plans that destroy/replace need the `allow-destroy` label.
- **infra-apply**: manual dispatch → environment with reviewers → plan → apply **that exact plan file**.
- **nightly-destroy-dev**: cost guard. **drift**: weekly plan → issue.
- **App pipeline** (`ci-templates/app-deploy.yml`): test → build arm64 on an arm runner → trivy (fail on fixable HIGH/CRITICAL) →
  push `:<sha>` → deploy dev → smoke. Promotion re-deploys the **same tag** (build once, deploy many).

## 8. Kubernetes (kind)
- **Deployment** (ReplicaSets, rolling update), **Service** (stable virtual IP → pods via label selector), **Ingress** (HTTP routing
  via ingress-nginx), **HPA** (scale on CPU from metrics-server), **PDB** (limits voluntary disruptions), **NetworkPolicy**
  (default-deny ingress, then allow ingress-nginx/monitoring), **Job** (migrations).
- **Probes**: startup (slow boot allowed), **liveness** `/healthz` (process wedged? → restart; must NOT check the DB),
  **readiness** `/readyz` (checks DB/Redis; failing just removes the pod from endpoints). Mixing these up means a DB blip restarts every pod.
- **Graceful shutdown**: `preStop: sleep 5` so endpoints are removed before the app stops accepting connections;
  `terminationGracePeriodSeconds` longer for workers.
- **Helm hooks**: ConfigMap/Secret/SA at weight -10 and the migration Job at 0, both `pre-install,pre-upgrade`. A failed migration aborts the upgrade.
  Trade-off: hook resources survive `helm uninstall`.
- **Security context**: non-root, read-only root FS, drop ALL capabilities, seccomp RuntimeDefault, `automountServiceAccountToken: false`.
- **No CPU limits** on purpose: CFS throttling causes latency spikes. Memory limits stay, because memory can't be throttled, only OOM-killed.
- `/metrics` blocked at the Ingress by routing the exact path to a **Service with no endpoints** (503). Snippet annotations
  are disabled in modern ingress-nginx (CVE-2021-25742).
- **Measured on kind** (laptop, single node): load start → HPA decision ~31 s → 4 ready pods ~42 s; a rolling restart under load
  returned 11,974/11,974 HTTP 200. See docs/measurements/.

---

## 9. Interview questions (with short answers)

1. **Draw your VPC. Why are databases in isolated subnets?**
   Public (ALB, NAT), app (tasks, NAT egress only), data (no default route). A DB with no route to the internet can't send data out
   even if compromised, and only the app SG can reach 5432.
2. **How does the app reach the internet from a private subnet?**
   Through the NAT gateway in a public subnet. AWS API traffic can skip the NAT through VPC endpoints (S3 gateway; ECR/SSM/Logs interface).
3. **Why one NAT gateway, not one per AZ?**
   Cost. The trade-off is that an AZ-a failure removes outbound internet for AZ-b tasks. Inbound via the ALB still works, and prod-like adds endpoints.
4. **SG vs NACL?** SG: stateful, per-ENI, allow rules only. NACL: stateless, per-subnet, allow + deny, ordered rules.
5. **How does GitHub Actions authenticate to AWS without keys?**
   OIDC: GitHub issues a signed JWT per job; `AssumeRoleWithWebIdentity`; the trust policy checks `aud` and an exact `sub`
   (repo + branch/environment). Credentials last ≤ 1 hour.
6. **What stops a PR from a fork from deploying?**
   The deploy role only trusts `repo:<owner>/<app>:ref:refs/heads/main`; apply only trusts `environment:infra-<env>`, which has reviewers.
7. **Execution role vs task role?** Execution: the ECS agent pulls images, fetches secrets, writes logs. Task: the app's own AWS calls.
8. **What is iam:PassRole and why scope it?** It's permission to hand a role to a service. Unscoped, CI could launch a task with an admin role.
9. **Where does Terraform keep state, and why lock it?** S3 (versioned, encrypted) + a DynamoDB lock, so concurrent applies can't corrupt it.
10. **How do you keep secrets out of Terraform state?** Placeholder + `ignore_changes`, values set out of band; RDS-managed master password.
11. **How do you deploy a schema change with zero downtime?** Expand/contract: additive migration first (old code still works), deploy the new
    code, backfill, and remove old columns in a later release. Migrations run before the rollout.
12. **How do you roll back?** Redeploy the previous immutable SHA. ECS's circuit breaker does it automatically on failed health checks.
    Never down-migrate during an incident.
13. **Why immutable image tags?** A tag always means the same bytes, so rollbacks and audits are trustworthy. No `latest` drift.
14. **Liveness vs readiness: what goes wrong if you mix them up?** If liveness checks the DB, a DB blip restarts every pod (a self-inflicted outage).
    Readiness should check dependencies, and failing it only removes the pod from traffic.
15. **What does a PodDisruptionBudget protect against?** Voluntary disruptions (drains, upgrades) taking replicas below `minAvailable`.
    It doesn't help with node crashes.
16. **Why no CPU limits?** CFS quota throttles even when the node has idle CPU, which causes latency spikes. Use requests for scheduling and the HPA for scale.
17. **Why is Celery beat a singleton, and how is that enforced?** Two schedulers enqueue every periodic job twice. ECS uses min 0/max 100;
    Kubernetes uses a `Recreate` strategy with 1 replica.
18. **Why `noeviction` on Redis?** It's a job broker. Evicting keys would silently drop jobs; refusing writes fails loudly.
19. **Why alert on 5xx rate instead of count?** Counts scale with traffic. Rate (with a minimum-traffic guard) means the same thing at any load.
20. **Why p95 instead of average latency?** An average hides the tail. p95/p99 show what your slowest users experience.
21. **ECS vs EKS: when would you choose each?** ECS: small team, AWS-only, no control-plane cost. EKS: many services/teams, portability,
    Kubernetes ecosystem (see docs/ecs-vs-eks.md).
22. **What drives cost in a small AWS setup?** NAT gateway, ALB, RDS (Multi-AZ doubles it), interface endpoints, public IPv4. Control it with
    a low-cost mode, nightly teardown, budgets, Graviton and Spot.
23. **How do you test Terraform?** fmt/validate, tflint, checkov, `terraform test` with mocked providers (offline unit tests),
    plan review on PRs, post-deploy smoke tests. Terratest for real integration tests in a sandbox account.
24. **What's drift and how do you detect it?** Real infrastructure differing from code (console changes). A scheduled `plan -detailed-exitcode` → exit 2.
25. **What is IMDSv2 and why enforce it?** A session-token-based metadata service; it blocks SSRF-based credential theft from EC2.
26. **How would you connect 10 ECS tasks to a small RDS without exhausting connections?** Smaller pools per task, RDS Proxy or PgBouncer, and do the
    math: tasks × pool size must stay below `max_connections`.
27. **What does `create_before_destroy` do on the ACM certificate?** It issues and validates the new cert before deleting the old one, so the listener is never left certless.

---

## 10. What to say honestly about this project
- "Everything is validated offline (terraform validate/test with a mocked provider, tflint, checkov, rendered-template linting).
  **I haven't applied it to AWS yet**, so there are no AWS cost or latency numbers. The runbook and cost log are ready for that session."
- "The Kubernetes part I ran live on kind: HPA scaling and a zero-error rolling restart, measured on my laptop."
- Known gaps are listed in `docs/security.md` and `docs/observability.md`. Knowing your gaps is a senior signal.
