"""ペンキ系キャラの色味をペンキワニの通常ドット（assets/wani_idle.png）に寄せる。

前のやり方（ワニの色に1色ずつ置き換える）は色数が減って、影が濃く・線が荒くなった。
今のやり方は色を置き換えず、「ピンク」「黄色」それぞれの色相・彩度・明るさの平均とばらつきを
ワニに合わせて全体をずらすだけ（色の転写）。生成された絵の階調や描き込みはそのまま残る。
暗い輪郭やペンキ以外の色（白目・灰色・紫など）には触らない。

使い方: python3 tools/palette_lock.py 入力.png [出力.png]   （出力を省略すると上書き）
"""
import colorsys
import math
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
        return None   # 輪郭は触らない
    if r > 150 and g > 120 and b < 140 and g > b + 40:
        return "yellow"
    if r > g + 30 and r >= b and sat > 0.25:
        return "pink"
    return None


def _stats(im):
    """種類ごとに、色相（円周の平均）・彩度・明るさの平均と標準偏差を求める"""
    acc = {}
    for p in im.getdata():
        if not p[3]:
            continue
        k = kind(p[:3])
        if not k:
            continue
        h, s, v = colorsys.rgb_to_hsv(*(x / 255.0 for x in p[:3]))
        a = acc.setdefault(k, {"hx": 0.0, "hy": 0.0, "s": [], "v": []})
        a["hx"] += math.cos(h * 2 * math.pi)
        a["hy"] += math.sin(h * 2 * math.pi)
        a["s"].append(s)
        a["v"].append(v)
    out = {}
    for k, a in acc.items():
        def ms(xs):
            m = sum(xs) / len(xs)
            return m, max((sum((x - m) ** 2 for x in xs) / len(xs)) ** 0.5, 1e-3)
        out[k] = {"h": (math.atan2(a["hy"], a["hx"]) / (2 * math.pi)) % 1.0, "s": ms(a["s"]), "v": ms(a["v"])}
    return out


def lock(src, dst=None, strength=1.0, stats_from=None):
    """stats_from を渡すと、その絵の色の傾向を基準にずらす（アニメの全コマを同じずらし方にして、ちらつきを防ぐ）"""
    master = _stats(Image.open(MASTER).convert("RGBA"))
    im = Image.open(src).convert("RGBA")
    mine = _stats(Image.open(stats_from).convert("RGBA")) if stats_from else _stats(im)
    px = im.load()
    cache = {}
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if not a:
                continue
            c = (r, g, b)
            if c not in cache:
                k = kind(c)
                if not k or k not in master or k not in mine:
                    cache[c] = c
                else:
                    h, s, v = colorsys.rgb_to_hsv(r / 255.0, g / 255.0, b / 255.0)
                    M, S = master[k], mine[k]
                    dh = ((M["h"] - S["h"] + 0.5) % 1.0) - 0.5
                    h2 = (h + dh * strength) % 1.0
                    # 平均とばらつきを合わせる（ばらつきは縮めすぎない＝階調を残す）
                    s2 = M["s"][0] + (s - S["s"][0]) * max(M["s"][1] / S["s"][1], 0.75)
                    v2 = M["v"][0] + (v - S["v"][0]) * max(M["v"][1] / S["v"][1], 0.75)
                    s2 = s + (s2 - s) * strength
                    v2 = v + (v2 - v) * strength
                    rr, gg, bb = colorsys.hsv_to_rgb(h2, min(max(s2, 0.0), 1.0), min(max(v2, 0.0), 1.0))
                    cache[c] = (round(rr * 255), round(gg * 255), round(bb * 255))
            px[x, y] = cache[c] + (a,)
    im.save(dst or src)


def lock_frames(srcs, dsts, key):
    """アニメ用：全コマを key（代表の1枚）の傾向で同じようにずらす"""
    for s, d in zip(srcs, dsts):
        lock(s, d, stats_from=key)


if __name__ == "__main__":
    lock(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else None)
