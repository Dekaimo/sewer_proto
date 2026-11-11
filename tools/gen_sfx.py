"""ElevenLabs で効果音を作り、sfx/<イベント>/ に保存する（GitHub Actions から実行）。
既にあるファイルは作り直さない。作り直したい音は消してから再実行する。
"""
import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path

PER_EVENT = int(os.environ.get("PER_EVENT", "3"))
ONLY = os.environ.get("ONLY", "").strip()

# イベント名: (プロンプト, 長さ秒)
PROMPTS = {
    "hit": ("soft thick slime glob landing, sticky gooey plop, viscous and muffled, no liquid splash", 0.9),
    "grab": ("thick sticky slime slowly engulfing, gooey stretching squelch, viscous, muffled", 1.4),
    "grab_loop": ("slow sticky goo squishing, thick slime kneaded in hands, gloopy squelch, gentle", 1.2),
    "assist": ("big glob of thick viscous slime oozing over, gloopy sticky squelch, slow", 1.5),
    "step_paint": ("foot sinking into thick sticky goo, slow gloopy squelch, mud-like", 0.6),
    "mop": ("mop dragging through thick sticky slime, gooey smear", 0.8),
    "wipe": ("sticky slime being slowly smeared and wiped off, gooey stretch", 0.8),
    "escape": ("pulling out of thick sticky slime, long gooey stretch and suction release", 1.2),
    "defeat": ("slowly sinking into thick viscous slime, deep gloopy gurgling ooze", 2.5),
    "gurgle": ("muffled thick goo churning and squelching underground, slimy bubbling gurgles, something struggling inside sticky slime", 1.6),
}


def generate(text: str, seconds: float) -> bytes:
    req = urllib.request.Request(
        "https://api.elevenlabs.io/v1/sound-generation?output_format=mp3_44100_128",
        data=json.dumps({"text": text, "duration_seconds": seconds, "prompt_influence": 0.75}).encode(),
        headers={"xi-api-key": os.environ["ELEVENLABS_API_KEY"], "Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=120) as r:
        return r.read()


def main() -> int:
    made = 0
    for ev, (text, sec) in PROMPTS.items():
        if ONLY and ev not in ONLY.split(","):
            continue
        d = Path("sfx") / ev
        d.mkdir(parents=True, exist_ok=True)
        have = len(list(d.glob("*.mp3")))
        for i in range(have, PER_EVENT):
            path = d / f"{ev}_{i + 1:02d}.mp3"
            n = i + 1
            while path.exists():
                n += 1
                path = d / f"{ev}_{n:02d}.mp3"
            try:
                path.write_bytes(generate(text, sec))
                made += 1
                print("made", path)
            except urllib.error.HTTPError as e:
                print("failed", ev, e.code, e.read()[:300].decode(errors="replace"))
                return 1
    print("total", made)
    return 0


if __name__ == "__main__":
    sys.exit(main())
