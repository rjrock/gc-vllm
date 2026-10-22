#!/usr/bin/env bash
set -euo pipefail

# Launches the aiter-biased-grouped-topk-nan-clamp formula.
# Forwards any extra args/vars to scripts/gc-sling-formula.sh, e.g.:
#   formulas/launch/launch-aiter-biased-grouped-topk-nan-clamp.sh --var formula_id=my-run -n

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
city_root="$(cd "$script_dir/../.." && pwd)"

exec "$city_root/scripts/gc-sling-formula.sh" \
  aiter/investigation.investigator aiter-biased-grouped-topk-nan-clamp "$@"
