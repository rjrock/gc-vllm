import torch, aiter
torch.manual_seed(0)
allok = True
for dt in (torch.float16, torch.bfloat16):
  for t, e, k in ((4,16,2),(32,64,4),(128,128,8),(33,32,1)):
    g = torch.randn(t, e, device="cuda", dtype=dt)
    w = torch.full((t, k), -7.0, device="cuda", dtype=torch.float32)
    i = torch.full((t, k), -7, device="cuda", dtype=torch.int32)
    aiter.topk_sigmoid(w, i, g); torch.cuda.synchronize()
    rw, ri = torch.topk(torch.sigmoid(g.float()), k, dim=-1)
    idx_ok = (i.sort(-1).values == ri.int().sort(-1).values).all().item()
    w_ok = torch.allclose(w.sort(-1).values, rw.sort(-1).values, atol=2e-2)
    allok &= idx_ok and w_ok
    print(dt, (t,e,k), "idx_ok", idx_ok, "w_ok", w_ok)
print("ALL_OK", allok)
