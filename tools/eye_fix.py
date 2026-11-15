# 目線差し替え：生成した1枚の目（白目・黒目）を元の色に合わせ、黒目の中のハイライトを消して、breathe_0..7 の全コマに同じ目を入れる。
# 使い方: python3 tools/eye_fix.py 目の元にする絵.png 出力の頭（例 assets/cru2/breathe_up）
import numpy as np, sys
from PIL import Image
from scipy import ndimage
src, outpre = sys.argv[1], sys.argv[2]
X0,X1,Y0,Y1=106,132,29,48
base=np.array(Image.open('assets/cru2/breathe_0.png').convert('RGBA'))
ed=np.array(Image.open(src).convert('RGB')).astype(int)
bb=base[Y0:Y1,X0:X1,:3].astype(int); eb=ed[Y0:Y1,X0:X1]; op=base[Y0:Y1,X0:X1,3]>0
pal=np.unique(bb[op].reshape(-1,3),axis=0)
d=((eb[:,:,None,:]-pal[None,None])**2).sum(3); lock=pal[d.argmin(2)]
PUP=np.array([24,2,34])
eyeish=lambda c:(c.min(2)>170)|(c.sum(2)<150)
near=ndimage.binary_dilation(eyeish(lock)&(lock.min(2)>170)|eyeish(bb)&(bb.min(2)>170),iterations=4)
dark=lock.sum(2)<150; light=lock.min(2)>170
lab,n=ndimage.label(light)
for k in range(1,n+1):
  comp=lab==k
  if comp.sum()<=3:
    ring=ndimage.binary_dilation(comp)&~comp
    if dark[ring].mean()>0.7: lock[comp]=PUP; print('highlight removed',comp.sum())
m=(np.abs(lock-bb).sum(2)>40)&near&op
print(src,'changed px',m.sum())
for i in range(8):
  o=np.array(Image.open(f'assets/cru2/breathe_{i}.png').convert('RGBA'))
  blk=o[Y0:Y1,X0:X1]; blk[m,:3]=lock[m]
  Image.fromarray(o).save(f'{outpre}_{i}.png')
