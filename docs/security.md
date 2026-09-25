# Security

## Controls in place
- **Network:** 3 tiers, SG-to-SG rules, data subnets with no internet route, locked default SG, REJECT flow logs.
- **Edge (WAF):** WAFv2 web ACL on the ALB (`modules/waf`), per env via `waf = {...}`: on in prod-like (block), off in staging, n/a in dev (no ALB). See [WAF](#waf).
- **Egress:** optional restricted mode for the app SG (`egress = { mode = "restricted" }`): 443 only to VPC endpoints, S3 and a CIDR allow-list. See [Egress](#egress).
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
| Slotwise egress stays open (tasks reach any host on :443) | webhook targets are customer-chosen URLs; SGs filter by IP, not hostname | egress proxy (e.g. smokescreen) for webhooks + restricted SG mode for everything else, or AWS Network Firewall with SNI domain lists |
| WAF not tuned against real traffic | never applied to AWS | run `mode = "count"` for a week, review logs, add `count_rules`, then block |
| Redis without AUTH token | SG-restricted + TLS; lab simplicity | `auth_token` from Secrets Manager |
| No permissions boundary on roles created by the apply role | prefix scoping covers the lab | an IAM permissions boundary required on `iam:CreateRole` |
| AWS-managed KMS keys | CMK cost | customer-managed keys with key policies per env |
| No GuardDuty / Security Hub / CloudTrail org trail | account-level, outside this repo | enable in a security/bootstrap stack |
| ALB access logs off | log bucket + policy | enable with a lifecycle-managed bucket |

## WAF
`modules/waf`: a REGIONAL WAFv2 web ACL associated with the ALB.

| Priority | Rule | Why |
|---|---|---|
| 0 | per-IP rate limit (default 2,000 req / 5 min → 429) | flood backstop; evaluated first so floods aren't billed through the managed groups. The app keeps its own per-user limits. |
| 5 | `AWSManagedRulesKnownBadInputsRuleSet` | Log4Shell/JNDI, Java deserialisation. **Fixed and always blocking**, even in count mode (no legitimate traffic matches). |
| 10+ | `var.managed_rule_groups`: IP reputation, Common Rule Set, SQLi | the configurable part |

- **Rollout:** `mode = "count"` makes the rate rule and the configurable groups count. Watch the logs, then switch to `block`.
- **Known false positive handled:** `SizeRestrictions_BODY` (8 KB body limit) only counts, because booking/webhook JSON can exceed it. Uploads bypass the ALB via presigned S3 URLs.
- **Logs:** `aws-waf-logs-<name>` (the required prefix). Only BLOCK/COUNT requests are kept (cost), and `authorization`/`cookie` headers are redacted.
- **Tests:** `modules/waf/tests/waf.tftest.hcl`: count vs block behaviour, rule order, the Log4Shell group can't be removed, log redaction, association.

## Egress
`modules/security` has `egress_mode`:
- `open` (default): app SG → 0.0.0.0/0:443.
- `restricted` (standard mode only): app SG → VPC CIDR:443 (interface endpoints for ECR/SSM/Logs), → S3 gateway prefix list:443,
  → each `egress_allowed_cidrs` entry:443. Validation rejects it without interface endpoints (tasks couldn't pull images) and rejects `0.0.0.0/0` in the allow-list.

**Why prod-like still uses `open`:** Slotwise delivers webhooks to URLs its customers choose, and security groups match IPs, not hostnames.
An allow-list can't express "any customer endpoint". So restricted mode fits workloads with fixed destinations (e.g. rag-engine calling one
LLM provider with published IP ranges). The honest fix for Slotwise is a dedicated egress proxy for webhook delivery (its SSRF guard already
blocks private ranges) plus restricted mode for everything else. **Not built:** AWS Network Firewall (SNI-based domain allow-lists) is the
managed option, but it needs firewall subnets and route-table changes, and costs roughly as much as the rest of staging (estimate, see cost.md).

## CIS AWS Foundations: quick map
Covered: no root keys used by automation, no IAM users with keys, MFA/OIDC-based access, S3 public access blocked,
EBS/RDS encryption, default SG restricted (5.4), flow logs enabled, no 0.0.0.0/0 → 22.
Not covered here (account level): CloudTrail in all regions, AWS Config, root MFA, password policy.
