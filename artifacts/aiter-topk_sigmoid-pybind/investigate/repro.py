import torch, aiter
t, e = 4, 16
k = 2
g = torch.randn(t, e, device="cuda", dtype=torch.float32)
w = torch.empty(t, k, device="cuda", dtype=torch.float32)
i = torch.empty(t, k, device="cuda", dtype=torch.int32)
aiter.topk_sigmoid(w, i, g)
print("OK", w, i)
