#!/usr/bin/env bash
set -euo pipefail

if [ $# -lt 1 ] || [ -z "$1" ]; then
  echo "Usage: $0 <formula-name> [formula-id]" >&2
  exit 1
fi

formula="$1"
formula_id="${2:-}"

if [ -n "$formula_id" ]; then
  dir="$PWD/artifacts/$formula_id"
  mkdir -p "$dir/investigate" "$dir/experiment" "$dir/implement"
  echo "$dir"
else
  mkdir -p "artifacts/$formula"
  mktemp -d "$PWD/artifacts/$formula/run.XXXXXX"
fi
