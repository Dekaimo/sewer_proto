"""PixelLab API の仕様書（OpenAPI）を取ってきて保存する。生成はしないので回数は消費しない。"""
import urllib.request
from pathlib import Path
out = Path("assets_raw/pixellab")
out.mkdir(parents=True, exist_ok=True)
for name, url in [("openapi.json", "https://api.pixellab.ai/v2/openapi.json"), ("llms.txt", "https://api.pixellab.ai/v2/llms.txt")]:
    with urllib.request.urlopen(url, timeout=60) as r:
        (out / name).write_bytes(r.read())
    print("saved", name)
