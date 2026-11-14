# のけぞりで暗く描かれた頭のピンクだけを、普段の頭の明るさに合わせて持ち上げる（形・描き込みはそのまま）。
# 使い方: python3 tools/head_bright.py 入力.png 出力.png x0 y0 x1 y1 [目標の明るさ=0.837]
#   箱の下端12画素はなだらかに効きを弱め、首のつなぎ目に段差を作らない。
import sys, colorsys
import numpy as np
from PIL import Image
src, dst = sys.argv[1], sys.argv[2]
x0, y0, x1, y1 = map(int, sys.argv[3:7])
target = float(sys.argv[7]) if len(sys.argv) > 7 else 0.837
a = np.array(Image.open(src).convert('RGBA'))
def pinkmask(r):
    R, G, B = r[..., 0].astype(int), r[..., 1].astype(int), r[..., 2].astype(int)
    return (r[..., 3] > 0) & (R > G + 30) & (R >= B)
reg = a[y0:y1, x0:x1]
pm = pinkmask(reg)
vs = [colorsys.rgb_to_hsv(*(p[:3] / 255))[2] for p in reg[pm]]
cur = float(np.mean(vs)) if vs else target
gain = target / cur if cur > 0 else 1.0
n = 0
for yy in range(y0, y1):
    w = 1.0 if yy < y1 - 12 else max(0.0, (y1 - yy) / 12)
    for xx in range(x0, x1):
        p = a[yy, xx]
        if p[3] == 0: continue
        R, G, B = int(p[0]), int(p[1]), int(p[2])
        if not (R > G + 30 and R >= B): continue
        h, s, v = colorsys.rgb_to_hsv(R / 255, G / 255, B / 255)
        if v < 0.25: continue   # 輪郭は触らない
        v2 = min(1.0, v * (1 + (gain - 1) * w))
        r2, g2, b2 = colorsys.hsv_to_rgb(h, s, v2)
        a[yy, xx, :3] = [round(r2 * 255), round(g2 * 255), round(b2 * 255)]; n += 1
Image.fromarray(a).save(dst)
print(dst, f'頭の明るさ {cur:.3f} -> 目標 {target:.3f}（{n}画素）')
