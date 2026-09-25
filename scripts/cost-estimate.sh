#!/usr/bin/env bash
# ESTIMATED monthly cost of an env from its Terraform code (infracost). Not a bill.
#   INFRACOST_API_KEY=... scripts/cost-estimate.sh staging
set -euo pipefail
ENV="${1:?usage: cost-estimate.sh <env>}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
: "${INFRACOST_API_KEY:?get a free key: https://www.infracost.io/docs/#2-get-api-key}"
docker run --rm -e INFRACOST_API_KEY -v "$ROOT:/repo" -w "/repo/envs/$ENV" infracost/infracost:ci-0.10 \
  breakdown --path . --terraform-var-file terraform.tfvars --show-skipped
echo "⚠ estimate only — record actual spend from Cost Explorer in docs/cost.md"
