# Security

## Controls in place
- **Network:** 3 tiers, SG-to-SG rules, data subnets with no internet route, locked default SG, REJECT flow logs.
- **Hosts:** IMDSv2 required (blocks SSRF → instance credentials), no SSH (SSM Session Manager), encrypted EBS.
- **Data:** RDS/ElastiCache/S3/EBS encrypted at rest; TLS in transit (`rds.force_ssl=1`, Redis TLS, S3 TLS-only policy, ALB TLS 1.2+);
  S3 public access fully blocked, ACLs disabled.
- **Identity:** no IAM users or long-lived keys; GitHub OIDC with exact-subject trust; separate execution/task roles; least-privilege DB roles
  (the API role has RLS enforced).
- **Secrets:** SSM SecureString with values set out-of-band (never in state); RDS master password managed by RDS/Secrets Manager.
- **Supply chain:** immutable ECR tags, scan-on-push, trivy in the app pipeline, gitleaks + checkov + tflint in infra CI.
- **Kubernetes:** non-root UID 10001, read-only root FS, all capabilities dropped, seccomp RuntimeDefault, no SA token automount,
  default-deny NetworkPolicies, `/metrics` never routed publicly.

## Accepted scanner findings
Terraform findings are skipped **inline** next to the resource with the reason (`#checkov:skip=...`), so they're reviewed in code review.
Kubernetes findings skipped in `make helm-check`:
- **CKV_K8S_15 / 43** (pull policy Always / digest pinning): tags are immutable git SHAs, which gives the same guarantee.
- **CKV_K8S_35** (secrets as files): the apps read config from env vars. Files would be stronger (see secrets.md).
- **CKV_K8S_11** (CPU limits): left out on purpose. CPU limits cause CFS throttling and latency spikes; requests + HPA handle fairness.
- **CKV_K8S_9** (readiness on workers): workers take no traffic. **CKV_K8S_8** for beat: no health endpoint; it's a singleton that restarts on exit.

## Gaps (what a production review would flag)
| Gap | Why not now | Upgrade path |
|---|---|---|
| No WAF | cost | AWS WAF managed rule groups on the ALB |
| No egress filtering (tasks reach any :443) | needs a proxy/firewall | AWS Network Firewall or an egress proxy with an allow-list |
| Redis without AUTH token | SG-restricted + TLS; lab simplicity | `auth_token` from Secrets Manager |
| No permissions boundary on roles created by the apply role | prefix scoping covers the lab | an IAM permissions boundary required on `iam:CreateRole` |
| AWS-managed KMS keys | CMK cost | customer-managed keys with key policies per env |
| No GuardDuty / Security Hub / CloudTrail org trail | account-level, outside this repo | enable in a security/bootstrap stack |
| ALB access logs off | log bucket + policy | enable with a lifecycle-managed bucket |

## CIS AWS Foundations: quick map
Covered: no root keys used by automation, no IAM users with keys, MFA/OIDC-based access, S3 public access blocked,
EBS/RDS encryption, default SG restricted (5.4), flow logs enabled, no 0.0.0.0/0 → 22.
Not covered here (account level): CloudTrail in all regions, AWS Config, root MFA, password policy.
