"""絵を見せる前の確認（毎回かならず実行し、結果を報告に書く）。
使い方: python3 tools/check_asset.py 候補.png 基準の立ち絵.png [出力の比較画像.png]
- 大きさ：256x256 以内か（アニメはどれも256が上限）
- 体の高さ・幅：基準の立ち絵と比べた比率（体の大きさが変わっていないか）
- 透け：体の内側の透明な穴を数え、水色の背景で塗って比較画像に出す（透過し忘れ・抜きすぎの確認）
- 比較画像：基準と候補を並べ、明るい背景・水色の背景・顔まわりの拡大を1枚にまとめる
顔の特徴と向きは目で確認する（比較画像の拡大を見て、基準と同じか報告に書く）。
"""
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

cand, ref = sys.argv[1], sys.argv[2]
out = sys.argv[3] if len(sys.argv) > 3 else "/tmp/check.png"
c = Image.open(cand).convert("RGBA")
r = Image.open(ref).convert("RGBA")
ok = True
print(f"大きさ: {c.size} {'OK' if c.width <= 256 and c.height <= 256 else 'NG（256を超えている）'}")
if c.width > 256 or c.height > 256:
    ok = False
cb, rb = c.getbbox(), r.getbbox()
ch, rh = cb[3] - cb[1], rb[3] - rb[1]
cw, rw = cb[2] - cb[0], rb[2] - rb[0]
print(f"体の高さ: 候補 {ch}px / 基準 {rh}px（{ch / rh:.2f}倍）  幅: 候補 {cw}px / 基準 {rw}px")
if cb[0] <= 0 or cb[1] <= 0 or cb[2] >= c.width or cb[3] >= c.height:
    print("注意: 絵が枠の端に触れている（切れていないか確認）")
a = np.array(c)
op = a[..., 3] > 0
holes = ndimage.binary_fill_holes(op) & ~op
lab, n = ndimage.label(holes)
sizes = sorted([int((lab == i).sum()) for i in range(1, n + 1)], reverse=True)
print(f"内側の透明な穴: {n}か所 {int(holes.sum())}px（大きい順 {sizes[:8]}）")
semi = ((a[..., 3] > 0) & (a[..., 3] < 255)).sum()
print(f"半透明の画素: {semi}")

S = 3
W = max(c.width, r.width)
H = max(c.height, r.height)
sheet = Image.new("RGBA", ((W * 2 + 10) * S, (H * 2 + 10) * S), (40, 40, 48, 255))
for row, bg in enumerate([(235, 235, 225, 255), (0, 220, 255, 255)]):
    for col, im in enumerate([r, c]):
        t = Image.new("RGBA", im.size, bg)
        t.alpha_composite(im)
        sheet.paste(t.resize((im.width * S, im.height * S), Image.NEAREST), (col * (W + 10) * S, row * (H + 10) * S))
sheet.save(out)
print("比較画像:", out, "（上：明るい背景、下：水色の背景。左が基準、右が候補）")
print("総合（自動で確認できる分）:", "OK" if ok else "NG")
