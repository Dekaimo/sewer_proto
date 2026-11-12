"""生成アニメのコマを立ち絵に合わせて整える（1コマずつ）。
1) 色の傾向（ピンク・黄色の色相/彩度/明るさ）を基準の絵に合わせる（palette_lock の色の転写）
2) 体の中の穴・浮いた暗い点の掃除と32色化（dot_cleanup）
3) 体から離れた小さな暗い粒（4画素以下）を消す
使い方: python3 tools/anim_fix.py 基準.png 出力フォルダ 入力1.png 入力2.png ...
"""
import os
import subprocess
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

sys.path.insert(0, os.path.dirname(__file__))
import palette_lock

args = sys.argv[1:]
nogray = "--nogray" in args   # 主人公が写っていないコマ：体の中の灰色のしみ（背景の色が混ざったもの）を周りの色で埋める
args = [x for x in args if x != "--nogray"]
ref, outdir, srcs = args[0], args[1], args[2:]
palette_lock.MASTER = ref
os.makedirs(outdir, exist_ok=True)
here = os.path.dirname(os.path.abspath(__file__))
for s in srcs:
    d = os.path.join(outdir, os.path.basename(s))
    palette_lock.lock(s, d)
    subprocess.run([sys.executable, "-W", "ignore", os.path.join(here, "dot_cleanup.py"), d, d, "32"], check=True, capture_output=True)
    a = np.array(Image.open(d).convert("RGBA")).astype(int)
    op = a[..., 3] > 0
    if nogray:
        mx = a[..., :3].max(-1)
        mn = a[..., :3].min(-1)
        gray = op & ((mx - mn) < 0.2 * np.maximum(mx, 1)) & (mx > 60) & (mx < 200)
        good = op & ~gray
        for _ in range(12):
            if not gray.any():
                break
            ys, xs = np.nonzero(gray)
            fixed = []
            for y, x in zip(ys, xs):
                y0, y1, x0, x1 = max(y - 1, 0), min(y + 2, a.shape[0]), max(x - 1, 0), min(x + 2, a.shape[1])
                nb = [tuple(a[yy, xx]) for yy in range(y0, y1) for xx in range(x0, x1) if good[yy, xx]]
                if len(nb) >= 2:
                    a[y, x] = max(set(nb), key=nb.count)
                    fixed.append((y, x))
            for y, x in fixed:
                gray[y, x] = False
                good[y, x] = True
    lum = 0.30 * a[..., 0] + 0.59 * a[..., 1] + 0.11 * a[..., 2]
    lb, n = ndimage.label(op, structure=np.ones((3, 3)))
    if n:
        sizes = ndimage.sum(op, lb, range(1, n + 1))
        means = ndimage.mean(lum, lb, range(1, n + 1))
        for i, (sz, m) in enumerate(zip(sizes, means)):
            if sz <= 4 and m < 110:
                a[lb == i + 1] = 0
    Image.fromarray(a.astype(np.uint8), "RGBA").save(d)
    print(d)
