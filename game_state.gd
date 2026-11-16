extends RefCounted
## 画面をまたいで持ち越すもの（選んだステージ）と、メニュー共通の文字。
## main.tscn を直接開いたとき（動作確認など）は stage = "all" のまま＝全部の敵が出る。

const FONT_PATH := "res://fonts/dotgothic16_kana.ttf"   # かなと英数字だけ（漢字は入っていない）
const MENU_SCENE := "res://menu.tscn"
const MAIN_SCENE := "res://main.tscn"

## ステージ：どの敵が出るか。icons は選択画面に並べる絵
const STAGES := [
	{"id": "wani", "name": "ペンキワニ", "sub": "つかまれる・のみこまれる・はりつけ", "wani": true, "dobe": false, "shark": false},
	{"id": "dobe", "name": "ペンキドーベルマン", "sub": "まちぶせ・はがいじめ・ヒップドロップ", "wani": false, "dobe": true, "shark": false},
	{"id": "shark", "name": "ペンキサメ", "sub": "ゆかの したから まるのみ", "wani": false, "dobe": false, "shark": true},
	{"id": "wani_dobe", "name": "ワニ と ドーベルマン", "sub": "はりつけに びんじょう・サンドイッチ", "wani": true, "dobe": true, "shark": false},
	{"id": "all", "name": "ぜんぶ", "sub": "3たい そろって おそってくる", "wani": true, "dobe": true, "shark": true},
]

static var stage := "all"
static var _font: Font


static func stage_info() -> Dictionary:
	for s in STAGES:
		if s.id == stage:
			return s
	return STAGES[STAGES.size() - 1]


static func font() -> Font:
	if _font == null:
		if ResourceLoader.exists(FONT_PATH):
			var f = load(FONT_PATH)
			if f is FontFile:
				f.antialiasing = TextServer.FONT_ANTIALIASING_NONE
				f.hinting = TextServer.HINTING_NONE
				f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
			_font = f
		if _font == null:
			_font = ThemeDB.fallback_font
	return _font


## ゲームオーバー画面のボタン（HUD が描き、マウスとタッチの両方から押せる）
const OVER_BUTTONS := [
	{"action": "restart", "label": "もういちど (R)", "rect": Rect2(250, 452, 220, 48)},
	{"action": "menu", "label": "タイトルへ (Esc)", "rect": Rect2(490, 452, 220, 48)},
]


static func over_button_at(p: Vector2) -> String:
	for b in OVER_BUTTONS:
		if b.rect.has_point(p):
			return b.action
	return ""
