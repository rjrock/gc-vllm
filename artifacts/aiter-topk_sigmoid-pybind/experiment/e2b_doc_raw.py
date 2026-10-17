import torch, aiter, importlib
m = importlib.import_module("aiter.jit.module_moe_topk_ck")
print("DOC", repr(m.topk_sigmoid.__doc__))
for dt in (torch.float32,):
    g = torch.randn(4, 16, device="cuda", dtype=dt)
    w = torch.full((4, 2), -7.0, device="cuda", dtype=dt)
    i = torch.full((4, 2), -7, device="cuda", dtype=torch.int32)
    m.topk_sigmoid(w, i, g); torch.cuda.synchronize()
    print("RAW direct w", w.tolist(), "i", i.tolist())
    rw, ri = torch.topk(torch.sigmoid(g), 2, dim=-1)
    print("REF w", rw.tolist(), "i", ri.tolist())
    w2 = torch.full((4, 2), -7.0, device="cuda", dtype=dt); i2 = torch.full((4, 2), -7, device="cuda", dtype=torch.int32)
    torch.ops.aiter.topk_sigmoid(w2, i2, g); torch.cuda.synchronize()
    print("OPS w", w2.tolist(), "i", i2.tolist())
