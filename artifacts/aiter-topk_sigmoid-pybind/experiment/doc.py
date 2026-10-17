import aiter
from aiter.jit.core import get_module
print(repr(get_module("module_moe_topk_ck").topk_sigmoid.__doc__))
