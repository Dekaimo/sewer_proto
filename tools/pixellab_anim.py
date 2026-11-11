"""PixelLab pixminimax でアニメを作り、assets_raw/gen/<name>/<日時>/ に保存する。
使う前後の残り生成回数も記録して、実際の消費を測る。
環境変数: NAME, SRC(元絵のパス), DESC(動きの説明), FRAMES(4の倍数), LAST(最後のポーズ, 任意),
          DIRECTION(east等, 任意), SUBJECT(何の絵か, 任意), VARIANTS(作るパターン数)
"""
import base64
import io
import json
import os
import time
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

from PIL import Image

BASE = "https://api.pixellab.ai/v2"
HDR = {"Authorization": "Bearer " + os.environ["PIXELLAB_API_KEY"], "Content-Type": "application/json"}


def call(method: str, path: str, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(BASE + path, data=data, headers=HDR, method=method)
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            return json.loads(r.read())
    except urllib.error.HTTPError as e:
        raise SystemExit(f"HTTP {e.code} {path}: {e.read()[:500].decode(errors='replace')}")


def b64img(path: str) -> dict:
    return {"type": "base64", "base64": base64.b64encode(Path(path).read_bytes()).decode(), "format": "png"}


def remaining() -> float:
    b = call("GET", "/balance")
    return b.get("subscription", {}).get("generations", -1)


def decode(img) -> Image.Image:
    s = img["base64"] if isinstance(img, dict) else img
    if "," in s[:40]:
        s = s.split(",", 1)[1]
    return Image.open(io.BytesIO(base64.b64decode(s))).convert("RGBA")


def main() -> None:
    name = os.environ["NAME"]
    stamp = datetime.now(timezone.utc).strftime("%m%d_%H%M%S")
    out = Path("assets_raw/gen") / name / stamp
    out.mkdir(parents=True, exist_ok=True)
    before = remaining()
    body = {
        "first_frame": b64img(os.environ["SRC"]),
        "description": os.environ["DESC"],
        "frame_count": int(os.environ.get("FRAMES", "4")),
        "no_background": True,
        "view": "side",
    }
    if os.environ.get("LAST"):
        body["last_frame"] = b64img(os.environ["LAST"])
    if os.environ.get("DIRECTION"):
        body["direction"] = os.environ["DIRECTION"]
    if os.environ.get("SUBJECT"):
        body["subject_description"] = os.environ["SUBJECT"]

    sheets = []
    for v in range(int(os.environ.get("VARIANTS", "1"))):
        job = call("POST", "/animate-pixminimax", body)
        jid = job.get("background_job_id") or job.get("id")
        for _ in range(120):
            time.sleep(5)
            st = call("GET", f"/background-jobs/{jid}")
            if st["status"] in ("completed", "failed"):
                break
        if st["status"] != "completed":
            print("failed", json.dumps(st)[:500])
            continue
        imgs = st["last_response"].get("images") or []
        frames = [decode(i) for i in imgs]
        for i, f in enumerate(frames):
            f.save(out / f"v{v + 1}_{i:02d}.png")
        sheets.append(frames)
        print("variant", v + 1, "frames", len(frames))

    after = remaining()
    # 一覧画像：パターンごとに1行、背景は暗いグレー
    if sheets:
        w, h = sheets[0][0].size
        cols = max(len(s) for s in sheets)
        sheet = Image.new("RGBA", (w * cols, h * len(sheets)), (40, 44, 52, 255))
        for r, frames in enumerate(sheets):
            for c, f in enumerate(frames):
                sheet.alpha_composite(f, (c * w, r * h))
        sheet.save(out / "sheet.png")
    info = {"desc": os.environ["DESC"], "src": os.environ["SRC"], "frames": body["frame_count"],
            "variants": len(sheets), "generations_before": before, "generations_after": after,
            "used": before - after}
    (out / "info.json").write_text(json.dumps(info, indent=2, ensure_ascii=False))
    print(json.dumps(info, ensure_ascii=False))


if __name__ == "__main__":
    main()
