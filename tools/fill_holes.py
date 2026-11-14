# 生成した絵の後始末：
#  1) 外側に付いた背景色っぽい灰色のふち・浮いた細かい点を消す
#  2) 内側の透明な穴のうち、raw で背景色でない所（抜けたツヤ・模様）を raw の色で埋める
#     （背景色＝raw の外側の透明部分によく出る色。白いツヤ・灰色の背景どちらにも対応）
# 使い方: python3 tools/fill_holes.py 入力.png raw.png 出力.png
import sys
import numpy as np
from PIL import Image
from scipy import ndimage
from collections import Counter

src, rawp, outp = sys.argv[1:4]
a = np.array(Image.open(src).convert('RGBA'))
raw = np.array(Image.open(rawp).convert('RGB')).astype(int)

def exterior(alpha0):
    lab, k = ndimage.label(alpha0)
    edge = set(lab[0]) | set(lab[-1]) | set(lab[:, 0]) | set(lab[:, -1])
    edge.discard(0)
    return np.isin(lab, list(edge)), lab

t = a[:, :, 3] == 0
ext, _ = exterior(t)
bgs = [np.array(c) for c, _ in Counter(map(tuple, raw[ext])).most_common(6)]
def is_bg(px):
    d = np.min([np.abs(px - c).sum(-1) for c in bgs], axis=0)
    return d <= 8

# 1) 灰色のふちを外側から削る
r, g, b = [a[:, :, i].astype(int) for i in range(3)]
mx = np.maximum(np.maximum(r, g), b); mn = np.minimum(np.minimum(r, g), b)
grayish = (a[:, :, 3] > 0) & (mx - mn < 22) & (mx > 80) & (mx < 215)
removed = 0
for _ in range(4):
    ext, _ = exterior(a[:, :, 3] == 0)
    touch = ndimage.binary_dilation(ext) & grayish & (a[:, :, 3] > 0)
    if not touch.any():
        break
    a[touch] = 0; removed += touch.sum(); grayish &= ~touch

# 2) 内側の穴を埋める
t = a[:, :, 3] == 0
ext, lab = exterior(t)
filled = 0
for j in range(1, lab.max() + 1):
    m = lab == j
    if ext[m].any():
        continue
    nb = ~is_bg(raw[m])
    if nb.mean() > 0.5:   # 大半がツヤ・模様 → 穴全体を raw の色で
        a[m, :3] = raw[m]; a[m, 3] = 255; filled += m.sum()

# 3) 浮いた小さな破片
mm = a[:, :, 3] > 0
lab2, k2 = ndimage.label(mm, structure=np.ones((3, 3)))
if k2:
    sz = ndimage.sum(mm, lab2, range(1, k2 + 1)); big = np.argmax(sz) + 1
    for j in range(1, k2 + 1):
        if j != big and sz[j - 1] < 12:
            a[lab2 == j] = 0
Image.fromarray(a).save(outp)
print(outp, 'ふち削除', int(removed), '穴埋め', int(filled))
