# 体の内側の、輪郭（暗い色）に囲まれていない透明な穴＝抜けたツヤを埋める。
# 輪郭に囲まれた隙間（粘液の糸のあいだ・しずくの輪・腕の輪の中）は本当の隙間なので残す。
# 使い方: python3 tools/fill_small_holes.py 入力.png 出力.png [最大の大きさ=200]
import sys
import numpy as np
from PIL import Image
from scipy import ndimage
from collections import Counter
src, dst = sys.argv[1], sys.argv[2]
mx = int(sys.argv[3]) if len(sys.argv) > 3 else 200
a = np.array(Image.open(src).convert('RGBA'))
H, W = a.shape[:2]
lab, k = ndimage.label(a[:, :, 3] == 0)
n = 0
for j in range(1, k + 1):
    m = lab == j
    sz = int(m.sum())
    ys, xs = np.where(m)
    if sz > mx or ys.min() == 0 or xs.min() == 0 or ys.max() == H - 1 or xs.max() == W - 1:
        continue
    ring = ndimage.binary_dilation(m, structure=np.ones((3, 3))) & ~m
    c = a[ring][:, :3].astype(int)
    lum = 0.3 * c[:, 0] + 0.59 * c[:, 1] + 0.11 * c[:, 2]
    if (lum < 70).mean() >= 0.3:
        continue
    cols = Counter(tuple(int(v) for v in x) for x in c)
    col = max(cols.most_common(3), key=lambda kv: sum(kv[0]))[0]
    a[m, :3] = col
    a[m, 3] = 255
    n += sz
Image.fromarray(a).save(dst)
print(dst, '埋めた画素', n)
