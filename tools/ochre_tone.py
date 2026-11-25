"""茶色ペンキ組の色合わせ：赤寄りの茶色を、少しくすんだ黄土寄りに寄せる。

使い方: python3 tools/ochre_tone.py 入力.png 出力.png [寄せる量=0.5]

2026-11-25 ユーザーが柔一で選んだ「中間」の色（寄せる量 0.5）。
- 黒い線（明るさ16%未満）・灰色や白いテカリ（彩度12%未満）は変えない。
- 明るく鮮やかな色（明るさ75%以上・彩度60%以上：洸哉の黄色い目・金の腕輪）も変えない。
- 茶色（明るさ75%未満）：色相を +9度（45度で止める）、彩度 ×0.85。
- クリーム（明るさ75%以上）：色相 42度、彩度 ×1.25（0.6で止める）、明るさ ×0.82。
- 上の変換を全部かけた色と元の色を、寄せる量の割合で混ぜる（0.5 ＝ ちょうど中間）。
画素の形・透明度は変えない。生成のたびに色がずれるので、決まった色に戻すときにも使う。
"""
import colorsys
import sys

from PIL import Image


def full_shift(c):
    r, g, b = [x / 255 for x in c]
    h, s, v = colorsys.rgb_to_hsv(r, g, b)
    hd = h * 360
    if v < 0.16 or s < 0.12:
        return c
    if v >= 0.75 and s >= 0.6:
        # 洸哉の黄色い目・金の腕輪など、ペンキでない鮮やかな色は変えない（柔一には該当なし）
        return c
    if v < 0.75:
        if hd < 45:
            hd = min(hd + 9, 45)
        s *= 0.85
    else:
        hd = 42
        s = min(s * 1.25, 0.6)
        v *= 0.82
    return tuple(round(x * 255) for x in colorsys.hsv_to_rgb(hd / 360, s, v))


def tone(img, amount=0.5):
    src = img.convert("RGBA")
    out = src.copy()
    cache = {}
    w, h = src.size
    for y in range(h):
        for x in range(w):
            p = src.getpixel((x, y))
            if p[3] == 0:
                continue
            c = p[:3]
            if c not in cache:
                f = full_shift(c)
                # PIL の Image.blend と同じ丸め（切り捨て）にそろえる
                cache[c] = tuple(int(a + (b - a) * amount) for a, b in zip(c, f))
            out.putpixel((x, y), cache[c] + (p[3],))
    return out


if __name__ == "__main__":
    amt = float(sys.argv[3]) if len(sys.argv) > 3 else 0.5
    tone(Image.open(sys.argv[1]), amt).save(sys.argv[2])
