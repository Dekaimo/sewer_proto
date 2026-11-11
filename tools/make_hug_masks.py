"""2体が1枚に描かれた絵（抱きつき等）から、主人公の部分だけを白にしたマスク画像を作る。
色で候補を拾い、ある程度大きなかたまり（主人公の体）だけを残すので、
ワニの目のような小さな灰色の部分は除外される。うまく取れない絵はマスクPNGを手で直せばよい。
使い方: python3 tools/make_hug_masks.py assets/wani_grab_*.png assets/wani_hug_*.png
"""
import sys
from collections import deque
from PIL import Image

MIN_SIZE = 150


def is_cat(r, g, b, a):
    if a == 0:
        return False
    mx, mn = max(r, g, b), min(r, g, b)
    if mx < 30:
        return False
    sat = (mx - mn) / mx
    return sat < 0.28 or (b >= r and b > g)


def make(path):
    im = Image.open(path).convert("RGBA")
    w, h = im.size
    px = im.load()
    cand = [[is_cat(*px[x, y]) for x in range(w)] for y in range(h)]
    seen = [[False] * w for _ in range(h)]
    mask = Image.new("L", (w, h), 0)
    mp = mask.load()
    for y in range(h):
        for x in range(w):
            if not cand[y][x] or seen[y][x]:
                continue
            comp, q = [], deque([(x, y)])
            seen[y][x] = True
            while q:
                cx, cy = q.popleft()
                comp.append((cx, cy))
                for dx in (-1, 0, 1):
                    for dy in (-1, 0, 1):
                        nx, ny = cx + dx, cy + dy
                        if 0 <= nx < w and 0 <= ny < h and cand[ny][nx] and not seen[ny][nx]:
                            seen[ny][nx] = True
                            q.append((nx, ny))
            if len(comp) >= MIN_SIZE:
                for cx, cy in comp:
                    mp[cx, cy] = 255
    out = path.replace(".png", "_mask.png").replace("assets/", "assets/masks/")
    mask.save(out)
    return out, sum(1 for v in mask.getdata() if v)


if __name__ == "__main__":
    import os
    os.makedirs("assets/masks", exist_ok=True)
    for p in sys.argv[1:]:
        print(*make(p))
