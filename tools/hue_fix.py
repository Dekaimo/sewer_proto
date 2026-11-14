# 生成で赤・橙に寄ってしまったピンクの部分の色相だけをピンクに戻す（明るさ・彩度・描き込みはそのまま）。
# 使い方: python3 tools/hue_fix.py 入力.png 出力.png
import sys, colorsys
import numpy as np
from PIL import Image
a = np.array(Image.open(sys.argv[1]).convert('RGBA'))
n = 0
for y, x in zip(*np.where(a[:, :, 3] > 0)):
    r, g, b = a[y, x, :3] / 255
    h, l, s = colorsys.rgb_to_hls(r, g, b)
    hd = h * 360
    if s > 0.25 and 0.12 < l < 0.92 and (hd >= 335 or hd < 25):
        r2, g2, b2 = colorsys.hls_to_rgb(322 / 360, l, s)
        a[y, x, :3] = [round(r2 * 255), round(g2 * 255), round(b2 * 255)]; n += 1
Image.fromarray(a).save(sys.argv[2])
print(sys.argv[2], '色相を戻した画素', n)
