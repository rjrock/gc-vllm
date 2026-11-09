#!/usr/bin/env bash
set -euo pipefail

if [ $# -lt 2 ]; then
  echo "Usage: $0 <target> <formula-name> [gc sling flags/vars...]" >&2
  echo "Derives --var artifact_dir=... automatically unless one is already supplied." >&2
  echo "If --var formula_id=<id> is passed, artifact_dir defaults to" >&2
  echo "~/dev/cities/runs/<formula_id> with investigate/experiment/implement" >&2
  echo "subdirs." >&2
  echo "Snapshots the formula and launch command into <artifact_dir>/launch." >&2
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
  artifacts_root="$HOME/dev/cities/runs"
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

# Snapshot the formula and the launch command into <artifact_dir>/launch so a
# run stays reproducible after the formula or its launch wrapper is edited.
# Best effort: a failed snapshot warns but does not block the launch.
snapshot_launch() {
  local launch_dir="$artifact_dir/launch"
  local city_root show_args=() vars=() search_paths=() src="" dir name
  city_root="$(cd "$script_dir/.." && pwd)"
  mkdir -p "$launch_dir"

  for ((i = 0; i < ${#args[@]}; i++)); do
    if [ "${args[$i]}" = "--var" ] && [ -n "${args[$i + 1]:-}" ]; then
      vars+=(--var "${args[$i + 1]}")
    fi
  done
  if [[ "$target" == */* ]]; then
    show_args+=(--rig "${target%%/*}")
  fi

  # Compiled recipe with this launch's vars substituted.
  gc --city "$city_root" formula show "$formula" --json "${show_args[@]}" "${vars[@]}" \
    >"$launch_dir/formula.compiled.json" ||
    echo "warning: could not compile $formula into $launch_dir" >&2

  # Source TOML; later search paths (the city's own formulas/) take precedence.
  mapfile -t search_paths < <(jq -r '.search_paths[]?' "$launch_dir/formula.compiled.json" 2>/dev/null)
  search_paths+=("$city_root/formulas")
  for dir in "${search_paths[@]}"; do
    for name in "$formula.formula.toml" "$formula.toml"; do
      if [ -f "$dir/$name" ]; then
        src="$dir/$name"
      fi
    done
  done
  if [ -n "$src" ]; then
    cp "$src" "$launch_dir/$(basename "$src")"
  else
    echo "warning: no source TOML found for formula $formula" >&2
  fi

  # The launch wrapper that exec'd us, by the formulas/launch convention.
  if [ -f "$city_root/formulas/launch/launch-$formula.sh" ]; then
    cp "$city_root/formulas/launch/launch-$formula.sh" "$launch_dir/"
  fi

  # The exact, re-runnable command (artifact_dir included).
  {
    echo "#!/usr/bin/env bash"
    echo "# Launched $(date -Iseconds) by ${USER:-unknown} from $PWD"
    echo "# formulas repo: $(git -C "$city_root" rev-parse HEAD 2>/dev/null || echo unknown)"
    printf 'cd %q\n' "$PWD"
    printf '%q ' gc sling "$target" "$formula" --formula "${args[@]}"
    echo
  } >"$launch_dir/launch.sh"
  chmod +x "$launch_dir/launch.sh"
  echo "launch snapshot: $launch_dir" >&2
}

if [ "$dry_run" -eq 0 ]; then
  for ((i = 0; i < ${#args[@]}; i++)); do
    if [ "${args[$i]}" = "--var" ] && [[ "${args[$i + 1]:-}" == artifact_dir=* ]]; then
      artifact_dir="${args[$i + 1]#artifact_dir=}"
    fi
  done
  snapshot_launch || echo "warning: launch snapshot incomplete" >&2
fi

exec gc sling "$target" "$formula" --formula "${args[@]}"
