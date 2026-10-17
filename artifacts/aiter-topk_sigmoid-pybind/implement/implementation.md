# Implementation ai-sd4: topk_sigmoid pybind SyntaxError

## Provenance
- Root ai-e76. Investigation ai-bmn (closed, gc.outcome=pass, same root):
  /home/ryrock/dev/gc-vllm/artifacts/aiter-topk_sigmoid-pybind/investigate/investigation.md
- Experiment ai-yfo (closed, gc.outcome=pass, same root): .../experiment/experiments.md
- Experiments were tested results (cold JIT, true editable, GPU 1); I re-reproduced them
  independently.

## Fix
- csrc/pybind/moe_topk_ck_pybind.cu: `#include <torch/all.h>` ->
  `#include <torch/extension.h>`. torch/all.h lacks the pybind11 at::Tensor<->torch.Tensor
  caster, so the docstring rendered `at::Tensor` and aiter/jit/core.py check_args exec()
  raised SyntaxError. aiter/jit/core.py untouched.
- Other ops: only this TU changes; extension.h is a superset of all.h and is already used
  by sibling pybind TUs (e.g. mha_v4_fwd_pybind.cu). No other op's binding is affected.
- Alternatives rejected: relaxing core.py's validation (masks bad docstrings for all ops;
  task forbids).
- Test: new op_tests/test_topk_sigmoid.py (the experimenter's untracked test, adapted).
  Experiment showed bf16 case failing even with the fix because tied low-precision scores
  yield a different, equally valid expert order (and in the experiment, duplicate ids). I
  changed the assertions to compare gathered scores plus a no-duplicate-ids check instead
  of exact id equality; weights still compared to reference.

## Repository / commits
- Repo /home/ryrock/dev/aiter (shared checkout untouched; dirty state: M .gitignore, ??
  .beads/ .gc/ op_tests/test_topk_sigmoid.py; main at 2ae524697).
- Worktree /home/ryrock/dev/gc-worktrees/aiter/ai-sd4, branch implement/ai-sd4, base
  2ae524697f8640dbb1305014458d4ac4df2928d5 (same as experiment's tested base), fix commit
  af2843619ccddc3d04b07883a1ee13871fb7e27b.
- CK submodule contents copied from /home/ryrock/dev/aiter-wt/ai-bmn (rev 96afae1d5), not
  committed.

## Validation

Container ai-sd4, image rjrock2/vllm-ci-ext:oct16 unmodified, GPU 2 (0% use),
HIP_VISIBLE_DEVICES=2, worktree mounted rw.

1. Editable overwrite: pip uninstall amd-aiter; rm site-packages
   aiter/aiter_meta/amd_aiter*; `cd /workspace/aiter && python setup.py develop`
   (b0_setup_develop.log, exit 0). b0_verify.log:
   aiter.__file__=/workspace/aiter/aiter/__init__.py, install_mode=develop, no aiter_meta,
   pip editable location /workspace/aiter.
2. Baseline (before fix, cold JIT): repro.py -> SyntaxError `topk_weights: at::Tensor` at
   core.py:2296 (b1_baseline_repro.log).
3. After fix (stale .so/build removed, rebuilt 38s, no reinstall): repro.py ran without
   error (f1_fix_repro.log).
4. Regression test: before test adjustment 5 pass / 1 fail (bf16 16x64 k=4, ties)
   (f2_pytest_new.log); after adjustment 6/6 pass, 3 consecutive runs
   (f3_pytest_run{1,2,3}.log). Reference = torch.sigmoid + topk.
5. Existing coverage: op_tests/test_moeTopkSoftmax.py ran to completion
   (f4_existing_topk.log; it is a benchmark script, not the topk_sigmoid op).
   test_moe_topk_gating.py via pytest collects 0 items (script-style).
6. Lint: black 26.3.0 and ruff 0.15.7 pass on op_tests/test_topk_sigmoid.py (f5_lint.log).
   git diff --cached --check clean. clang-format (host version, not 18) warns on the
   untouched PYBIND11_MODULE line only (pre-existing); my one-line include change is not
   flagged.

## Limitations
- Only MI300X (gfx942), one GPU, one image/torch version. Not tested on gfx950 or other
  torch versions; stock-wheel path not tested.
- Proxy: new regression test only; no broader topk suite assertions run (existing topk
  scripts are benchmarks).
- Not fixed (separate issues from the experiment): fp32 gating input is a silent no-op in
  topk_sigmoid (outputs untouched; repro.py's fp32 call printed unwritten values, so "OK"
  there only means no SyntaxError); tied fp16/bf16 scores can yield duplicate expert ids.
  Test inputs/assertions are tie-tolerant but these kernel behaviors remain.
- Test relaxation means exact tie-order is not asserted.

## Artifacts
/home/ryrock/dev/gc-vllm/artifacts/aiter-topk_sigmoid-pybind/implement/:
implementation.md, implementation.patch (git diff --binary base fix), commit_hash.txt,
b0_*, b1_*, f1..f5 logs, repro.py.
