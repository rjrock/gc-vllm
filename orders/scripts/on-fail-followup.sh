#!/usr/bin/env bash
# on-fail-followup — triage every failed workflow to the mayor.
#
# General, formula-agnostic mechanism: ANY v2 formula's root bead closing with
# gc.outcome=fail gets routed to the mayor as a task bead describing the
# failure, with enough context (formula name/source, failed step, failure
# reason, report paths) for the mayor to decide what to do -- including
# authoring and launching a brand-new follow-up formula that did not exist
# when the original formula was written. This is deliberately NOT gated on
# any var the original formula author had to pre-declare: the whole point is
# that the right follow-up often isn't known until the failure is read.
#
# A formula MAY optionally declare on_fail_followup_formula/
# on_fail_followup_target vars as a fast-path hint (skip straight to a known
# follow-up instead of re-deriving it) -- see e.g.
# flint-rocm-attention-fix.formula.toml. Both are purely advisory: they're
# included in the mayor's task bead when present, and the mayor itself
# decides whether to use the hint, pick something else, or author a new
# formula. The order never slings a formula directly, because deciding
# "is this hint still right, or do I need to think harder" is a judgment
# call, not something an exec script should make.
#
# A workflow's root bead carries every formula var as gc.var.<name> (confirmed
# via `gc bd show <root> --json`), so the hint vars are readable straight off
# the bead.closed event payload.
#
# Every member step in this project's v2 formulas sets gc.on_fail=abort_scope,
# so ANY step failing closes the workflow root itself with gc.kind=workflow,
# gc.outcome=fail (confirmed empirically against vl-apjh, the
# flint-rocm-attention-fix root, which closed this way when its experiment
# step vl-13fc failed). Subscribing to the ROOT's bead.closed event -- not the
# individual step's -- means this fires exactly once per failed workflow,
# regardless of which member step actually aborted it. The failed member
# step(s) are looked up separately (gc.root_bead_id == root, gc.outcome ==
# fail) to pull the actual gc.failure_reason text, since the root bead itself
# does not carry that field.
#
# Routes to the mayor via `gc sling mayor --stdin --nudge`: creates a task
# bead (first line = title, rest = description) and wakes the always-on
# mayor session (pack.toml named_session, mode=always) so it doesn't have to
# be polled for or wait on its own idle cycle.
#
# Idempotent: a given failed root bead triggers triage at most once. Dedup
# state lives in $GC_CITY_RUNTIME_DIR/orders/on-fail-followup-state.json.
#
# Runs as an exec order (no LLM, no agent, no wisp) until the point it slings
# the triage task to the mayor.
set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
    echo "on-fail-followup: jq is required but not found in PATH" >&2
    exit 1
fi

CITY="${GC_CITY:-.}"

# Event lookback window. Must exceed the controller's event-trigger eval
# cadence so no close event is missed between runs.
LOOKBACK="${GC_ON_FAIL_FOLLOWUP_LOOKBACK:-5m}"
# Dedup entries older than this are pruned so the state file stays bounded.
# Must exceed LOOKBACK.
RETENTION="${GC_ON_FAIL_FOLLOWUP_RETENTION:-24h}"

STATE_DIR="${GC_PACK_STATE_DIR:-${GC_CITY_RUNTIME_DIR:-$CITY/.gc/runtime}/orders}"
STATE_FILE="$STATE_DIR/on-fail-followup-state.json"
mkdir -p "$STATE_DIR"

duration_to_seconds() {
    case "$1" in
        *h) echo $(( ${1%h} * 3600 )) ;;
        *m) echo $(( ${1%m} * 60 )) ;;
        *s) echo "${1%s}" ;;
        *)  echo "$1" ;;
    esac
}

# Resolve a bead id's rig into RIG_ARG1/RIG_ARG2 ("--rig" "<name>"), or leave
# them empty when the prefix is unknown / is the HQ rig (HQ beads use
# default scope). Callers expand with ${RIG_ARG1:+...} so an empty result
# adds no arguments under `set -u`.
RIGS_JSON="$(gc rig list --json 2>/dev/null || true)"
set_rig_args() {
    RIG_ARG1=""
    RIG_ARG2=""
    [ -n "$RIGS_JSON" ] || return 0
    _prefix="${1%%-*}"
    [ -n "$_prefix" ] && [ "$_prefix" != "$1" ] || return 0
    _rig="$(printf '%s' "$RIGS_JSON" \
        | jq -r --arg p "$_prefix" '(.rigs // [])[] | select(.prefix == $p and (.hq != true)) | .name' 2>/dev/null \
        | head -1)"
    if [ -n "$_rig" ]; then
        RIG_ARG1="--rig"
        RIG_ARG2="$_rig"
    fi
}

# Pull recent bead.closed events. Best-effort: a read failure must not
# crash the controller's order loop.
EVENTS="$(gc events --type bead.closed --since "$LOOKBACK" 2>/dev/null)" || exit 0
[ -n "$EVENTS" ] || exit 0

# Every failed workflow root. One line per match:
# "<root-id>\t<formula_name>\t<formula_source>\t<hint_formula>\t<hint_target>".
MATCHES="$(printf '%s\n' "$EVENTS" \
    | jq -r '
        select(.payload.bead.metadata."gc.kind" == "workflow"
               and .payload.bead.metadata."gc.outcome" == "fail")
        | .payload.bead
        | [.id,
           (.metadata."gc.formula_name" // ""),
           (.metadata."gc.formula_source" // ""),
           (.metadata."gc.var.on_fail_followup_formula" // ""),
           (.metadata."gc.var.on_fail_followup_target" // "")]
        | @tsv
      ' 2>/dev/null)" || MATCHES=""
[ -n "$MATCHES" ] || exit 0

# Load dedup state (object mapping root-bead-id -> ISO timestamp).
STATE="$(cat "$STATE_FILE" 2>/dev/null || true)"
echo "$STATE" | jq -e 'type == "object"' >/dev/null 2>&1 || STATE='{}'

NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
TRIAGED=0
while IFS="$(printf '\t')" read -r root_id formula_name formula_source hint_formula hint_target; do
    [ -n "$root_id" ] || continue

    if echo "$STATE" | jq -e --arg k "$root_id" 'has($k)' >/dev/null 2>&1; then
        continue
    fi

    set_rig_args "$root_id"
    FAILED_STEPS="$(gc bd list ${RIG_ARG1:+"$RIG_ARG1" "$RIG_ARG2"} \
        --metadata-field "gc.root_bead_id=$root_id" \
        --metadata-field "gc.outcome=fail" --all --json 2>/dev/null)" || FAILED_STEPS="[]"

    REASONS="$(printf '%s' "$FAILED_STEPS" \
        | jq -r '(. // [])[] | "- " + (.metadata."gc.step_id" // .id) + ": " + (.metadata."gc.failure_reason" // "(no gc.failure_reason recorded)")' \
        2>/dev/null)" || REASONS=""
    [ -n "$REASONS" ] || REASONS="(no failed member step found with gc.failure_reason; inspect $root_id directly)"

    hint_line=""
    if [ -n "$hint_formula" ]; then
        if [ -n "$hint_target" ]; then
            hint_line="Formula author's fast-path hint: $hint_formula -> $hint_target (optional; use your judgment, this may be stale or insufficient)."
        else
            hint_line="Formula author's fast-path hint: $hint_formula (no target declared; optional, use your judgment)."
        fi
    else
        hint_line="No fast-path hint declared -- decide the follow-up from scratch."
    fi

    TASK_TEXT="$(cat <<EOF
Triage failed workflow $root_id (formula: ${formula_name:-unknown})

Workflow root $root_id closed with gc.outcome=fail.
Formula: ${formula_name:-unknown}
Formula source: ${formula_source:-unknown}

Failed step(s) and recorded reason:
$REASONS

$hint_line

Read the failure in full (gc bd show $root_id --json and the failed step
beads above; follow any report_path/artifact metadata they carry) and decide
what, if anything, to do next. If a follow-up fix attempt is warranted and
none of the existing formulas in formulas/ already cover it, author a new
formula (see formulas/*.formula.toml for the v2 contract and
formulas/launch/launch-*.sh for the launch-wrapper convention this city
uses), then launch it via scripts/gc-sling-formula.sh. If an existing
formula already covers it (including the hint above, if present and still
appropriate), launch that one instead. If no follow-up is warranted, say so
and leave it at that.
EOF
    )"

    if printf '%s' "$TASK_TEXT" | gc sling mayor --stdin --nudge >&2; then
        STATE="$(echo "$STATE" | jq --arg k "$root_id" --arg now "$NOW" '.[$k] = $now')"
        TRIAGED=$((TRIAGED + 1))
        echo "on-fail-followup: triaged $root_id (formula: ${formula_name:-unknown}) to mayor"
    else
        echo "on-fail-followup: failed to route triage task for $root_id; will retry next run" >&2
    fi
done <<EOF
$MATCHES
EOF

# Prune entries older than RETENTION so the state file stays bounded.
RETENTION_S="$(duration_to_seconds "$RETENTION")"
STATE="$(echo "$STATE" | jq --argjson keep "$RETENTION_S" \
    'with_entries(select((now - (.value | fromdateiso8601)) <= $keep))')" || true

# Atomic write: temp file in the same dir, then rename.
TMP="$(mktemp "$STATE_DIR/.on-fail-followup-state.XXXXXX")"
printf '%s\n' "$STATE" > "$TMP"
mv -f "$TMP" "$STATE_FILE"

if [ "$TRIAGED" -gt 0 ]; then
    echo "on-fail-followup: triaged $TRIAGED failed workflow(s) to mayor"
fi
