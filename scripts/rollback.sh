#!/usr/bin/env bash
# Roll back to a previous image tag.
#   scripts/rollback.sh dev            host swaps back to .previous_tag
#   scripts/rollback.sh staging <sha>  ECS redeploys the given (immutable) tag
# Schema: migrations follow expand/contract, so the previous image still works on the current schema.
# Never "down-migrate" during an incident. See docs/rollback.md.
set -euo pipefail
ENV="${1:?usage: rollback.sh <env> [previous_sha]}"
TO="${2:-}"
REGION="${AWS_REGION:-ap-south-1}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ "$ENV" = dev ]; then
  INSTANCE="$(cd "$ROOT/envs/dev" && terraform output -raw instance_id)"
  arg="--rollback"; [ -n "$TO" ] && arg="$TO"
  aws ssm send-command --region "$REGION" --instance-ids "$INSTANCE" --document-name AWS-RunShellScript \
    --comment "rollback" --parameters "commands=[\"/opt/slotwise/host-deploy.sh $arg\"]" \
    --query Command.CommandId --output text
else
  [ -n "$TO" ] || { echo "ECS rollback needs an explicit tag: rollback.sh $ENV <sha>" >&2; exit 1; }
  exec "$ROOT/scripts/deploy.sh" "$ENV" "$TO"
fi
