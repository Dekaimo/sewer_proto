"""表情だけ差し替える。
通常の立ち絵（orig）と、表情だけ変えた絵（edit）の差分のうち顔のあたりだけを取り出し、
待機・歩きの各コマの顔の位置（テンプレート照合で探す）に貼り込む。体・帽子などは通常の絵のまま。

python3 tools/face_patch.py ORIG EDIT OUT_PREFIX FRAME...
  例: python3 tools/face_patch.py assets/cat_idle_0.png edit.png assets/cat_idle1_ assets/cat_idle_0.png ...
"""
import sys
import numpy as np
from PIL import Image
from scipy import ndimage

# 顔のあたり（128px の立ち絵の座標）。帽子のつばより下、首より上
FACE = (44, 34, 100, 66)   # x0, y0, x1, y1


def load(p):
    return np.array(Image.open(p).convert("RGBA")).astype(int)


def face_mask(orig, edit):
    d = np.abs(orig - edit).sum(-1) > 40
    m = np.zeros_like(d)
    x0, y0, x1, y1 = FACE
    m[y0:y1, x0:x1] = d[y0:y1, x0:x1]
    # 小さすぎる点（生成のノイズ）は捨て、残りを1ドット広げる
    lab, n = ndimage.label(m)
    for j in range(1, n + 1):
        if (lab == j).sum() < 2:
            m[lab == j] = False
    return ndimage.binary_dilation(m, iterations=1) & (edit[..., 3] > 0)


def find_offset(orig, frame, search=10):
    x0, y0, x1, y1 = FACE
    tpl = orig[y0:y1, x0:x1].astype(float)
    best, bo = None, (0, 0)
    for dy in range(-search, search + 1):
        for dx in range(-search, search + 1):
            ys, xs = y0 + dy, x0 + dx
            if ys < 0 or xs < 0 or ys + (y1 - y0) > frame.shape[0] or xs + (x1 - x0) > frame.shape[1]:
                continue
            c = frame[ys:ys + (y1 - y0), xs:xs + (x1 - x0)].astype(float)
            e = np.abs(c - tpl).sum()
            if best is None or e < best:
                best, bo = e, (dx, dy)
    return bo


def main():
    orig, edit = load(sys.argv[1]), load(sys.argv[2])
    out_prefix = sys.argv[3]
    m = face_mask(orig, edit)
    ys, xs = np.nonzero(m)
    for i, fp in enumerate(sys.argv[4:]):
        fr = load(fp)
        dx, dy = find_offset(orig, fr)
        out = fr.copy()
        ty, tx = ys + dy, xs + dx
        ok = (ty >= 0) & (ty < fr.shape[0]) & (tx >= 0) & (tx < fr.shape[1])
        out[ty[ok], tx[ok]] = edit[ys[ok], xs[ok]]
        Image.fromarray(out.astype(np.uint8)).save(f"{out_prefix}{i}.png")
        print(fp, "offset", dx, dy)


if __name__ == "__main__":
    main()
