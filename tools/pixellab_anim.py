"""PixelLab で絵を作り、assets_raw/gen/<name>/<日時>/ に保存する。使う前後の残り生成回数も記録する。
環境変数 JOBS に JSON の配列で複数の作業を渡す。各要素:
  {"name", "mode": "anim"|"edit", "src", "desc", "frames", "last", "direction", "subject", "variants"}
  anim = pixminimax でアニメ（src が最初のコマ、last が最後のポーズ）
  edit = pixen で1枚絵を文章の指示で編集（ポーズ違いなどを作る）
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


def run_job(j: dict) -> None:
    name = j["name"]
    stamp = datetime.now(timezone.utc).strftime("%m%d_%H%M%S")
    out = Path("assets_raw/gen") / name / stamp
    out.mkdir(parents=True, exist_ok=True)
    before = remaining()
    if j.get("mode", "anim") == "edit":
        path = "/edit-image-pixen"
        body = {"image": b64img(j["src"]), "description": j["desc"], "no_background": True}
    else:
        path = "/animate-pixminimax"
        body = {"first_frame": b64img(j["src"]), "description": j["desc"],
                "frame_count": int(j.get("frames", 4)), "no_background": True, "view": "side"}
        if j.get("last"):
            body["last_frame"] = b64img(j["last"])
        if j.get("direction"):
            body["direction"] = j["direction"]
        if j.get("subject"):
            body["subject_description"] = j["subject"]

    rows = []
    for v in range(int(j.get("variants", 1))):
        job = call("POST", path, body)
        jid = job.get("background_job_id") or job.get("id")
        st = {}
        for _ in range(120):
            time.sleep(5)
            st = call("GET", f"/background-jobs/{jid}")
            if st["status"] in ("completed", "failed"):
                break
        if st.get("status") != "completed":
            print("failed", name, json.dumps(st)[:500])
            continue
        lr = st["last_response"] or {}
        imgs = lr.get("images") or ([lr["image"]] if lr.get("image") else [])
        frames = [decode(i) for i in imgs]
        for i, f in enumerate(frames):
            f.save(out / f"v{v + 1}_{i:02d}.png")
        rows.append(frames)
        print(name, "variant", v + 1, "frames", len(frames))

    after = remaining()
    if rows:
        w = max(f.size[0] for r in rows for f in r)
        h = max(f.size[1] for r in rows for f in r)
        cols = max(len(r) for r in rows)
        sheet = Image.new("RGBA", (w * cols, h * len(rows)), (40, 44, 52, 255))
        for r, frames in enumerate(rows):
            for c, f in enumerate(frames):
                sheet.alpha_composite(f, (c * w, r * h))
        sheet.save(out / "sheet.png")
    info = dict(j, generations_before=before, generations_after=after, used=before - after)
    (out / "info.json").write_text(json.dumps(info, indent=2, ensure_ascii=False))
    print(json.dumps(info, ensure_ascii=False))


def main() -> None:
    for j in json.loads(os.environ["JOBS"]):
        run_job(j)


if __name__ == "__main__":
    main()
