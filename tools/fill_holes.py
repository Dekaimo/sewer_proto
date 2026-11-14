# 内側の透明な穴のうち、raw では背景色でない所（抜けたツヤ・模様）を raw の色で埋める。
# 使い方: python3 tools/fill_holes.py 入力.png raw.png 出力.png
import sys
import numpy as np
from PIL import Image
from scipy import ndimage
from collections import Counter
src, rawp, outp = sys.argv[1:4]
a = np.array(Image.open(src).convert('RGBA'))
raw = np.array(Image.open(rawp).convert('RGB'))
edge = np.concatenate([raw[0], raw[-1], raw[:, 0], raw[:, -1]])
bg = Counter(map(tuple, edge)).most_common(1)[0][0]
t = a[:, :, 3] == 0
lab, k = ndimage.label(t)
filled = 0
for j in range(1, k + 1):
    m = lab == j
    ys, xs = np.where(m)
    if ys.min() == 0 or xs.min() == 0 or ys.max() == 255 or xs.max() == 255:
        continue
    nb = np.abs(raw[m].astype(int) - np.array(bg)).sum(1) > 12
    if nb.mean() > 0.5:  # 大半が背景色でない＝抜けすぎ
        # 穴の大半がツヤ・模様なら、穴全体を raw の色で埋める（白いツヤは背景と同じ色になるため）
        a[m, :3] = raw[m]
        a[m, 3] = 255
        filled += m.sum()
# 浮いた小さな破片を消す
mm = a[:, :, 3] > 0
lab2, k2 = ndimage.label(mm, structure=np.ones((3, 3)))
if k2:
    sz = ndimage.sum(mm, lab2, range(1, k2 + 1)); big = np.argmax(sz) + 1
    for j in range(1, k2 + 1):
        if j != big and sz[j - 1] < 12:
            a[lab2 == j] = 0
Image.fromarray(a).save(outp)
print(outp, '背景色', bg, '埋めた画素', int(filled))
