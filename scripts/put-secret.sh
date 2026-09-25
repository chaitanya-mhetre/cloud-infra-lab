#!/usr/bin/env bash
# Set a secret's real value in SSM without it touching Terraform state or shell history.
#   scripts/put-secret.sh dev JWT_SECRET            # prompts (hidden input)
#   openssl rand -hex 32 | scripts/put-secret.sh dev JWT_SECRET -
set -euo pipefail
ENV="${1:?usage: put-secret.sh <env> <NAME> [-]}"
NAME="${2:?usage: put-secret.sh <env> <NAME> [-]}"
REGION="${AWS_REGION:-ap-south-1}"
PARAM="/slotwise/$ENV/$NAME"

if [ "${3:-}" = "-" ]; then
  IFS= read -r VALUE
else
  read -r -s -p "Value for $PARAM: " VALUE; echo
fi
[ -n "$VALUE" ] || { echo "empty value refused" >&2; exit 1; }

aws ssm put-parameter --region "$REGION" --name "$PARAM" --type SecureString --overwrite \
  --value "$VALUE" >/dev/null
echo "set $PARAM"
