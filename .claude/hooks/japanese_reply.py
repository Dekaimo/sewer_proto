#!/usr/bin/env python3
"""返答を日本語に保つためのフック（参考: クラスメソッドの記事「Claude Code hooks で英語の返答を防ぐ」）。
- UserPromptSubmit: 毎回「日本語で返答する」ことを文脈に足す
- Stop: 最後の返答が英語なら止めて、日本語で書き直させる（stop_hook_active の時は止めない＝無限ループ防止）
英語の判定: コード・URL・パスを除いた本文で、ラテン文字が一定数以上かつ日本語の文字の割合が低い段落があるか
"""
import json
import os
import re
import sys

MIN_LATIN = int(os.environ.get("JAPANESE_REPLY_MIN_LATIN", "80"))
MAX_JA_RATIO = float(os.environ.get("JAPANESE_REPLY_MAX_JA_RATIO", "0.25"))
BANNED = re.compile(r"(その|おっしゃる|仰る|御指摘の|ご指摘の)通り")
JA = re.compile(r"[぀-ヿ㐀-鿿ｦ-ﾟ]")
LATIN = re.compile(r"[A-Za-z]")


def clean(text: str) -> str:
    text = re.sub(r"```.*?```", " ", text, flags=re.S)
    text = re.sub(r"`[^`]*`", " ", text)
    text = re.sub(r"https?://\S+", " ", text)
    text = re.sub(r"[\w./~-]*/[\w./-]+", " ", text)          # パス
    text = re.sub(r"\b[\w-]+\.(png|gif|md|py|gd|json|txt|tscn|ogg)\b", " ", text)
    return text


def is_english(text: str) -> bool:
    text = clean(text or "")
    total_latin = len(LATIN.findall(text))
    total_ja = len(JA.findall(text))
    if total_latin >= MIN_LATIN and total_ja / max(total_ja + total_latin, 1) < MAX_JA_RATIO:
        return True
    for para in re.split(r"\n\s*\n", text):
        if para.lstrip().startswith(">"):
            continue
        la, ja = len(LATIN.findall(para)), len(JA.findall(para))
        if la >= MIN_LATIN and ja / max(ja + la, 1) < MAX_JA_RATIO:
            return True
    return False


def last_assistant_text(data: dict) -> str:
    msg = data.get("last_assistant_message")
    if isinstance(msg, str) and msg:
        return msg
    path = data.get("transcript_path")
    if not path or not os.path.exists(path):
        return ""
    last = ""
    with open(path, encoding="utf-8") as f:
        for line in f:
            try:
                e = json.loads(line)
            except Exception:
                continue
            m = e.get("message") or {}
            if e.get("type") == "assistant" or m.get("role") == "assistant":
                content = m.get("content")
                if isinstance(content, str):
                    t = content
                else:
                    t = "".join(c.get("text", "") for c in (content or []) if isinstance(c, dict) and c.get("type") == "text")
                if t.strip():
                    last = t
    return last


def latest_text_since_user(path: str) -> str:
    """直近のユーザー発言より後に書いた文（作業途中の文を含む）をすべてつなげて返す"""
    if not path or not os.path.exists(path):
        return ""
    texts = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            try:
                e = json.loads(line)
            except Exception:
                continue
            m = e.get("message") or {}
            role = m.get("role") or e.get("type")
            content = m.get("content")
            if role == "user":
                if isinstance(content, str) or any(isinstance(c, dict) and c.get("type") == "text" for c in (content or [])):
                    texts = []
                continue
            if role == "assistant":
                if isinstance(content, str):
                    texts.append(content)
                else:
                    texts.extend(c.get("text", "") for c in (content or []) if isinstance(c, dict) and c.get("type") == "text")
    return texts[-1] if texts else ""


def main() -> None:
    try:
        data = json.load(sys.stdin)
    except Exception:
        return
    ev = data.get("hook_event_name", "")
    if ev == "UserPromptSubmit":
        print("【必須】返答はすべて日本語で書く。英語の文章で返答しない（コード・ファイル名・固有名詞を除く）。「その通りです」「おっしゃる通りです」などの同意の決まり文句は使わない。送る前に確認する。")
        return
    if ev == "PreToolUse":
        t = latest_text_since_user(data.get("transcript_path", ""))
        if t and (is_english(t) or BANNED.search(clean(t))):
            sys.stderr.write("直前に書いた文が英語、または「その通り」などの決まり文句になっています。道具を使う前に、同じ内容を日本語で（決まり文句なしで）書き直してから続けてください。")
            sys.exit(2)
        return
    if ev == "Stop":
        if data.get("stop_hook_active"):
            return
        text = last_assistant_text(data)
        if BANNED.search(clean(text or "")):
            print(json.dumps({
                "decision": "block",
                "reason": "直前の返答に「その通り」「おっしゃる通り」などの決まり文句が入っています。ユーザーはこれを強く嫌がっています。この言い回しを使わずに書き直して、改めて返答してください。",
            }, ensure_ascii=False))
            return
        if is_english(text):
            print(json.dumps({
                "decision": "block",
                "reason": "直前の返答が英語になっています。ユーザーは英語の返答を強く嫌がっています。同じ内容を日本語で書き直して、改めて返答してください。",
            }, ensure_ascii=False))
        return


if __name__ == "__main__":
    main()
