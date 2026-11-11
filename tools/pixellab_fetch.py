"""PixelLab に保存済みのキャラ・オブジェクトを一覧化し、ZIPで取り出して assets_raw/pixellab/ に展開する。"""
import io
import json
import os
import re
import urllib.request
import zipfile
from pathlib import Path

BASE = "https://api.pixellab.ai/v2"
HDR = {"Authorization": "Bearer " + os.environ["PIXELLAB_API_KEY"]}
OUT = Path("assets_raw/pixellab")


def get(path: str) -> bytes:
    req = urllib.request.Request(BASE + path, headers=HDR)
    with urllib.request.urlopen(req, timeout=120) as r:
        return r.read()


def items(data):
    if isinstance(data, list):
        return data
    for k in ("characters", "objects", "items", "data", "results"):
        if isinstance(data.get(k), list):
            return data[k]
    return []


def slug(s: str) -> str:
    return re.sub(r"[^A-Za-z0-9_-]+", "_", s)[:40].strip("_") or "item"


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT.parent / ".gdignore").write_text("")
    try:
        (OUT / "balance.json").write_bytes(get("/balance"))
    except Exception as e:
        print("balance failed", e)
    for kind in ("characters", "objects"):
        try:
            listing = json.loads(get(f"/{kind}?limit=100"))
        except Exception as e:
            print(kind, "list failed", e)
            continue
        (OUT / f"{kind}.json").write_text(json.dumps(listing, indent=2, ensure_ascii=False))
        for it in items(listing):
            iid = it.get("id") or it.get(f"{kind[:-1]}_id")
            name = it.get("name") or it.get("description") or it.get("prompt") or str(iid)
            d = OUT / kind / f"{slug(str(name))}_{str(iid)[:8]}"
            d.mkdir(parents=True, exist_ok=True)
            try:
                (d / "detail.json").write_bytes(get(f"/{kind}/{iid}"))
                zipfile.ZipFile(io.BytesIO(get(f"/{kind}/{iid}/zip"))).extractall(d)
                print("got", d)
            except Exception as e:
                print("failed", d, e)


if __name__ == "__main__":
    main()
