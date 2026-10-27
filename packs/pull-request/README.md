# PR drafting from VIP artifacts

This local schema-2 pack supplies the rig-scoped template
`<rig>/pull-request.pull-requester`. The city imports it per rig (currently
`vllm` and `aiter`); each import renders its own `{{ .RigName }}`-scoped
drafter against that rig's repository. It inherits the city provider,
supports one controller-managed worker at a time, and starts when work is
routed.

The drafter reads a completed implementation bead and follows its producer
chain back through the experiment and investigation beads, verifying each
closed `gc.outcome=pass` on the same workflow root. It loads
`templates/vllm_pull_request_template.md` from the city root and fills in
Overview/Claims/Validation/Details from the investigation, experiment, and
implementation reports (preferring reproducer logs for validation evidence
when available), writing the minimal draft that still lets a maintainer
judge the change on its merits rather than reproducing the VIP reports'
full narrative. It inspects the implementer's worktree read-only to
confirm the branch and commit exist; it never edits, commits, or creates a
worktree of its own.

The agent only drafts. It never runs `git push` or `gh pr create`; it
writes the exact push/open-PR commands for a human to run, alongside the
draft, so publication stays an explicit human (or separately authorized
publish step) action. See the upstream `publish` formula
(`gc.publisher`, gated `push`/`open_pr` vars) for GasCity's existing
pattern for an explicitly-authorized follow-up publish step, if one is
wanted later; it is not wired up here.

After loading the new configuration:

```bash
gc reload --soft
```

For a direct task, create a bead referencing a completed `implement` step
(its bead ID or report path) in the target rig and dispatch it:

```bash
gc bd --rig vllm create "Draft PR for <bead-id>'s fix" \
  --set-metadata implementation.report_path=<path>
gc sling vllm/pull-request.pull-requester <bead-id> --no-formula
```

Inside a formula, add it as a step with `needs = ["implement"]` and
`metadata = { "gc.run_target" = "vllm/pull-request.pull-requester",
"gc.scope_ref" = "body", "gc.scope_role" = "member", "gc.on_fail" =
"abort_scope" }`, then retarget the `body` scope step's `needs` to
`["pull-request"]`.

Drafts go under `<artifact_dir>/pull_request/` (a sibling of `investigate/`,
`experiment/`, `implement/`, and `reproducer/`) inside a formula run, or
`~/dev/cities/runs/pull-requests/<rig>/<bead-id>/pull_request/` for a direct
task with no shared artifact directory. Each run writes `pr_description.md`
(the filled-in template, ready to paste into a GitHub PR body) and
`pull_request.md` (provenance, worktree/branch/commit, and the exact
push/PR commands for a human to run).

To validate the definition and rendered prompt:

```bash
gc config show --validate
gc prime <rig>/pull-request.pull-requester --strict
gc lint packs/pull-request
```
