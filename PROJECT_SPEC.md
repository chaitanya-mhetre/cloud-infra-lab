# Cloud Infra Lab
> Terraform-managed AWS infrastructure (VPC, compute, RDS, Redis, S3, IAM, monitoring) plus GitHub Actions CI/CD and a Kubernetes track. It deploys `production-fastapi`, with a low-cost mode and one-command teardown.

## 1. Problem & why it exists
My current cloud experience is operational: a single EC2 VM with Docker Compose and Nginx (Ponticare), some GCP console work at Agribid (unverified), and no Infrastructure-as-Code.
Platform-leaning roles (Razorpay AI Platform, Microsoft cloud/AI infra) expect **Terraform, networking, IAM, CI/CD, Kubernetes, observability**.
This lab builds that properly, reproducibly, and cheaply, so I can explain every subnet, security group, and IAM policy.

## 2. What this proves to an employer
| Skill | Target requirement |
|---|---|
| Terraform modules, remote state, environments | Razorpay "Terraform"; Microsoft infra |
| AWS networking (VPC, subnets, NAT, SGs), IAM least privilege | EaseOps "AWS"; Amazon SDE "AWS" |
| GitHub Actions CI/CD with OIDC to AWS (no static keys) | Razorpay "CI/CD" |
| Kubernetes (Deployments, Services, Ingress, HPA, probes) | Razorpay/Microsoft "Kubernetes" |
| Observability (CloudWatch, Prometheus/Grafana) | Razorpay "observability, Prometheus" |
| Cost awareness + teardown discipline | senior-signal engineering habit |

## 3. Scope
### In scope (v1)
- Terraform modules: `network`, `security`, `compute-ecs` (Fargate), `compute-ec2` (low-cost), `database` (RDS Postgres),
  `cache` (ElastiCache Redis, or Redis-on-EC2 in low-cost mode), `storage` (S3 + lifecycle), `loadbalancer` (ALB + ACM),
  `observability` (CloudWatch logs/alarms, optional managed Prometheus), `iam` (task roles, the GitHub OIDC role), `secrets` (SSM Parameter Store)
- Environments: `envs/dev` (low-cost), `envs/staging`, `envs/prod-like`. The same modules with different variables
- Remote state: S3 backend + DynamoDB lock table (bootstrapped by `bootstrap/`)
- GitHub Actions: app CI (in the app repo) and infra CI here (`fmt`, `validate`, `tflint`, `tfsec`/`checkov`, `plan` on PR, `apply` on manual approval)
- Deploy `production-fastapi`: push the image to ECR, run migrations as a one-off task, rolling deploy, rollback
- **Low-cost mode**: one `t4g.small` EC2 running Docker Compose (api + worker + redis), with RDS `db.t4g.micro` or Postgres in a container, and no NAT gateway (public subnet + strict SG)
- Teardown: `make destroy ENV=dev`, a nightly GitHub Actions "destroy dev" workflow, AWS Budgets alerts
- **Kubernetes track**: local kind/k3d cluster with Helm chart for `production-fastapi` (api, worker, beat), Ingress-NGINX, HPA, probes, ConfigMaps/Secrets, kube-prometheus-stack; optional short-lived EKS run
- Docs: network diagram, IAM model, secrets flow, scaling, rollback, cost estimates

### Out of scope (explicitly)
- Multi-region / DR beyond backups + a written plan
- Service mesh (Istio/Linkerd)
- Keeping any environment running 24/7 (everything is torn down after demos)
- GCP/Azure equivalents (possible later note only)

## 4. Architecture
**Standard mode (staging / prod-like)**
```
                       Route53 (optional) ─▶ ACM cert
Internet ─▶ ALB (public subnets, 2 AZs, HTTPS only, HTTP→HTTPS redirect)
              │  target group (health: /readyz)
      ┌───────▼──────────────── VPC 10.20.0.0/16 ─────────────────────────┐
      │ private app subnets (2 AZ):  ECS Fargate services                  │
      │     api (2 tasks)   worker (1–3)   beat (1)   outbox-relay (1)     │
      │           │ SG: from ALB only        │                              │
      │ private data subnets (2 AZ):                                       │
      │     RDS Postgres (SG: from app SG:5432)  ElastiCache Redis (6379)  │
      │ NAT gateway (1, cost-saving: single AZ) for outbound (SES, APIs)   │
      │ VPC endpoints: S3 (gateway), ECR/SSM/Logs (interface, prod-like)  │
      └────────────────────────────────────────────────────────────────────┘
 S3 (uploads, private, presigned)   ECR   SSM Parameter Store   CloudWatch Logs/Alarms
 GitHub Actions ──OIDC──▶ IAM role (deploy-only permissions)
```
**Low-cost mode (dev)**
```
Internet ─▶ EC2 t4g.small (public subnet, SG: 80/443 from anywhere, 22 closed. Access via SSM Session Manager)
            Docker Compose: nginx + api + worker + redis (+ postgres container OR RDS micro)
            IAM instance profile: read SSM params, pull ECR, write logs
```
- **Two AZs for ALB/RDS subnets**: ALB and RDS subnet groups require them, and it's the basis of availability discussions.
- **Private subnets for apps and data**: nothing stateful is reachable from the internet; SGs reference other SGs, not CIDRs.
- **A single NAT gateway**: a documented cost trade-off (NAT gateways are one of the biggest fixed costs). VPC endpoints reduce NAT traffic.
- **OIDC for GitHub Actions**: no long-lived AWS keys in GitHub secrets; the role is restricted to the repo and branch.
- **SSM Session Manager instead of SSH**: no port 22, and sessions are audited.

## 5. Tech stack & justification
| Choice | Why | Alternatives |
|---|---|---|
| AWS | most common in Indian product companies and the target JDs; I have EC2 experience | GCP (Agribid used it; unverified depth) |
| Terraform (≥1.9) | the IaC most JDs name; Razorpay lists it | Pulumi, CDK |
| ECS Fargate for standard mode | no node management; the concepts transfer | EKS (too expensive to keep; used briefly in the K8s track) |
| kind/k3d + Helm | free, realistic Kubernetes practice | minikube |
| tflint, tfsec/checkov, infracost (optional) | lint, security scan, cost diff on PRs | — |
| GitHub Actions | used across all repos | GitLab CI |

## 6. Data model
Infrastructure state rather than app data:
- **Terraform state**: `s3://<acct>-tfstate/<env>/terraform.tfstate`, lock table `tf-locks` (partition key `LockID`)
- **Resource naming/tagging**: `{project}-{env}-{component}`; tags `Project`, `Env`, `Owner=chaitanya`, `ManagedBy=terraform`, `TTL` (for nightly cleanup)
- **Secrets**: SSM `/slotwise/{env}/DATABASE_URL`, `/slotwise/{env}/JWT_SECRET`, ... (SecureString, KMS default key)
- **Repo layout**
```
bootstrap/                 # state bucket + lock table + GitHub OIDC provider (applied once)
modules/{network,security,iam,compute-ecs,compute-ec2,database,cache,storage,loadbalancer,observability,secrets}/
envs/{dev,staging,prod-like}/{main.tf,variables.tf,terraform.tfvars,backend.tf}
k8s/charts/slotwise/       # Helm chart
k8s/kind/cluster.yaml
scripts/{teardown.sh,cost-check.sh,smoke.sh}
.github/workflows/{infra-ci.yml,infra-apply.yml,nightly-destroy-dev.yml}
docs/{network.md,iam.md,secrets.md,scaling.md,rollback.md,cost.md,runbook.md}
```

## 7. API / interface design
Operator interface (Makefile):
```
make bootstrap                      # once per AWS account
make plan  ENV=dev|staging|prod-like
make apply ENV=...                  # requires confirmation; staging/prod-like only from CI with approval
make deploy ENV=... IMAGE_TAG=sha   # update ECS service / compose on EC2
make migrate ENV=...                # one-off ECS task running alembic upgrade head
make rollback ENV=... TO=<prev_sha>
make destroy ENV=...                # full teardown
make cost ENV=...                   # infracost breakdown (estimate)
make k8s-up / k8s-deploy / k8s-down # kind cluster + helm
```
Module interface example: `module "database" { source="../../modules/database" env=..., vpc_id, subnet_ids, allowed_sg_ids, instance_class="db.t4g.micro", backup_retention_days=1 }`
→ outputs `endpoint`, `port`, `secret_param_name`.

## 8. Key engineering problems
1. **Least-privilege IAM.** Separate roles: the ECS task execution role (pull images, read secrets) vs the task role (the app: S3 bucket prefix, SES send) vs the GitHub deploy role (ECR push, `ecs:UpdateService`, `iam:PassRole` scoped).
   IAM Access Analyzer checks the policies.
2. **Secrets flow.** Terraform must not put secret values in state where avoidable. The approach: create SSM parameters with placeholder values and set real values out-of-band or via CI. The residual risk is documented.
3. **Safe migrations during deploys.** Run the migration task first. The expand/contract rule means the old version keeps working on the new schema. The failure path is documented.
4. **Rollback.** ECS deployment circuit breaker with rollback enabled + the `make rollback TO=<sha>` image pin. On EC2, compose image tags + a previous-tag file (similar to the Ponticare `build-and-ship.sh` approach).
5. **Cost control.** NAT gateway and ALB hourly costs dominate small setups. Dev avoids both, nightly destroy removes leftovers, and a budget alert fires at a small threshold.
6. **State safety.** Remote state + locking; `prevent_destroy` on the state bucket; no `terraform apply` from laptops for staging/prod-like.
7. **Drift.** A scheduled `terraform plan -detailed-exitcode` workflow reports drift.
8. **Kubernetes correctness.** Readiness vs liveness probes (don't kill pods during a slow DB), resource requests/limits, HPA on CPU (and custom metrics as a stretch), graceful termination (`preStop`, `terminationGracePeriodSeconds`).

## 9. Milestones
**M1: Bootstrap + network (1 wk).** State bucket/lock, OIDC provider, the `network` + `security` modules, `envs/dev`.
*Accept:* `plan`/`apply`/`destroy` cycle works; diagram in `docs/network.md`; `tfsec` clean or findings justified.

**M2: Low-cost deploy (1 wk).** The `compute-ec2` module, instance profile, SSM params, Compose-based deploy of `production-fastapi`, HTTPS via Nginx + Let's Encrypt (or an ALB if the budget allows).
*Accept:* a public HTTPS smoke test passes; SSM Session Manager access works with port 22 closed; teardown leaves zero billable resources (`scripts/cost-check.sh`).

**M3: CI/CD (1 wk).** Infra CI (fmt/validate/tflint/tfsec/plan comment on PR), app pipeline build → ECR → deploy through OIDC, manual approval gate.
*Accept:* a merge to main deploys to dev automatically; the PR shows the plan output; no AWS static keys in the repo settings.

**M4: Standard mode (1–2 wks).** The `compute-ecs`, `database`, `cache`, `loadbalancer`, `storage` modules; `envs/staging`; the migration task; the deployment circuit breaker.
*Accept:* rolling deploy with zero failed requests during a k6 run (measured); rollback demo recorded.

**M5: Observability (1 wk).** CloudWatch log groups + metric filters + alarms (5xx rate, target response time, RDS CPU/storage, queue lag from the app metric); optional Amazon Managed Prometheus/Grafana or a self-hosted stack on EC2.
*Accept:* an alarm triggered deliberately (a load spike) and notification received.

**M6: Kubernetes track (2 wks).** kind cluster, Helm chart (api/worker/beat Deployments, Service, Ingress, HPA, PDB, probes, ConfigMap/Secret), kube-prometheus-stack, an HPA scale-up demo under load.
Optional: `envs/eks-demo` with a managed node group, applied for a few hours and destroyed (cost estimate recorded before and actual cost after).
*Accept:* `helm install` from a clean cluster works; the HPA scales from 2 to N pods under load (measured); a document comparing ECS vs EKS.

**M7: Docs + hardening (1 wk).** IAM doc, secrets doc, scaling and rollback docs, cost doc (estimates vs actual bill), runbook, drift-detection workflow.

## 10. Testing strategy
- Static: `terraform fmt -check`, `validate`, `tflint`, `tfsec`/`checkov` in CI.
- Plan review: every PR posts the plan; destructive changes need an explicit label.
- Integration: `terratest` (Go) or `terraform test` for the network module (subnets across 2 AZs, no public IP on private subnets).
- Post-deploy smoke: `scripts/smoke.sh` hits `/readyz` + a booking create/cancel.
- Helm: `helm lint`, `helm template | kubeconform`, `ct install` on kind in CI.

## 11. Observability
CloudWatch logs (JSON from the app) with retention set (7 days in dev); alarms as code; dashboards as code (the CloudWatch dashboard JSON or Grafana JSON).
In Kubernetes: kube-prometheus-stack, with a ServiceMonitor scraping the app's `/metrics`.

## 12. Security
- No public databases; SG-to-SG rules; IMDSv2 enforced on EC2; encrypted EBS/RDS/S3; S3 public access blocked; TLS everywhere public.
- GitHub OIDC restricted by `repo:...:ref:refs/heads/main`; deploy role can't modify IAM beyond `PassRole` to named roles.
- Secret scanning (gitleaks), IaC scanning (tfsec/checkov), image scanning (trivy) in pipelines.
- The CIS AWS Foundations quick checklist documented, with what's covered and what isn't.

## 13. Deployment
This project **is** the deployment layer. It deploys `production-fastapi` (and optionally `rag-engine`/`ai-gateway` later) using the same modules with different service definitions.

## 14. Evaluation / measurements to collect
All values are **estimates until the AWS bill confirms them**:
- Monthly cost estimate per env (infracost/AWS calculator): dev `TBD (estimate)`, staging `TBD (estimate)`. Record actual spend per demo session.
- Deploy duration (commit → live): `TBD`
- Failed requests during a rolling deploy under k6 load: `TBD`
- HPA scale-up time from load start to new pods ready: `TBD`
- Time for a full `apply` from scratch and a full `destroy`: `TBD`

## 15. Prerequisite learning
`learning/cloud/linux-networking` (CIDR, routing, NAT, DNS, TLS), `learning/cloud/aws` (IAM, VPC, EC2, RDS, S3, ECS),
`learning/cloud/terraform`, `learning/cloud/docker`, `learning/cloud/ci-cd`, `learning/cloud/kubernetes`, `learning/cloud/observability`.

## 16. Interview talking points
- "Draw your VPC. Why are the databases in private subnets? How does the app reach the internet?"
- "How does GitHub Actions authenticate to AWS without keys?"
- "How do you deploy a schema change without downtime? How do you roll back?"
- "Liveness vs readiness probes: what goes wrong if you mix them up?"
- "ECS vs EKS: when would you pick each?"
- "What drives cost in a small AWS setup, and how did you control it?"

## 17. Resume bullet templates
- Provisioned AWS infrastructure with modular Terraform (VPC across 2 AZs, ECS Fargate, RDS, ElastiCache, S3, ALB) across dev/staging environments with remote state, policy scanning, and keyless GitHub Actions OIDC deployments.
- Built a Helm chart and Kubernetes setup (HPA, probes, PDB, Prometheus monitoring) scaling from 2 to [MEASURED_VALUE] pods under load in [MEASURED_VALUE] s.
- Achieved zero-downtime rolling deploys with [MEASURED_VALUE] failed requests under k6 load and one-command rollback.

## 18. Open questions / uncertainties
- AWS free-tier/credits availability for this account: unknown. Every cost figure stays an estimate until the bill confirms it.
- Whether to use an ALB in dev (clearer architecture) or Nginx on EC2 (cheaper). The default is Nginx on EC2 in dev.
- EKS demo: only if the budget allows; kind covers the core Kubernetes concepts for interviews.
- GCP equivalents (Cloud Run, Cloud Build) could strengthen the Agribid story *if* that experience is verified; not planned.
