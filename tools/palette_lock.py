"""ペンキ系キャラの色をペンキワニの通常ドット（assets/wani_idle.png）に合わせる。
ピンク・黄色・暗い輪郭の3種類に分け、同じ種類の中で「明るさの順位（何%目に明るいか）」が同じ色に置き換える。
生成された絵は全体に明るい・暗いのクセがあるので、絶対的な明るさではなく順位で合わせると、元の色の配分になる。
それ以外の色（白目、灰色、紫など）はそのまま残す。生成した絵を組み込む前に必ず通す。
使い方: python3 tools/palette_lock.py 入力.png [出力.png]   （出力を省略すると上書き）
"""
import sys
from PIL import Image

MASTER = "assets/wani_idle.png"


def lum(c):
    return 0.30 * c[0] + 0.59 * c[1] + 0.11 * c[2]


def kind(c):
    r, g, b = c
    mx, mn = max(c), min(c)
    sat = (mx - mn) / mx if mx else 0.0
    if lum(c) < 40:
        return "dark"
    if r > 150 and g > 120 and b < 140 and g > b + 40:
        return "yellow"
    if r > g + 30 and r >= b and sat > 0.25:
        return "pink"
    return None   # ペンキ以外の色は触らない


def _weighted(im):
    """種類ごとに (明るさ, 色, 画素数) を明るい順に並べ、累積の割合を付ける"""
    counts = {"pink": {}, "yellow": {}, "dark": {}}
    for p in im.getdata():
        if p[3]:
            k = kind(p[:3])
            if k:
                counts[k][p[:3]] = counts[k].get(p[:3], 0) + 1
    out = {}
    for k, d in counts.items():
        cols = sorted(d.items(), key=lambda kv: lum(kv[0]))
        total = sum(n for _, n in cols) or 1
        acc, lst = 0, []
        for c, n in cols:
            lst.append((c, (acc + n / 2) / total))
            acc += n
        out[k] = lst
    return out


def lock(src, dst=None):
    master = _weighted(Image.open(MASTER).convert("RGBA"))
    im = Image.open(src).convert("RGBA")
    mine = _weighted(im)
    table = {}
    for k, lst in mine.items():
        if not master[k]:
            continue
        for c, q in lst:
            table[c] = min(master[k], key=lambda mc: abs(mc[1] - q))[0]
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if a and (r, g, b) in table:
                px[x, y] = table[(r, g, b)] + (a,)
    im.save(dst or src)


if __name__ == "__main__":
    lock(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else None)
