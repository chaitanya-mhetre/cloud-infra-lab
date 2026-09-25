#!/usr/bin/env bash
# Drop-in for scripts/tools.sh when the tools are installed locally (e.g. inside the toolbox image):
#   make check TOOLS=scripts/local-tools.sh
set -euo pipefail
exec "$@"
