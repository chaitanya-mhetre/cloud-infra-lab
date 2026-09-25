#!/usr/bin/env bash
# Destroy an environment completely, then verify nothing billable is left behind.
#   scripts/teardown.sh dev            interactive
#   CI=true scripts/teardown.sh dev    non-interactive (nightly workflow; dev only)
set -euo pipefail
ENV="${1:?usage: teardown.sh <env>}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

case "$ENV" in
  dev|staging|prod-like|eks-demo) ;;
  shared) echo "refusing: 'shared' holds the image registry; destroy it by hand if you really mean it" >&2; exit 1 ;;
  *) echo "unknown env $ENV" >&2; exit 1 ;;
esac

if [ "${CI:-}" = true ]; then
  [ "$ENV" = dev ] || { echo "non-interactive teardown is only allowed for dev" >&2; exit 1; }
  APPROVE=(-auto-approve)
else
  read -r -p "Destroy EVERYTHING in '$ENV'? Type the env name to confirm: " c
  [ "$c" = "$ENV" ] || { echo "aborted"; exit 1; }
  APPROVE=()
fi

cd "$ROOT/envs/$ENV"
terraform init -backend-config=backend.hcl -input=false >/dev/null
terraform destroy -input=false "${APPROVE[@]}"

"$ROOT/scripts/cost-check.sh" "$ENV"
