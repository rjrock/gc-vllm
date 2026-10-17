import torch, aiter
torch.manual_seed(0)
for dt, (t,e,k) in ((torch.bfloat16,(16,64,4)),(torch.bfloat16,(32,64,4)),(torch.float16,(128,128,8))):
    g = torch.randn(t, e, device="cuda", dtype=dt)
    w = torch.zeros((t, k), device="cuda", dtype=torch.float32)
    i = torch.zeros((t, k), device="cuda", dtype=torch.int32)
    aiter.topk_sigmoid(w, i, g); torch.cuda.synchronize()
    rw, ri = torch.topk(torch.sigmoid(g.float()), k, dim=-1)
    bad = (i.sort(-1).values != ri.int().sort(-1).values).any(-1)
    print(dt,(t,e,k),"bad rows",bad.sum().item(),"/",t, "max w diff", (w.sort(-1).values-rw.sort(-1).values).abs().max().item())
    r = bad.nonzero()[0].item() if bad.any() else 0
    print(" row",r,"got i",i[r].tolist(),"w",[round(x,4) for x in w[r].tolist()])
    print("     ref i",ri[r].tolist(),"w",[round(x,4) for x in rw[r].tolist()])
    print("     ref vals at got idx", [round(torch.sigmoid(g[r,j].float()).item(),4) for j in i[r].tolist()] if (i[r]>=0).all() and (i[r]<e).all() else "idx out of range")
    print(" w==0 count", (w==0).sum().item(), "i==0 count", (i==0).sum().item())
