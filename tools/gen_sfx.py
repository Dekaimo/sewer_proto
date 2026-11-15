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
    "hit": ("wet sloppy glob of thick slime slapping on, squelchy gooey splat, sticky and squishy", 0.9),
    "grab": ("thick wet slime wrapping and squeezing, sloppy squelching and squishing, sticky gooey stretch", 1.4),
    "grab_loop": ("wet sticky goo being squished and kneaded, sloppy squelchy squishing, gloopy and slimy", 1.2),
    "assist": ("big wet mass of thick slime oozing over, sloppy squelch, gloopy sticky splorch", 1.5),
    "step_paint": ("foot squelching into thick wet sticky goo, sloppy squish", 0.6),
    "mop": ("mop sloshing through thick wet slime, squelchy gooey smear", 0.8),
    "wipe": ("wet sticky slime being smeared and wiped, squelchy gooey stretch", 0.8),
    "escape": ("pulling free from thick wet slime, long squelchy stretch and wet suction pop", 1.2),
    "defeat": ("slowly sinking into thick wet slime, deep sloppy squelching and gurgling ooze", 2.5),
    "gurgle": ("thick wet goo churning and squelching, sloppy slimy bubbling, something squirming inside sticky slime", 1.6),
    "slurp": ("thick wet goo being forced down a throat, sloppy wet gulping and squelching, sticky slurp", 1.2),
    "snort": ("a big relaxed smug snort through the nose of a large beast, a short amused huff of breath out the nostrils, slightly wet", 0.8),
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
