# 磔の場面（ワニ柱・猫・ドーベルマン）を、ドーベルマンの層と同じ256の枠で切り出す／粘液を切り出して層に戻す。
#  blue:   python3 tools/cru_scene.py blue ドーベルマン層.png 猫.png 出力.png
#          ワニを青く塗り替え、猫とドーベルマンを重ねて、ドーベルマンの層の枠（ワニの左上から x-39, y+63）で切り出す
#  goo:    python3 tools/cru_scene.py goo 編集前.png 編集フォルダ 猫.png 出力の粘液層.png
#          extract_goo で切り出した粘液から、猫の形の内側・青・灰色・小さな破片を除く
import sys, os, subprocess
import numpy as np
from PIL import Image
from scipy import ndimage
WANI = 'assets_raw/wani_cru_tall.png'
OX, OY = 170, 10            # 場面の中のワニの左上
DX, DY = -39, 63            # ドーベルマン層の左上（ワニからのずれ）
CAT = (56, 52)              # 猫の左上（ワニからのずれ）

def blue_wani():
    W = np.array(Image.open(WANI).convert('RGBA')).astype(float)
    lum = 0.3 * W[..., 0] + 0.59 * W[..., 1] + 0.11 * W[..., 2]
    B = W.copy(); B[..., 0] = lum * 0.35; B[..., 1] = lum * 0.6; B[..., 2] = np.minimum(255, lum * 1.15 + 40)
    B = B.clip(0, 255).astype(np.uint8); B[..., 3] = W[..., 3].astype(np.uint8)
    return Image.fromarray(B)

def cat_mask(catp):
    cat = np.array(Image.open(catp).convert('RGBA'))
    cm = np.zeros((256, 256), bool)
    cx, cy = CAT[0] - DX, CAT[1] - DY
    for y in range(cat.shape[0]):
        for x in range(cat.shape[1]):
            ly, lx = y + cy, x + cx
            if 0 <= ly < 256 and 0 <= lx < 256 and cat[y, x, 3] > 0:
                cm[ly, lx] = True
    return cm

if sys.argv[1] == 'blue':
    dobe, catp, out = sys.argv[2:5]
    C = Image.new('RGBA', (700, 520), (0, 0, 0, 0))
    C.alpha_composite(blue_wani(), (OX, OY))
    C.alpha_composite(Image.open(catp).convert('RGBA'), (OX + CAT[0], OY + CAT[1]))
    C.alpha_composite(Image.open(dobe).convert('RGBA'), (OX + DX, OY + DY))
    C.crop((OX + DX, OY + DY, OX + DX + 256, OY + DY + 256)).save(out)
    print(out)
else:
    src, gen, catp, out = sys.argv[2:6]
    tmp = out + '.raw.png'
    subprocess.run(['python3', 'tools/extract_goo.py', src, gen, tmp], check=True)
    g = np.array(Image.open(tmp).convert('RGBA')).astype(int); os.remove(tmp)
    R, G, B, A = [g[..., i] for i in range(4)]
    blue = (B > R + 15) & (G > R - 10)
    gray = (np.abs(R - G) < 22) & (np.abs(R - B) < 22) & (R > 40) & (R < 230)
    keep = (A > 0) & ~cat_mask(catp) & ~blue & ~gray
    g[~keep] = 0
    m = g[..., 3] > 0
    lab, n = ndimage.label(m, structure=np.ones((3, 3)))
    sz = ndimage.sum(m, lab, range(1, n + 1))
    pink = (g[..., 0] > g[..., 1] + 30) & m
    for j in range(1, n + 1):
        comp = lab == j
        if sz[j - 1] < 15 or pink[comp].sum() < 0.5 * comp.sum():
            g[comp] = 0
    Image.fromarray(g.astype(np.uint8)).save(out)
    print(out, '粘液', int((g[..., 3] > 0).sum()), 'px')
