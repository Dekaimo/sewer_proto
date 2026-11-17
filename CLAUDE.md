# 下水道お掃除ゲー（sewer_proto）— 作業を始める前に読む

Godot 4.3 の 2D ドット絵アクション。主人公（黒猫）が下水道のペンキの魔物に捕まって汚されながら抗うゲーム。
ルールの本体は claude.ai のプロジェクト「下水道お掃除ｹﾞｰ」のドキュメント（`claude/制作ルール（全キャラ共通）.md`、キャラ別の仕様メモ）。**作業前に必ず読む。**

## 絶対の決まり（全文はプロジェクトの制作ルール「生成と素材（最優先）」。ここは要点）
- **生成はユーザーが「回して」と言ってから。** 回す前にプロンプト全文・参考画像（どの画像を、どの大きさ・形式で）・回数・消費を見せて待つ。質問への答えを許可とみなさない。
- **1回ずつ**（ジョブに `variants` を書かない。gen なら4枚・15回分）。2回以上まとめるのはユーザーが頼んだときだけ。
- **ユーザーが貼った画像は劣化させない**（縮小・JPEG化・減色・ぼかしをしない）。PixelLab の参考画像は元の画像のまま渡せる（1024pxを超える分は PixelLab 側で縮める）ので、こちらで縮めない。入力の文字数などの制限でどうしても落とす時は、何をどれだけ落とすかを先に言って許可を取る。
- 前回うまくいった条件は黙って変えない。参考画像から分からない所（服など）は自分で決めずに聞く。
- 目・口・粘液を手打ちのドットで描き足さない（透明の穴を塗る・浮いたかけらを消す程度だけ可）。

## 返答
- 日本語だけ。「その通りです」「おっしゃる通りです」などの決まり文句は使わない（`.claude/settings.json` のフックでも止める）。

## 構成
- `main.gd` 全体・カメラ（`zoom_moment`）／`player.gd` 主人公（状態：normal / grabbed / held / crucified / swallowed / engulfed / pinned / defeated）
- `enemy.gd` ペンキワニ。磔は `_cru2_update`（素材 `assets/cru2/`、柱だけ `cru_bend.gdshader` でしならせ、上の群れ `cru2_up` が乗って傾く）
- `doberman.gd` ペンキドーベルマン（待ち伏せ・羽交い締め・ヒップドロップ・磔に便乗 `sandwich`：form → tease（押し合いっこ）→ hug（擦りつけ／ペンキを飲ませる））
- `shark.gd` ペンキサメ／`belly_view.gd` 地中の小窓／`voice.gd` 捕まっている間のフキダシ／`touch_ui.gd`・`web/mobile.js` スマホ操作
- `sfx.gd` 効果音（`sfx/<名前>/`）

## 絵の作り方（PixelLab、GitHub Actions）
- ジョブ投入：`gh api -X POST repos/Dekaimo/sewer_proto/actions/workflows/pixellab_anim.yml/dispatches -f ref=main -f "inputs[jobs]=$JOBS"` → `gh run watch` → `git pull`
- 出力：`assets_raw/gen/<名前>/<時刻>/v1_0N.png`（raw_ は背景つき）。mode：anim（src/last、8コマ）・editv2（src、白背景）・gen・skel
- 後処理（毎コマ）：`tools/fill_holes.py 入力 raw 出力` → `tools/hue_fix.py`（色ずれ）→ `tools/fill_small_holes.py`
- editv2 は白い所（白目など）が背景と一緒に抜けることがある → raw の色で戻す
- 1回分の候補の中から、動き（何ドット動くか）・コマ間の差・ガタつきを数値で測って選ぶ。見せる前にゲームと同じ重ね方で合成して確認する。

## 確認
- Web：push で `web.yml` が書き出して https://dekaimo.github.io/sewer_proto/ に公開。ログの「SCRIPT ERROR / Parse Error」が 0 件か見る。
- 画面なしの動作確認：`smoke.yml`（inputs.solo：0 / 1 / shark / hd / hds / cru）
- 効果音：`tools/gen_sfx.py` の文言 → `gen_sfx.yml`（inputs.only）。既にある音は飛ばすので、作り直すときは `sfx/<名前>/` を消してから。

## コミット
メッセージの最後に、その会話で指定された Co-Authored-By / Claude-Session の行を付ける。
