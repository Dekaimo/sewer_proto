extends Node2D
## 捕まっている間の主人公のうめき声・くぐもった声をフキダシで出す。
## しゃべらせるのではなく、短いうめき・息・口をふさがれた声だけ。

const FONT_PATH := "res://fonts/dotgothic16_kana.ttf"
const FONT_SIZE := 16
const SHOW_T := 1.3          # 1回の表示時間
const POP_T := 0.08          # ポンと出る時間
const FADE_T := 0.25         # 消えていく時間

## 場面ごとのセリフ。muffled=口がふさがれている（フキダシをくぐもらせ、文字を小刻みに震わせる）
const LINES := {
	"caught": {"t": ["ひゃっ…！", "わっ…！", "ひぅ…っ"], "muffled": false, "gap": [1.2, 2.0]},
	"grabbed": {"t": ["く…っ", "ん…っ！", "うぅ…", "ふぬ…っ", "は、はなし…っ"], "muffled": false, "gap": [1.8, 3.4]},
	"rise": {"t": ["わ、わっ…！", "ひっ…"], "muffled": false, "gap": [1.5, 2.5]},
	"startle": {"t": ["ひっ…", "え…っ"], "muffled": false, "gap": [1.0, 1.5]},
	"cru": {"t": ["うぅ…", "く…っ", "ん…っ"], "muffled": false, "gap": [2.2, 4.0]},
	"push": {"t": ["んん…っ", "く…ぅ…", "や…っ", "ふぬぬ…"], "muffled": false, "gap": [1.4, 2.6]},
	"rub": {"t": ["うぅ…", "ひぅ…", "や…め…っ", "んぅ…"], "muffled": false, "gap": [1.8, 3.2]},
	"drink": {"t": ["んぐっ…", "んむぅ…！", "んくっ…", "むー…っ"], "muffled": true, "gap": [1.2, 2.4]},
	"muffled": {"t": ["むぐ…っ", "んむ…！", "んんっ…！", "ん…ぅ…"], "muffled": true, "gap": [1.8, 3.2]},
	"under": {"t": ["～～～！！！", "～～～っ！！", "～～っ…！", "～～～…！"], "muffled": true, "gap": [1.4, 2.8]},
	"faint": {"t": ["…ぅ…", "…ぁ…", "……"], "muffled": true, "gap": [5.0, 9.0]},
	"free": {"t": ["ぷはっ…！", "はぁ…はぁ…"], "muffled": false, "gap": [99.0, 99.0]},
}

var main
var font: Font
var text := ""
var muffled := false
var t := 0.0            # 表示中の経過時間（-1 = 表示していない）
var cool := 0.0         # 次に声を出すまで
var ctx := ""
var anchor := Vector2.ZERO    # 主人公の頭の位置（ワールド座標）
var last_line := ""
var side := 0           # 0=頭の上に出す / 1=右横 / -1=左横（磔：ワニの顔を隠さないように、主人公の頭の横に出す）


func _ready() -> void:
	z_as_relative = false
	z_index = 4000
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if ResourceLoader.exists(FONT_PATH):
		var f = load(FONT_PATH)
		if f is FontFile:
			f.antialiasing = TextServer.FONT_ANTIALIASING_NONE
			f.hinting = TextServer.HINTING_NONE
			f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
		font = f
	if font == null:
		font = ThemeDB.fallback_font
	t = -1.0


func _context(p) -> String:
	match p.state:
		"grabbed", "held":
			return "grabbed"
		"crucified":
			var w = p.crucifier
			if w != null and is_instance_valid(w) and "cru2_phase" in w and w.cru2_phase != "":
				return w.cru2_phase
			return "cru"
		"swallowed":
			return "under"     # 地面の中（呑まれて地中を引き回される）：声にならない
		"engulfed", "pinned":
			return "muffled"
		"defeated":
			return "faint"
	return ""


func _head(p) -> Vector2:
	side = 0
	if p.state == "crucified" or (p.state == "defeated" and p.crucifier != null):
		var w = p.crucifier
		if w != null and is_instance_valid(w) and w.has_method("cru2_on") and w.cru2_on() and w.cru2_cat != null:
			var h: Vector2 = w.cru2_cat.to_global(Vector2(92, 30))
			side = 1 if h.x > w.cru2_cat.to_global(Vector2(30, 30)).x else -1
			return h
	if p.state == "swallowed" and p.swallower != null and is_instance_valid(p.swallower):
		return p.swallower.position + Vector2(0, -90)
	if p.state == "engulfed":
		return p.position + Vector2(0, -70)
	if p.state == "pinned" or p.trio_finish:
		return p.position + Vector2(0, -95)
	if p.state == "defeated":
		return anchor
	return p.position + Vector2(0, -p.z - 104)


func say(kind: String) -> void:
	var d: Dictionary = LINES[kind]
	var arr: Array = d["t"]
	var s: String = arr[randi() % arr.size()]
	if s == last_line and arr.size() > 1:
		s = arr[(arr.find(s) + 1) % arr.size()]
	text = s
	last_line = s
	muffled = d["muffled"]
	t = 0.0
	cool = SHOW_T + randf_range(d["gap"][0], d["gap"][1])


func _process(delta: float) -> void:
	var p = main.player
	if p == null:
		return
	var c := _context(p)
	if c != ctx:
		var was := ctx
		ctx = c
		if c == "" and was != "" and was != "faint" and p.state == "normal":
			say("free")            # 抜け出した
		elif c == "grabbed" and was == "":
			say("caught")          # 捕まった瞬間
		elif c != "" and c != "faint":
			cool = minf(cool, randf_range(0.2, 0.6))   # 場面が変わったら、すぐ一声
		elif c == "faint":
			cool = 1.5
	cool -= delta
	if ctx != "" and cool <= 0.0:
		say(ctx)
	if t >= 0.0:
		t += delta
		if t > SHOW_T:
			t = -1.0
	anchor = _head(p)
	queue_redraw()


func _draw() -> void:
	if t < 0.0 or text == "":
		return
	var a := 1.0
	if t > SHOW_T - FADE_T:
		a = clampf((SHOW_T - t) / FADE_T, 0.0, 1.0)
	var pop := clampf(t / POP_T, 0.0, 1.0)
	var ts := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
	var pad := Vector2(6, 4)
	var size := (ts + pad * 2.0).round()
	# 頭の右上に出す（画面の右端に近ければ左上）。磔では頭の横に出す
	var right: bool = anchor.x < main.VIEW_W - size.x - 40.0
	var box_pos: Vector2
	if side != 0:
		right = side > 0
		box_pos = anchor + (Vector2(14, -size.y * 0.5) if right else Vector2(-14 - size.x, -size.y * 0.5))
	else:
		box_pos = anchor + (Vector2(16, -size.y - 20) if right else Vector2(-16 - size.x, -size.y - 20))
	box_pos.y = maxf(box_pos.y, 4.0)
	# ポンと膨らむ（小さい所から）
	var center := box_pos + size * 0.5
	var sc := lerpf(0.55, 1.0, pop)
	var r := Rect2((center - size * 0.5 * sc).round(), (size * sc).round())
	var line_col := Color(0.12, 0.08, 0.14, a)
	var fill := Color(1.0, 0.97, 0.98, 0.95 * a) if not muffled else Color(0.93, 0.86, 0.9, 0.92 * a)
	# しっぽ（頭へ向かう三角）。頭の上なら下の辺から、横なら頭側の辺から出す
	var tip: Vector2
	var b0: Vector2
	var b1: Vector2
	if side != 0:
		var ex: float = r.position.x if right else r.end.x - 1.0
		var cy: float = roundf(r.position.y + r.size.y * 0.5)
		b0 = Vector2(ex, cy - 4)
		b1 = Vector2(ex, cy + 3)
		tip = (anchor + Vector2(2 if right else -2, 2)).round()
	else:
		var bx: float = r.position.x + (10.0 if right else r.size.x - 10.0)
		b0 = Vector2(bx - 4, r.end.y - 1)
		b1 = Vector2(bx + 4, r.end.y - 1)
		tip = (anchor + Vector2(6 if right else -6, -6)).round()
	draw_colored_polygon(PackedVector2Array([b0, b1, tip]), fill)
	draw_line(b0, tip, line_col, 1.0)
	draw_line(b1, tip, line_col, 1.0)
	# 本体：角を1ドット落とした四角
	var x0 := r.position.x
	var y0 := r.position.y
	var x1 := r.end.x
	var y1 := r.end.y
	draw_rect(Rect2(x0 + 1, y0, r.size.x - 2, r.size.y), fill)
	draw_rect(Rect2(x0, y0 + 1, r.size.x, r.size.y - 2), fill)
	if muffled:
		# くぐもった声：ふちをガタガタの線にする
		var i := 0.0
		while i < r.size.x - 2:
			var o: float = 1.0 if int(i / 3.0) % 2 == 0 else 0.0
			draw_rect(Rect2(x0 + 1 + i, y0 - o, 3, 1), line_col)
			draw_rect(Rect2(x0 + 1 + i, y1 - 1 + o, 3, 1), line_col)
			i += 3.0
		draw_rect(Rect2(x0, y0 + 1, 1, r.size.y - 2), line_col)
		draw_rect(Rect2(x1 - 1, y0 + 1, 1, r.size.y - 2), line_col)
	else:
		draw_rect(Rect2(x0 + 1, y0, r.size.x - 2, 1), line_col)
		draw_rect(Rect2(x0 + 1, y1 - 1, r.size.x - 2, 1), line_col)
		draw_rect(Rect2(x0, y0 + 1, 1, r.size.y - 2), line_col)
		draw_rect(Rect2(x1 - 1, y0 + 1, 1, r.size.y - 2), line_col)
	# しっぽの付け根のふちを消して、本体とつなげる
	if side != 0:
		draw_rect(Rect2(b0.x, b0.y + 1, 1, b1.y - b0.y - 1), fill)
	else:
		draw_rect(Rect2(b0.x + 1, b0.y, b1.x - b0.x - 1, 1), fill)
	if pop < 1.0:
		return
	# 文字（くぐもった声は小刻みに震える）
	var jit := Vector2.ZERO
	if muffled and int(t * 20.0) % 3 == 0:
		jit = Vector2(randi_range(-1, 1), 0)
	var tp := (r.position + pad + Vector2(0, font.get_ascent(FONT_SIZE)) + jit).round()
	draw_string(font, tp, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color(0.16, 0.1, 0.2, a))
