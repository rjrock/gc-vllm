# Experiments ai-yfo: topk_sigmoid JIT-binding SyntaxError (editable aiter)

- Claimed bead: ai-yfo (root ai-e76). Producer bead: ai-bmn (closed, gc.outcome=pass, same
  gc.root_bead_id=ai-e76).
- aiter base commit: 2ae524697f8640dbb1305014458d4ac4df2928d5 (main tip). Worktree:
  /home/ryrock/dev/gc-worktrees/aiter/ai-yfo, branch experiment/ai-yfo (work_dir recorded
  on bead).
- CK submodule 3rdparty/composable_kernel: file contents copied (no .git) from
  /home/ryrock/dev/aiter-wt/ai-bmn (rev 96afae1d5).
- Image rjrock2/vllm-ci-ext:oct16 (unmodified). GPU index 1 (0% use, ~0.3GB VRAM at check;
  all 8 were idle). HIP_VISIBLE_DEVICES=1.
- Container name: ai-yfo. Launch:
  `docker run -d --name ai-yfo --entrypoint bash --device=/dev/kfd --device=/dev/dri --group-add video --security-opt seccomp=unconfined --ipc=host --shm-size=16g -e HIP_VISIBLE_DEVICES=1 -v /home/ryrock/dev/gc-worktrees/aiter/ai-yfo:/workspace/aiter:rw -v <experiment dir>:/artifacts:rw rjrock2/vllm-ci-ext:oct16 -c 'sleep infinity'`
- JIT cache: the worktree itself (aiter/jit, aiter/jit/build), fresh and cold for this
  bead; no shared cache.
- Extra context found before running (git history, not an experiment): ed5fc689b /
  0ba802e2d show moe_topk_ck_pybind.cu used to get torch via `moe_op.h`; 0ba802e2d
  replaced that with `<torch/all.h>` when making moe_op.h torch-free.

## Pre-registered hypotheses and predictions (written before any run)

- E0 (setup verification): After `pip uninstall amd-aiter` + `python setup.py develop` in
  the bind-mounted worktree, aiter.__file__ is under /workspace/aiter, aiter/install_mode
  contains `develop`, and no aiter_meta tree exists/is used. Prediction: all three hold.
- E1 (control, unmodified tree): H1-control. Calling aiter.topk_sigmoid via
  /artifacts/repro.py raises SyntaxError at aiter/jit/core.py check_args exec, with stub
  containing `at::Tensor`. Prediction: SyntaxError identical to investigation;
  `get_module("module_moe_topk_ck").topk_sigmoid.__doc__` contains `at::Tensor`.
- E2 (fix, H1): Replacing `#include <torch/all.h>` with `#include <torch/extension.h>` in
  csrc/pybind/moe_topk_ck_pybind.cu (after deleting the stale module .so/build dir) makes
  the docstring use `torch.Tensor` and repro.py prints OK. Prediction: docstring has
  `torch.Tensor`, no SyntaxError, in editable mode without reinstall.
- E3 (correctness): With the E2 fix, topk_sigmoid output matches reference
  (sigmoid(gating) then topk, k=2 and larger shapes). Prediction: weights allclose and
  index sets equal (ties unlikely with randn fp32).
- E4 (H3, include order): Placing `<torch/extension.h>` BEFORE `rocm_ops.hpp` also works.
  Prediction: also works (no ordering dependence).
- E5: run op_tests/test_topk_sigmoid.py if present in the worktree (it is untracked in the
  shared checkout, so likely absent here; will note).

## Records
(appended below as runs execute)

### E0 setup verification (run)
- Cmd: pip uninstall amd-aiter; rm leftover dist-packages aiter/aiter_meta/amd_aiter*;
  `cd /workspace/aiter && python setup.py develop` (e0_setup_develop.log, exit 0).
- Actual (e0_verify.log): aiter.__file__=/workspace/aiter/aiter/__init__.py;
  aiter/install_mode=`develop`; no /workspace/aiter/aiter_meta nor
  dist-packages/aiter_meta; AITER_META_DIR=AITER_ROOT_DIR=/workspace/aiter; pip: Editable
  project location /workspace/aiter. module_aiter_core built cold in 21s under the
  worktree.
- Verdict: SUPPORTS. The handoff's editable overwrite is genuinely in effect
  (independently reproduced).

### E1 control, unmodified tree (run)
- Cmd: `cd /tmp && python /artifacts/repro.py` (fp32 gating [4,16], k=2).
- Actual (e1_control_out.log, e1_control_doc.log): SyntaxError at aiter/jit/core.py:2296
  check_args exec: `def topk_sigmoid(topk_weights: at::Tensor, ...) -> None: pass`. Raw
  docstring: 'topk_sigmoid(topk_weights: at::Tensor, topk_indices: at::Tensor,
  gating_output: at::Tensor) -> None ...'. (Pybind decl: csrc/pybind/moe_topk_ck_pybind.cu
  + MOE_TOPK_CK_PYBIND in csrc/include/rocm_ops.hpp:1451.)
- Verdict: SUPPORTS H1-control. Failure reproduces in true editable mode, identical to the
  investigation.

### E2 fix: `#include <torch/all.h>` -> `#include <torch/extension.h>`
- At moe_topk_ck_pybind.cu:5 (e2_fix.diff). Run: delete aiter/jit/module_moe_topk_ck.so
  and aiter/jit/build/module_moe_topk_ck, rerun repro.py (e2_fix_out.log,
  e2b_doc_raw_out.log). No reinstall.
- Actual: module rebuilt (38.6s, picked up from the worktree directly, no reinstall).
  Docstring: 'topk_sigmoid(topk_weights: torch.Tensor, topk_indices: torch.Tensor,
  gating_output: torch.Tensor) -> None ...'. repro.py printed OK with no SyntaxError.
- Caveat on e2_fix_out.log: my doc.py there failed (ModuleNotFoundError) because it called
  get_module before the .so was built; that is my script's error, not the fix. e2b imports
  the module after build and shows the docstring.
- Verdict: SUPPORTS H1. The missing torch type caster (torch/all.h lacks it) causes
  at::Tensor in the docstring; extension.h fixes the binding.

### E3 correctness (run)
- Scripts e3_correct.py (fp32/bf16/fp16 outputs), e3b_correct.py (fp16/bf16 gating with
  fp32 weights, 4 shapes), e3c_diag.py; reference = torch.topk(torch.sigmoid(g.float())).
- Actual: fp32 gating produced no output (weights/indices left at the fill value -7) both
  through aiter.topk_sigmoid and torch.ops.aiter.topk_sigmoid (e3_correct_out.log,
  e2b_doc_raw_out.log). Reading csrc/py_itfs_ck/topk_sigmoid_kernels.cu + CK
  topk_softmax_api.cpp: the sigmoid path dispatches only fp16/bf16 input with fp32
  weights; fp32 input silently matches no branch (kernel limitation, unrelated to binding;
  I did not run CK to confirm the no-op, inferred from output untouched).
- fp16/bf16 inputs (e3b_correct_out.log): the op runs and 5/8 shape/dtype cases match
  exactly. 3/8 mismatch (fp16 128x128 k=8; bf16 32x64 k=4, 128x128 k=8 in the first run; a
  different subset varied in rerun/diag because of different RNG draws). e3c_diag_out.log:
  mismatching rows return a duplicated index (e.g. got [11,17,47,47] vs ref [11,17,10,47];
  got [..,38,38,38,38] vs ref [..,38,87,0,11]), where the duplicated experts have
  identical low-precision sigmoid values (ties in fp16/bf16). Weights are correct values
  for the selected indices; the max weight diff is 0 except rows with ties (0.04 for fp16
  128x128 k=8).
- E5: the existing untracked shared-checkout test (copied to test_topk_sigmoid.py here,
  not modified) gave 5 passed, 1 failed (test_topk_sigmoid[16-64-4-dtype1], bf16, the same
  tie-duplicate-index pattern) (e5_pytest_out.log).
- Verdict: PARTIALLY SUPPORTS. The binding now loads and the op executes and writes
  correct results for non-tied rows, so the fix is not merely silencing the error. But
  there is a separate, pre-existing-looking correctness issue: duplicated indices on tied
  low-precision scores, and fp32 gating being a silent no-op. Cause not isolated further;
  I did not test whether it also occurs in the previous (pre-0ba802e2d) code or on the
  stock wheel, so I cannot say it is a regression.

### E4 include order (H3)
- Placed `<torch/extension.h>` BEFORE `#include "rocm_ops.hpp"` (e4_order.diff), deleted
  .so/build, rebuilt.
- Actual (e4_order_out.log): built in 37.9s; e3b_correct.py ran without SyntaxError and
  produced the same results as E2 (ALL_OK False for the same tie reasons). The docstring
  was not printed in this run (my e2b script ran before the build and hit
  ModuleNotFoundError); the absence of SyntaxError in check_args is the evidence.
- Verdict: SUPPORTS (weakly) that order does not matter; inconclusive on the docstring
  text specifically.

## Summary / uncertainties
- The root cause in the handoff (torch/all.h lacks the pybind type caster -> `at::Tensor`
  in the generated stub -> SyntaxError in check_args) is confirmed by control + fix on the
  real editable install, cold JIT (the cache was cold in each build; I did not compare
  warm cache, since the fix requires deleting the .so anyway).
- The unmodified-worktree control was run before the edit in the same container/worktree
  (not a separate tree).
- Only GPU 1, one container, one image. Not tested: other torch versions, the stock wheel
  path, a core.py-side workaround (H2).
- Separate finding: kernel tie handling (duplicate indices) and fp32 no-op; the existing
  op test is flaky or failing in bf16 due to this, even with the include fix. Worth its
  own investigation before relying on that test as a gate.

## Recommended fix direction
- File: csrc/pybind/moe_topk_ck_pybind.cu line 5. Change: `#include <torch/all.h>` ->
  `#include <torch/extension.h>` (kept after `rocm_ops.hpp`; the reverse order also
  builds). Tested revision: base 2ae524697 + this one-line diff in worktree
  /home/ryrock/dev/gc-worktrees/aiter/ai-yfo (branch experiment/ai-yfo, uncommitted; diff
  at e2_fix.diff). Not applied to the shared checkout.
- Follow up separately: tie handling / fp32 input in topk_sigmoid kernel; and consider
  whether the regression test's bf16 case should use tie-free inputs.

## Artifacts
All under /home/ryrock/dev/gc-vllm/artifacts/aiter-topk_sigmoid-pybind/experiment/:
experiments.md, e0_setup_develop.log, e0_verify.log, e1_control_out.log,
e1_control_doc.log, e2_fix.diff, e2_fix_out.log, e2b_doc_raw_out.log, e3_correct_out.log,
e3b_correct_out.log, e3c_diag_out.log, e4_order.diff, e4_order_out.log, e5_pytest_out.log,
plus scripts (repro.py, doc.py, e2b_doc_raw.py, e3*.py, test_topk_sigmoid.py).
