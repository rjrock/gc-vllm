# Rig implementation from experiment results

This local schema-2 pack supplies the rig-scoped template
`<rig>/implementation.implementer`. The city imports it per rig (currently
`vllm` and `aiter`); each import renders its own `{{ .RigName }}`-scoped
implementer against that rig's repository. It inherits the city provider,
supports one controller-managed worker at a time, and starts when work is
routed.

The implementer reads the experimenter's report and evidence, chooses the
best-supported fix, and creates a dedicated rig git worktree on a new branch.
It implements the fix, adds focused regression coverage, runs relevant checks,
and leaves the worktree, complete patch, and implementation report for review.

The source experiment bead and report are inputs. Existing uncommitted
changes in the rig repository must be reviewed and ported deliberately into
the new worktree. Reports distinguish proxy validation from validation on
the actual model.

After loading the new configuration:

```bash
gc reload --soft
```

Use the `implement-experiment` formula to consume a completed experiment bead.
For example, for an existing vllm-rig experiment, run from the city directory
(substitute `aiter` or another registered rig name as needed):

```bash
scripts/gc-sling-formula.sh vllm/implementation.implementer implement-experiment \
  --var experiment_bead=vl-a1g \
  --var base_ref=main
```

For a direct task, create a bead in the target rig and include the experiment
bead ID, report path, implementation scope, base ref, and resource constraints
in its description, then dispatch it with
`gc sling <rig>/implementation.implementer <bead-id> --no-formula`.

Worktrees default to
`~/dev/cities/gc-worktrees/<rig>/<implementation-step-bead-id>/` on branch
`implement/<implementation-step-bead-id>`. Reports and patches use the
supplied artifact directory, or default to
`~/dev/cities/gc-artifacts/implementations/<rig>/<bead-id>/` for direct
tasks. The agent leaves changes in its worktree for review. Publication
requires explicit task scope.

Before editing, the implementer verifies the worktree's repository, path, and
task branch, and saves its absolute path on the claimed bead as both `work_dir`
and `implementation.worktree_path`. gc uses `work_dir` to start resumed
sessions in the saved worktree. Restarts recover and verify that worktree
without discarding existing changes. Every edit, dependency setup, and test
runs from the verified worktree.

To validate the definition and rendered prompt:

```bash
gc config show --validate
gc prime <rig>/implementation.implementer --strict
gc lint packs/implementation
```
