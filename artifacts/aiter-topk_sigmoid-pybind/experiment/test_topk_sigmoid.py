# SPDX-License-Identifier: MIT
# Copyright (C) 2025-2026, Advanced Micro Devices, Inc. All rights reserved.

"""Regression test for aiter.topk_sigmoid (module_moe_topk_ck pybind op).

Its pybind docstring used to render the C++ type `at::Tensor` instead of
`torch.Tensor` (the TU lacked torch/extension.h), so aiter/jit/core.py's
check_args raised SyntaxError on the first call -- the op could never load.
test_moe_topk_gating.py's sigmoid section benchmarks topk_gating, not this
op, so it never caught the regression.
"""

import pytest
import torch

from aiter.ops.moe_op import topk_sigmoid

torch.set_default_device("cuda")

_ATOL = {torch.float16: 2e-2, torch.bfloat16: 2e-2}


def _ref_sigmoid(gating_output, topk):
    scores = torch.sigmoid(gating_output.float())
    topk_weights, topk_ids = scores.topk(k=topk, dim=-1, largest=True, sorted=True)
    return topk_weights, topk_ids.to(torch.int32)


@pytest.mark.parametrize("dtype", [torch.float16, torch.bfloat16])
@pytest.mark.parametrize(
    "num_experts, num_tokens, topk", [(8, 4, 2), (16, 64, 4), (32, 33, 1)]
)
def test_topk_sigmoid(num_experts, num_tokens, topk, dtype):
    torch.manual_seed(0)
    gating_output = torch.randn(num_tokens, num_experts, dtype=dtype)
    topk_weights = torch.zeros((num_tokens, topk), dtype=torch.float32)
    topk_ids = torch.zeros((num_tokens, topk), dtype=torch.int32)

    topk_sigmoid(topk_weights, topk_ids, gating_output)
    ref_weights, ref_ids = _ref_sigmoid(gating_output, topk)

    assert torch.equal(topk_ids, ref_ids)
    torch.testing.assert_close(topk_weights, ref_weights, atol=_ATOL[dtype], rtol=0)
