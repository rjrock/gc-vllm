# Investigation ai-bmn: topk_sigmoid JIT-binding SyntaxError (editable aiter)

- Bead: ai-bmn (root ai-e76). Date: 2026-10-16.
- aiter commit: 2ae524697f8640dbb1305014458d4ac4df2928d5 (main tip; rig path
  /home/ryrock/dev/aiter verified via `gc rig list --json`).
- Worktree: /home/ryrock/dev/aiter-wt/ai-bmn, branch investigate/ai-bmn (no source changes
  made; CK submodule 96afae1d5 fetched into it).

## Environment
- Image rjrock2/vllm-ci-ext:oct16 (local, unmodified). torch 2.13.0+git733fca1, python
  3.12.13, ROCm 7.2.3, stock wheel amd-aiter 0.1.25.
- GPU: index 0 (MI300X, 0% use, ~0.3GB VRAM at launch). HIP_VISIBLE_DEVICES=0. Env from
  image: AITER_ROCM_ARCH=gfx942;gfx950.
- Container `ai-bmn` (removed after use):
  `docker run -d --name ai-bmn --entrypoint bash --device=/dev/kfd --device=/dev/dri --group-add video --security-opt seccomp=unconfined --ipc=host --shm-size=16g -e HIP_VISIBLE_DEVICES=0 -v /home/ryrock/dev/aiter-wt/ai-bmn:/workspace/aiter:rw -v <artifacts>/investigate:/artifacts:rw rjrock2/vllm-ci-ext:oct16 -c 'sleep infinity'`
- JIT cache: worktree-local (/workspace/aiter/aiter/jit, fresh/cold; module_aiter_core and
  module_moe_topk_ck both built from scratch in-run, 20s and 37s). I did not run a
  separate warm-cache comparison. Not a separate per-bead cache dir beyond the fresh
  worktree.

## Editable overwrite steps
1. `pip uninstall -y amd-aiter`; `rm -rf` of leftover dist-packages/aiter, aiter_meta,
   amd_aiter* (confirmed absent afterward).
2. In /workspace/aiter: `python setup.py develop` (log: setup_develop.log; ended "Finished
   processing dependencies for amd-aiter==0.1.0"). Note: git inside container warned "not
   a git repository" (worktree .git points to host path); setup still succeeded.
3. Verification:
   - (a) `aiter.__file__` = /workspace/aiter/aiter/__init__.py
   - (b) /workspace/aiter/aiter/install_mode = `develop`
   - (c) no /workspace/aiter/aiter_meta and no dist-packages/aiter_meta;
     `AITER_META_DIR == AITER_ROOT_DIR == /workspace/aiter`; pip shows "Editable project
     location: /workspace/aiter".

## Reproduction (valid, editable mode)
`docker exec ai-bmn bash -c 'cd /tmp && python /artifacts/repro.py'` (repro.py: allocate
fp32 gating [4,16] cuda, weights [4,2], indices int32 [4,2], call aiter.topk_sigmoid).
Output: repro_out.log. Result:
```
File ".../aiter/jit/core.py", line 2296, in check_args  exec(...)
  def topk_sigmoid(topk_weights: at::Tensor, topk_indices: at::Tensor, gating_output: at::Tensor) -> None: pass
SyntaxError: invalid syntax
```
Raw pybind docstring (docstring_and_headers.log):
`'topk_sigmoid(topk_weights: at::Tensor, topk_indices: at::Tensor, gating_output: at::Tensor) -> None\n\nApply topk sigmoid to the gating outputs.\n'`

## Fresh findings
- aiter/jit/core.py:2296-2299 exec's `def {doc_str}: pass`; the doc_str rewrites at
  core.py:2253-2273 handle list/tuple/Optional/enums/aiter_tensor_t but nothing maps
  `at::Tensor`.
- csrc/pybind/moe_topk_ck_pybind.cu:5 includes `<torch/all.h>`; declares
  `aiter::topk_sigmoid(torch::Tensor...)` (lines 8-11), bound via MOE_TOPK_CK_PYBIND
  (csrc/include/rocm_ops.hpp:1451-1457).
- Torch's `type_caster<at::Tensor>` (torch/csrc/utils/pybind.h:38 in the image's torch) is
  reached via `<torch/extension.h>` -> `<torch/python.h>`, not via `<torch/all.h>`
  (extension.h:6 includes all.h, :10 includes python.h). Without the caster, pybind11
  renders the C++ name `at::Tensor` in signatures. (Inferred from header structure plus
  the observed docstring; header was not directly diffed for a compile.)
- Only moe_topk_ck_pybind.cu in csrc/pybind/*.cu includes torch/all.h.
  mha_v4_fwd_pybind.cu doesn't include extension.h itself; its comment (lines 5-9) claims
  the pattern and says "see moe_topk_ck_pybind.cu", while torch/mha_v4_fwd.h:5 includes
  `<torch/extension.h>`. So the supplied claim that the sibling TU "pulls it in" is true
  only transitively; and the comment implies moe_topk_ck_pybind.cu previously used
  extension.h (history not checked).

## Hypotheses
1. (High, ~90%) Missing torch pybind type caster because of `<torch/all.h>` => docstring
   `at::Tensor` => SyntaxError. Evidence: observed docstring, include, header structure.
   Not yet shown: that the swap fixes it (no fix applied by design).
2. (Low, ~7%) Fix belongs in core.py instead (map `at::Tensor`->`torch.Tensor` in doc_str
   rewriting). Would work as workaround but hides the cause and the real call path
   (torch_guard) may also depend on caster for runtime conversion; though the op, being
   torch::Tensor args, would fail at call time without the caster anyway.
3. (Low) Interaction with rocm_ops.hpp ordering/ABI-family split (mha_v4 comment mentions
   module_aiter_core ABI families); extension.h before/after rocm_ops.hpp might matter.
   Untested. Missing evidence: result of the include swap; git history of that file.

## Experiment plan (for experimenter; use own worktree, same container recipe above)
- H1: change line 5 of csrc/pybind/moe_topk_ck_pybind.cu to
  `#include <torch/extension.h>`. Prediction: docstring shows `torch.Tensor`, repro.py
  prints OK, no SyntaxError. Control: unchanged tree fails as in repro_out.log. Rebuild
  requires deleting aiter/jit/module_moe_topk_ck.so and aiter/jit/build/module_moe_topk_ck
  (cold build ~37s). Commands: edit;
  `rm -rf aiter/jit/module_moe_topk_ck.so aiter/jit/build/module_moe_topk_ck`;
  `python /artifacts/repro.py`; print
  `get_module("module_moe_topk_ck").topk_sigmoid.__doc__`.
- Also check correctness of output vs torch (sigmoid then topk) and
  `python op_tests/test_topk_sigmoid.py` (untracked file exists in shared checkout; not
  read). Try include placed before and after rocm_ops.hpp to test H3. Verify editable
  checks (a)-(c) again.
- Artifacts:
  investigate/{setup_develop.log,repro.py,repro_out.log,docstring_and_headers.log}.
