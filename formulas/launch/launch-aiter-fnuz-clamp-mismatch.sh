#!/usr/bin/env bash
set -euo pipefail

# Launches the aiter-fnuz-clamp-mismatch formula (gfx942 lane +
# MI350/gfx950 remote lane). Forwards any extra args/vars to
# scripts/gc-sling-formula.sh, e.g.:
#   formulas/aiter-fnuz-clamp-mismatch/launch.sh --var remote_host=c13
#   formulas/aiter-fnuz-clamp-mismatch/launch.sh --var formula_id=my-run -n

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
city_root="$(cd "$script_dir/.." && pwd)"

exec "$city_root/scripts/gc-sling-formula.sh" \
  vllm/investigation.investigator aiter-fnuz-clamp-mismatch "$@"
