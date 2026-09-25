# Secrets flow

Goal: real secret values never appear in `.tf` files, plan output, Terraform state, git, or CI logs.

```
 operator / CI                     AWS SSM Parameter Store                  runtime
 ─────────────                     ───────────────────────                  ───────
 terraform apply  ──creates──▶  /slotwise/<env>/JWT_SECRET = "PLACEHOLDER"   (lifecycle ignore_changes = [value])
 scripts/put-secret.sh ──sets──▶ /slotwise/<env>/JWT_SECRET = <real>  (SecureString, KMS aws/ssm)
                                        │
                ECS: task definition `secrets` → agent fetches via execution role → env var SLOTWISE_JWT_SECRET
                dev: fetch-env.sh on the host (instance profile) → /opt/slotwise/.env (mode 600)
```

## Parameters per env
| Name | Kind | Set by |
|---|---|---|
| `DATABASE_URL`, `MIGRATION_DATABASE_URL`, `WORKER_DATABASE_URL` | SecureString | operator (after creating DB roles) |
| `APP_DB_PASSWORD`, `WORKER_DB_PASSWORD` | SecureString | operator (`openssl rand -base64 32`) |
| `POSTGRES_PASSWORD` (dev only: container Postgres) | SecureString | operator |
| `JWT_SECRET`, `FERNET_KEY`, `MOCKPAY_WEBHOOK_SECRET` | SecureString | operator |
| `REDIS_URL`, `CELERY_BROKER_URL`, `S3_BUCKET` | String | **Terraform** (derived from other resources, not secret) |

## RDS master password
`manage_master_user_password = true`: RDS generates the password and stores it in **Secrets Manager**.
Terraform only sees the secret's ARN (`db_master_secret_arn` output). The master user is used once, to run
`modules/compute-ec2/files/db-roles.sh`, which creates the least-privilege `slotwise_app` (RLS enforced) and
`slotwise_worker` (BYPASSRLS) roles. After that the app never uses it.

## Bootstrap checklist (per env)
```bash
for s in JWT_SECRET MOCKPAY_WEBHOOK_SECRET APP_DB_PASSWORD WORKER_DB_PASSWORD; do
  openssl rand -base64 36 | tr -d '\n' | scripts/put-secret.sh staging "$s" -
done
python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())" | scripts/put-secret.sh staging FERNET_KEY -
# create DB roles (via ECS Exec into any task, or a bastion), then set the three DATABASE_URL values
```
`fetch-env.sh` refuses to start the dev stack while any value is still `PLACEHOLDER`, so a missed secret fails loudly.

## Residual risks (honest)
- SecureString parameters use the AWS-managed `aws/ssm` key. A customer-managed key would add key-policy control and audit separation.
- Env-var injection means anything that can read `/proc/<pid>/environ` in the container can see secrets. Mounting them as files is stronger
  (checkov CKV_K8S_35), but it needs app changes.
- No automatic rotation. `db-roles.sh` re-applies passwords, so rotating means "put new value → run script → redeploy".
