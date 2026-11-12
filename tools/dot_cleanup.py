"""生成ドットの掃除：体の中の小さな抜け（透明の穴）を埋め、塗りの中に浮いた孤立した暗い点を消し、
中間色のノイズを減らすために色数を絞る。輪郭線や大きな隙間（腕と胴のあいだ等）には触らない。
使い方: python3 tools/dot_cleanup.py 入力.png 出力.png [色数=32]
"""
import sys
import numpy as np
from PIL import Image
from scipy import ndimage

src, dst = sys.argv[1], sys.argv[2]
ncol = int(sys.argv[3]) if len(sys.argv) > 3 else 32
a = np.array(Image.open(src).convert("RGBA")).astype(int)
solid = a[..., 3] > 0
lum = 0.30 * a[..., 0] + 0.59 * a[..., 1] + 0.11 * a[..., 2]

def neigh_fill(mask, ok):
    """mask の画素を、周りの ok な画素の最頻色で埋める（外側から順に）"""
    mask = mask.copy()
    for _ in range(6):
        if not mask.any():
            break
        ys, xs = np.nonzero(mask)
        done = []
        for y, x in zip(ys, xs):
            cs = []
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    yy, xx = y + dy, x + dx
                    if (dy or dx) and 0 <= yy < a.shape[0] and 0 <= xx < a.shape[1] and ok[yy, xx] and not mask[yy, xx]:
                        cs.append(tuple(a[yy, xx]))
            if len(cs) >= 3:
                a[y, x] = max(set(cs), key=cs.count)
                done.append((y, x))
        for y, x in done:
            mask[y, x] = False
    return mask

# 1) 小さな穴（4画素以下）を埋める
holes = ndimage.binary_fill_holes(solid) & ~solid
lab, n = ndimage.label(holes)
sizes = ndimage.sum(holes, lab, range(1, n + 1))
small = np.isin(lab, [i + 1 for i, s in enumerate(sizes) if s <= 4])
neigh_fill(small, solid)
solid = a[..., 3] > 0
print("filled holes px:", int(small.sum()))

# 2) 塗りの中の孤立した暗い点（2画素以下、周り8画素がほぼ明るい）を消す
lum = 0.30 * a[..., 0] + 0.59 * a[..., 1] + 0.11 * a[..., 2]
dark = solid & (lum < 90)
lab, n = ndimage.label(dark, structure=np.ones((3, 3)))
sizes = ndimage.sum(dark, lab, range(1, n + 1))
cand = np.isin(lab, [i + 1 for i, s in enumerate(sizes) if s <= 2])
# 縁（透明に接している）は輪郭なので除外
edge = ndimage.binary_dilation(~solid, np.ones((3, 3))) & solid
cand &= ~edge
neigh_fill(cand, solid & ~dark)
print("removed specks px:", int(cand.sum()))

# 3) 色数を絞って中間色のノイズを減らす（輪郭の暗色も含めて全体で）
im = Image.fromarray(a.astype(np.uint8), "RGBA")
rgb = im.convert("RGB").quantize(colors=ncol, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGB")
out = Image.merge("RGBA", (*rgb.split(), im.split()[3]))
out.save(dst)
print("colors:", len(set(c for c, al in zip(out.convert("RGB").getdata(), out.getdata()) if al[3])))
