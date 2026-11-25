# 体格・向き・大きさの見本：左斜め向きに立つ、のっぺりした灰色の人型（256x256）
import sys
from PIL import Image, ImageDraw
H_TOP = int(sys.argv[2]) if len(sys.argv) > 2 else 24   # 頭のてっぺん（たてがみは含まない）
FEET = 250
out = sys.argv[1]
S = 4  # 大きく描いてから縮めて角をなめらかに…はしない（ドットのまま）。比率だけ使う
W = 256
im = Image.new("RGBA", (W, W), (0, 0, 0, 0))
far = Image.new("RGBA", (W, W), (0, 0, 0, 0))
d = ImageDraw.Draw(im); df = ImageDraw.Draw(far)
NEAR = (150, 150, 150, 255); FAR = (105, 105, 105, 255); OUT = (40, 40, 40, 255)
t = H_TOP; L = FEET - t           # 全体の長さ
y = lambda f: round(t + L * f)    # 0=頭のてっぺん 1=足の裏
def cap(dr, p, q, r, col):
    dr.line([p, q], fill=col, width=2 * r)
    for c in (p, q):
        dr.ellipse([c[0] - r, c[1] - r, c[0] + r, c[1] + r], fill=col)
# 奥の腕・奥の脚（暗い灰色、体の後ろ）
cap(df, (172, y(.23)), (176, y(.37)), 11, FAR)
cap(df, (176, y(.37)), (174, y(.48)), 9, FAR)
df.ellipse([166, y(.47), 184, y(.535)], fill=FAR)
cap(df, (144, y(.52)), (148, y(.76)), 14, FAR)
cap(df, (148, y(.76)), (146, y(.96)), 9, FAR)
df.ellipse([128, y(.96) - 5, 156, y(1.0)], fill=FAR)
# 胴（逆三角：肩幅広く、腰は細い）
d.polygon([(82, y(.20)), (174, y(.20)), (164, y(.33)), (150, y(.44)), (154, y(.52)),
           (104, y(.52)), (108, y(.44)), (96, y(.33))], fill=NEAR)
d.ellipse([76, y(.17), 118, y(.30)], fill=NEAR)    # 手前の肩
d.ellipse([140, y(.17), 180, y(.29)], fill=NEAR)   # 奥の肩（大部分は胴に重なる）
# 首（太い）
d.polygon([(118, y(.10)), (146, y(.10)), (154, y(.21)), (108, y(.21))], fill=NEAR)
# 頭：頭蓋＋左下へ伸びる長い口先（馬）
d.ellipse([120, t, 148, y(.085)], fill=NEAR)
d.polygon([(124, y(.03)), (142, y(.07)), (130, y(.13)), (106, y(.145)), (102, y(.11)), (110, y(.065))], fill=NEAR)
d.ellipse([98, y(.09), 114, y(.15)], fill=NEAR)    # 鼻先（左を向く）
d.polygon([(136, t - 2), (142, t + 8), (132, t + 8)], fill=NEAR)   # 耳
# 手前の腕（太い）
cap(d, (90, y(.24)), (84, y(.37)), 13, NEAR)
cap(d, (84, y(.37)), (86, y(.49)), 10, NEAR)
d.ellipse([77, y(.48), 95, y(.545)], fill=NEAR)
# 手前の脚（太くまっすぐ）、足先は左へ
cap(d, (118, y(.52)), (112, y(.76)), 16, NEAR)
cap(d, (112, y(.76)), (112, y(.96)), 10, NEAR)
d.ellipse([90, y(.955), 122, FEET], fill=NEAR)
base = Image.alpha_composite(far, im)
# 外側に1ドットの暗い縁
a = base.getchannel("A")
from PIL import ImageFilter
grown = a.filter(ImageFilter.MaxFilter(3))
edge = Image.new("RGBA", (W, W), OUT); edge.putalpha(grown)
res = Image.alpha_composite(edge, base)
res.save(out)
bb = res.getbbox(); print("bbox", bb, "height", bb[3] - bb[1])
