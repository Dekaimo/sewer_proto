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
    "hit": ("wet thick paint slap hitting a body, sticky splat, short", 0.8),
    "grab": ("heavy slime grabbing, thick goo wrapping around, squelch, short", 1.2),
    "grab_loop": ("slow sticky slime squishing and squeezing, wet goo kneading, short", 1.0),
    "assist": ("large wet goo splash dumped on body, thick viscous splatter", 1.2),
    "step_paint": ("footstep in sticky wet paint puddle, squelchy", 0.5),
    "mop": ("wet mop swing and slap on floor", 0.7),
    "wipe": ("wiping sticky goo off fur with cloth, short wet rub", 0.7),
    "escape": ("pulling free from thick sticky slime, wet suction pop", 1.0),
    "defeat": ("body collapsing into a big puddle of thick goo, long squelch", 2.5),
}


def generate(text: str, seconds: float) -> bytes:
    req = urllib.request.Request(
        "https://api.elevenlabs.io/v1/sound-generation?output_format=mp3_44100_128",
        data=json.dumps({"text": text, "duration_seconds": seconds, "prompt_influence": 0.5}).encode(),
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
