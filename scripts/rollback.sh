#!/usr/bin/env bash
# Roll back to a previous image tag.
#   scripts/rollback.sh dev            host swaps back to its recorded .previous_tag
#   scripts/rollback.sh dev <sha>      host deploys that exact tag
#   scripts/rollback.sh staging <sha>  ECS redeploys the given (immutable) tag
# Schema: migrations follow expand/contract, so the previous image still works on the current schema.
# Never down-migrate during an incident. See docs/rollback.md.
set -euo pipefail
ENV="${1:?usage: rollback.sh <env> [previous_sha]}"
TO="${2:-}"
REGION="${AWS_REGION:-ap-south-1}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tf_out() { (cd "$ROOT/envs/$ENV" && terraform output -raw "$1"); }

if [ "$ENV" = dev ]; then
  "$ROOT/scripts/ssm-deploy.sh" "$REGION" "$(tf_out instance_id)" "${TO:---rollback}"
else
  [ -n "$TO" ] || { echo "ECS rollback needs an explicit tag: rollback.sh $ENV <sha>" >&2; exit 1; }
  "$ROOT/scripts/ecs-deploy.sh" "$REGION" "$(tf_out ecs_cluster_name)" "$TO"
fi
"$ROOT/scripts/smoke.sh" "$(tf_out base_url)"
