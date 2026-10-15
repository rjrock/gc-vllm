# vLLM investigations

This local schema-2 pack supplies the rig-scoped template
`vllm/investigation.investigator`. The city imports it only for the vllm rig.
It inherits the city's provider, supports one controller-managed
worker at a time, and starts when routed work is available.

The investigator handles engine crashes, model compatibility, attention and
KV-cache layouts, GPU kernels, distributed execution, correctness, profiling,
and performance. It produces reproducible diagnosis and a root-cause report.
Tasks that say "Fix" or otherwise request implementation also produce a
targeted patch and validation, committed on an isolated worktree branch for
human review. The agent does not merge, push, or publish.

After changing the pack or city imports, reload the live controller:

```bash
gc reload --soft
```

To create and dispatch an investigation from the city directory:

```bash
gc bd create --rig vllm "Fix MiniMax-M2.5 engine crash: paged_attention_common dense K/V plane assertion with VLLM_ROCM_SHUFFLE_KV_CACHE_LAYOUT"
# Use the bead ID returned above:
gc sling vllm/investigation.investigator <bead-id>
```

Include the failing environment/container, reproduction command, versions,
and existing traces in the bead description when available. Do not attach
an implementation formula to a diagnosis-only task.

For an interactive investigation:

```bash
gc session new vllm/investigation.investigator
```

Reports and experiment artifacts default to
`$GC_CITY/investigations/vllm/<bead-id-or-task-slug>/`; routed tasks also
record their findings and artifact paths in bead notes.

To check the configuration and rendered prompt:

```bash
gc config show --validate
gc prime vllm/investigation.investigator --strict
gc lint packs/investigation
```
