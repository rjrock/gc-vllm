#!/usr/bin/env bash
set -euo pipefail

if [ $# -lt 2 ]; then
  echo "Usage: $0 <target> <formula-name> [gc sling flags/vars...]" >&2
  echo "Derives --var artifact_dir=... automatically unless one is already supplied." >&2
  echo "If --var formula_id=<id> is passed, artifact_dir defaults to" >&2
  echo "~/dev/cities/gc-artifacts/<formula_id> with investigate/experiment/implement" >&2
  echo "subdirs." >&2
  exit 1
fi

target="$1"
formula="$2"
shift 2

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

args=("$@")
has_artifact_dir=0
dry_run=0
formula_id=""
for ((i = 0; i < ${#args[@]}; i++)); do
  if [ "${args[$i]}" = "--var" ] && [[ "${args[$i + 1]:-}" == artifact_dir=* ]]; then
    has_artifact_dir=1
  fi
  if [ "${args[$i]}" = "--var" ] && [[ "${args[$i + 1]:-}" == formula_id=* ]]; then
    formula_id="${args[$i + 1]#formula_id=}"
  fi
  case "${args[$i]}" in
    -n | --dry-run) dry_run=1 ;;
  esac
done

if [ "$has_artifact_dir" -eq 0 ]; then
  artifacts_root="$HOME/dev/cities/gc-artifacts"
  if [ -n "$formula_id" ]; then
    artifact_dir="$artifacts_root/$formula_id"
  else
    artifact_dir="$artifacts_root/$formula/run.XXXXXX"
  fi
  if [ "$dry_run" -eq 1 ]; then
    echo "artifact_dir (not created, dry run): $artifact_dir" >&2
  else
    artifact_dir="$("$script_dir/new-artifact-dir.sh" "$formula" "$formula_id")"
    echo "artifact_dir: $artifact_dir" >&2
  fi
  args+=(--var "artifact_dir=$artifact_dir")
fi

exec gc sling "$target" "$formula" --formula "${args[@]}"
