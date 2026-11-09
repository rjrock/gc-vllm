---
name: author-formula
description:
  Author a self-contained Gas City formula (formulas/*.formula.toml plus its launch
  script) for investigate -> experiment -> implement style workflows in this city. Use
  when asked to create or revise a formula.
---

### Why self-containment matters

Every step of a formula runs in a fresh agent that sees only that step's description and
the formula vars. It cannot see the conversation that produced the formula, earlier beads,
or any artifacts except those the formula tells it to read. Anything left implicit is
guessed.

### Reference

Model the formula on `formulas/flint-rocm-attention-fix.formula.toml` and its launcher
`formulas/launch/launch-flint-rocm-attention-fix.sh`.

### Instructions

1. **Top-level `description`**: what is broken, why it matters, and what done looks like.
2. **Inline the evidence** instead of pointing at it: verbatim tracebacks, file:line,
   commit SHAs, exact reproduction commands, image tags, model paths. A path to a log may
   be cited as a secondary pointer only.
3. **Label prior findings as unverified leads** (a `known_context` var) and tell each step
   to re-derive them fresh. Date-stamp any state that was true at authoring time and say
   "re-verify".
4. **External references** (bead IDs, sibling repos, logs outside this repo): say what
   they are and why they matter, and say what to do if they are missing.
5. **Vars**: run-specific values must be vars with defaults, not hard-coded in steps.
   Follow the Flint set: `artifact_dir` (required, absolute), `formula_id`, `image`,
   `repo_path`, `base_ref`, `question`, `constraints`, `known_context`, `gpu_rules`, and
   `on_fail_followup_formula`/`on_fail_followup_target` where a follow-up is already
   known.
6. **Constraints var**: state scope, explicit out-of-scope items, the primary end-to-end
   success criterion, and what may not be done (e.g. no `pip install` over the editable
   vllm).
7. **Nested vars**: `{{var}}` inside another var's default may not be expanded. Where a
   block uses `{{image}}` and is itself interpolated, restate the value next to it as the
   Flint formula does (`IMAGE={{image}} -- resolve <IMAGE> ...`), or avoid nesting.
8. **Steps**: a `body` scope step plus `investigate` -> `experiment` -> `implement` (or
   the subset needed). Each non-body step sets `gc.run_target`, `gc.scope_ref = "body"`,
   `gc.scope_role = "member"`, `gc.on_fail = "abort_scope"`, and `needs`.
9. **Handoffs**: each step writes its report to a named file under
   `{{artifact_dir}}/<step>/`, appends a summary to its claimed bead, sets a
   `*.report_path` metadata key and `gc.outcome=pass`, and closes only its own step. The
   next step must read that file and verify the producer bead shares its `gc.root_bead_id`
   and has `gc.outcome=pass`.
10. **Failure paths**: every step says what to do when blocked (`gc.outcome=fail`,
    `gc.failure_reason`, close only this step) and when its hypothesis is refuted (still
    `pass`, with the evidence).
11. **Worktrees**: use
    `~/dev/cities/gc-worktrees/<rig>/{{formula_id}}/<step>/<claimed-bead-id>` on branch
    `{{formula_id}}/<step>/<claimed-bead-id>`. Never edit the shared rig checkout.
12. **Launcher**: add `formulas/launch/launch-<formula>.sh` that only execs
    `scripts/gc-sling-formula.sh <target> <formula> "$@"`. Copy the Flint launcher.
13. **Self-review before finishing**: re-read the formula as the `experiment` agent would.
    List everything you would have to guess or look up elsewhere, and fix those gaps in
    the formula.
