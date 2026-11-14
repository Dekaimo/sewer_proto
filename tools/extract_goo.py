"""青く塗り替えたワニ＋猫の絵に、ピンクの粘液を足す編集をかけた結果から、手前の粘液の層だけを色で切り出す。
使い方: python3 tools/extract_goo.py 編集前.png 編集後のフォルダ 出力.png
- 編集前との差があり、ピンク／黄色の画素と、その近くの暗い輪郭（猫の灰色は除く）を粘液とみなす
- 粘液の内側の抜け（白いハイライト）は、生成の元（raw_v1_00.png）の色で埋める。元が青（ワニ）なら本当の隙間なので埋めない
- 最後に色をワニの立ち絵に合わせる（palette_lock）
"""
import os
import subprocess
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

src, gen, out = sys.argv[1], sys.argv[2], sys.argv[3]
e = np.array(Image.open(os.path.join(gen, "v1_00.png")).convert("RGBA")).astype(int)
r = np.array(Image.open(os.path.join(gen, "raw_v1_00.png")).convert("RGBA")).astype(int)
c = np.array(Image.open(src).convert("RGBA")).astype(int)
R, G, B = e[..., 0], e[..., 1], e[..., 2]
op = e[..., 3] > 0
diff = np.abs(e - c).sum(-1) > 40
pink = op & (R > G + 30) & (R >= B) & (R > 90)
yel = op & (R > 150) & (G > 120) & (B < 140) & (G > B + 40)
core = (pink | yel) & diff
near = ndimage.binary_dilation(core, iterations=2)
lum = 0.3 * R + 0.59 * G + 0.11 * B
gray = (np.abs(R - B) < 20) & (np.abs(R - G) < 20) & (R > 40)
g = core | (op & diff & near & (lum < 90) & ~gray)
lab, n = ndimage.label(g, structure=np.ones((3, 3)))
sz = ndimage.sum(np.ones_like(lab), lab, range(1, n + 1))
g = np.isin(lab, [i + 1 for i, s in enumerate(sz) if s >= 10])
o = np.zeros(e.shape, np.uint8)
o[g] = e[g]
hole = ndimage.binary_fill_holes(g) & ~g
fill = hole & ~(r[..., 2] > r[..., 0] + 20)
o[fill] = r[fill]
o[fill, 3] = 255
tmp = out + ".tmp.png"
Image.fromarray(o).save(tmp)
subprocess.run([sys.executable, os.path.join(os.path.dirname(__file__), "palette_lock.py"), tmp, out], check=True, capture_output=True)
os.remove(tmp)
a = np.array(Image.open(out).convert("RGBA"))
left = ndimage.binary_fill_holes(a[..., 3] > 0) & ~(a[..., 3] > 0)
print("粘液", int(g.sum()), "px / 埋めたハイライト", int(fill.sum()), "px / 残った穴", int(left.sum()), "px")
