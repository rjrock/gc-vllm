#!/usr/bin/env bash
set -euo pipefail

# Launches the inkling-fp8-kv-rel-attn-dtype-mismatch formula.
# Forwards any extra args/vars to scripts/gc-sling-formula.sh, e.g.:
#   formulas/launch/launch-inkling-fp8-kv-rel-attn-dtype-mismatch.sh --var formula_id=my-run -n

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
city_root="$(cd "$script_dir/../.." && pwd)"

exec "$city_root/scripts/gc-sling-formula.sh" \
  vllm/investigation.investigator inkling-fp8-kv-rel-attn-dtype-mismatch "$@"
