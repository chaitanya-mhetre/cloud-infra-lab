#!/usr/bin/env bash
# Render compute-ec2 templates (HTTP-only and TLS variants) and lint the output offline.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/.tools/render"
rm -rf "$OUT"; mkdir -p "$OUT"
cd "$ROOT/tests/render"
"$ROOT/scripts/tools.sh" terraform init -backend=false -input=false >/dev/null

for variant in http tls; do
  domain=""; [ "$variant" = tls ] && domain="dev.example.com"
  mkdir -p "$OUT/$variant"
  for f in docker-compose.yml nginx.conf fetch-env.sh host-deploy.sh cloud-init.yaml; do
    # terraform console prints heredoc form for multi-line strings; jsonencode gives an exact round-trip.
    echo "jsonencode(local.rendered[\"$f\"])" \
      | "$ROOT/scripts/tools.sh" terraform console -var "domain_name=$domain" \
      | python3 -c 'import sys,json; sys.stdout.write(json.loads(json.loads(sys.stdin.read())))' > "$OUT/$variant/$f"
  done
done

echo "== shellcheck"
mapfile -t repo_scripts < <(cd "$ROOT/scripts" && printf '/scripts/%s\n' *.sh)
docker run --rm -v "$OUT:/mnt" -v "$ROOT/scripts:/scripts:ro" koalaman/shellcheck:stable \
  /mnt/http/fetch-env.sh /mnt/http/host-deploy.sh "${repo_scripts[@]}"

echo "== cloud-init YAML parses"
for v in http tls; do python3 -c "import yaml,sys; yaml.safe_load(open(sys.argv[1]))" "$OUT/$v/cloud-init.yaml" 2>/dev/null \
  || docker run --rm -v "$OUT:/mnt" python:3.12-alpine sh -c "pip -q install pyyaml >/dev/null 2>&1 && python -c \"import yaml; yaml.safe_load(open('/mnt/$v/cloud-init.yaml'))\""; done

echo "== docker compose config"
for v in http tls; do
  printf 'SLOTWISE_POSTGRES_PASSWORD=x\nIMAGE_TAG=abc1234\n' > "$OUT/$v/.env"
  (cd "$OUT/$v" && IMAGE_TAG=abc1234 docker compose -f docker-compose.yml config -q)
done

echo "== nginx -t"
for v in http tls; do
  extra=()
  if [ "$v" = tls ]; then
    mkdir -p "$OUT/tls/le/live/dev.example.com"
    openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj "/CN=dev.example.com" \
      -keyout "$OUT/tls/le/live/dev.example.com/privkey.pem" -out "$OUT/tls/le/live/dev.example.com/fullchain.pem" 2>/dev/null
    extra=(-v "$OUT/tls/le:/etc/letsencrypt:ro")
  fi
  docker run --rm --add-host api:127.0.0.1 -v "$OUT/$v/nginx.conf:/etc/nginx/conf.d/default.conf:ro" "${extra[@]}" \
    nginx:1.27-alpine nginx -t -q
done
echo "✔ rendered templates OK"
