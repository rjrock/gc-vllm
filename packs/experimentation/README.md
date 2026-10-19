# Rig experiments

This local schema-2 pack supplies the rig-scoped template
`<rig>/experimentation.experimenter`. The city imports it per rig (currently
`vllm` and `aiter`); each import renders its own `{{ .RigName }}`-scoped
experimenter against that rig's repository. It inherits the city's provider,
supports one controller-managed worker at a time, and starts when routed
work is available.

For each experiment, the experimenter states a hypothesis and predicted
result, records the exact command and environment, runs the experiment,
records the actual result, and states whether the evidence supports or
contradicts the hypothesis (or is inconclusive). It prefers minimal
experiments and records predictions before execution.

After changing the pack or city imports, reload the live controller:

```bash
gc reload --soft
```

To create and dispatch an experiment from the city directory (example
against the `vllm` rig; substitute `aiter` or another registered rig name):

```bash
gc bd create --rig vllm "Test whether KV-cache layout changes reproduce the attention assertion"
# Use the bead ID returned above:
gc sling vllm/experimentation.experimenter <bead-id>
```

Include the question, hypothesis if known, environment, reproduction command,
and any resource or runtime limits in the bead description when available.

For an interactive experiment:

```bash
gc session new <rig>/experimentation.experimenter
```

Experiment records and raw output default to
`~/dev/cities/gc-artifacts/experiments/<rig>/<bead-id-or-task-slug>/`; routed
tasks also record their findings and artifact paths in bead notes.

To check the configuration and rendered prompt:

```bash
gc config show --validate
gc prime <rig>/experimentation.experimenter --strict
gc lint packs/experimentation
```
