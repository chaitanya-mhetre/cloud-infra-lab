#!/usr/bin/env bash
# Post-deploy smoke test: liveness, readiness, and a real API round-trip.
#   scripts/smoke.sh https://dev.example.com
set -euo pipefail
BASE="${1:?usage: smoke.sh <base_url>}"
fail() { echo "✘ $*" >&2; exit 1; }

echo "→ $BASE/healthz"
curl -fsS --max-time 5 "$BASE/healthz" >/dev/null || fail "healthz"

echo "→ $BASE/readyz (DB + Redis reachable)"
curl -fsS --max-time 10 "$BASE/readyz" >/dev/null || fail "readyz"

echo "→ $BASE/openapi.json"
curl -fsS --max-time 10 "$BASE/openapi.json" | grep -q '"openapi"' || fail "openapi"

# /metrics must NOT be reachable from the internet (nginx/ALB block it).
code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$BASE/metrics" || true)"
[ "$code" = "403" ] || [ "$code" = "404" ] || fail "/metrics exposed publicly (HTTP $code)"

echo "✔ smoke passed for $BASE"
