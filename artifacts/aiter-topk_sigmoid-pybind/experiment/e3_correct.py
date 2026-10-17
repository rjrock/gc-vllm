import torch, aiter
torch.manual_seed(0)
for dt in (torch.float32, torch.bfloat16, torch.float16):
  for t, e, k in ((4,16,2),(32,64,4),(128,128,8)):
    g = torch.randn(t, e, device="cuda", dtype=dt)
    w = torch.full((t, k), -7.0, device="cuda", dtype=dt)
    i = torch.full((t, k), -7, device="cuda", dtype=torch.int32)
    aiter.topk_sigmoid(w, i, g); torch.cuda.synchronize()
    rw, ri = torch.topk(torch.sigmoid(g.float()), k, dim=-1)
    idx_ok = (i.sort(-1).values == ri.int().sort(-1).values).all().item()
    w_ok = torch.allclose(w.float().sort(-1).values, rw.sort(-1).values, atol=1e-2)
    print(dt, (t,e,k), "idx_ok", idx_ok, "w_ok", w_ok, "w[0]", w[0].tolist(), "ref", rw[0].tolist(), "i[0]", i[0].tolist(), "ri", ri[0].tolist())
