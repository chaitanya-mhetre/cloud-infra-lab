#!/usr/bin/env bash
# After teardown: list anything still tagged for this env that costs money while idle.
# Exit 1 if leftovers exist, so the nightly workflow fails loudly.
set -euo pipefail
ENV="${1:?usage: cost-check.sh <env>}"
REGION="${AWS_REGION:-ap-south-1}"

echo "== resources still tagged Project=cil, Env=$ENV"
left="$(aws resourcegroupstaggingapi get-resources --region "$REGION" \
  --tag-filters Key=Project,Values=cil Key=Env,Values="$ENV" \
  --query 'ResourceTagMappingList[].ResourceARN' --output text)"

# Untaggable/commonly-forgotten cost items, checked explicitly.
eips="$(aws ec2 describe-addresses --region "$REGION" --query 'Addresses[?AssociationId==null].PublicIp' --output text)"
nats="$(aws ec2 describe-nat-gateways --region "$REGION" --filter Name=state,Values=available \
  --query 'NatGateways[].NatGatewayId' --output text)"
vols="$(aws ec2 describe-volumes --region "$REGION" --filters Name=status,Values=available \
  --query 'Volumes[].VolumeId' --output text)"

status=0
for label in "tagged resources:$left" "unattached EIPs:$eips" "NAT gateways:$nats" "detached EBS volumes:$vols"; do
  name="${label%%:*}"; val="${label#*:}"
  if [ -n "${val// /}" ]; then echo "  ✘ $name: $val"; status=1; else echo "  ✔ no $name"; fi
done
exit $status
