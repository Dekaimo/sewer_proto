extends Node2D
## タイトル → ステージ選択 / ギャラリー（仮実装）。
## 操作：↑↓（W S）で選ぶ、Z / Enter / Space で決定、X / Esc で戻る。マウス・タッチは項目をそのまま押す。

const GameState = preload("res://game_state.gd")
const Gallery = preload("res://gallery.gd")

const PINK := Color("ec5a9e")
const PALE := Color("f4b6d4")
const GREY := Color("aab3ba")
const LIST_X := 36.0
const LIST_W := 372.0
const ROW_H := 46.0
const PANEL := Rect2(430, 14, 512, 512)   # 右側の見本を出す枠
const BACK_RECT := Rect2(36, 480, 150, 40)

var screen := "title"
var sel := 0
var t := 0.0
var font: Font
var cfg: ConfigFile
var tex_cache := {}
var title_sel := 0     # タイトルに戻ったとき、元の項目に合わせる
var stage_sel := 0


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	Engine.time_scale = 1.0
	font = GameState.font()
	cfg = Gallery.load_cfg()
	if DisplayServer.is_touchscreen_available():
		get_tree().root.content_scale_stretch = Window.CONTENT_SCALE_STRETCH_FRACTIONAL
	for i in GameState.STAGES.size():
		if GameState.STAGES[i].id == GameState.stage:
			stage_sel = i


func _process(delta: float) -> void:
	t += delta
	queue_redraw()


# ---------- 項目 ----------
func _count() -> int:
	match screen:
		"title": return 2
		"stage": return GameState.STAGES.size()
		_: return Gallery.ENTRIES.size()


func _row_rect(i: int) -> Rect2:
	if screen == "title":
		return Rect2(330, 384 + i * 56.0, 300, 48)
	return Rect2(LIST_X, 84 + i * ROW_H, LIST_W, ROW_H - 6.0)


func _go(to: String) -> void:
	if screen == "title":
		title_sel = sel
	elif screen == "stage":
		stage_sel = sel
	screen = to
	sel = title_sel if to == "title" else (stage_sel if to == "stage" else 0)
	if to == "gallery":
		cfg = Gallery.load_cfg()


func _confirm() -> void:
	match screen:
		"title":
			_go("stage" if sel == 0 else "gallery")
		"stage":
			GameState.stage = GameState.STAGES[sel].id
			get_tree().change_scene_to_file(GameState.MAIN_SCENE)


func _back() -> void:
	if screen != "title":
		_go("title")


# ---------- 入力 ----------
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_UP, KEY_W:
				sel = posmod(sel - 1, _count())
			KEY_DOWN, KEY_S:
				sel = posmod(sel + 1, _count())
			KEY_Z, KEY_J, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				_confirm()
			KEY_X, KEY_K, KEY_ESCAPE, KEY_BACKSPACE:
				_back()
	elif event is InputEventMouseMotion:
		var i := _row_at(make_input_local(event).position)
		if i >= 0:
			sel = i
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_press_at(make_input_local(event).position)
	elif event is InputEventScreenTouch and event.pressed:
		_press_at(make_input_local(event).position)


func _row_at(p: Vector2) -> int:
	for i in _count():
		if _row_rect(i).has_point(p):
			return i
	return -1


func _press_at(p: Vector2) -> void:
	if screen != "title" and BACK_RECT.has_point(p):
		_back()
		return
	var i := _row_at(p)
	if i >= 0:
		sel = i
		_confirm()


# ---------- 描画 ----------
func _tex(path: String) -> Texture2D:
	if not tex_cache.has(path):
		tex_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return tex_cache[path]


func _txt(pos: Vector2, s: String, col := Color.WHITE, size := 16) -> void:
	draw_string(font, pos + Vector2(2, 2), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, 0.6))
	draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _txt_c(cx: float, y: float, s: String, col := Color.WHITE, size := 16) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	_txt(Vector2(round(cx - w * 0.5), y), s, col, size)


func _draw() -> void:
	_draw_bg()
	match screen:
		"title": _draw_title()
		"stage": _draw_stage()
		_: _draw_gallery()


func _draw_bg() -> void:
	draw_rect(Rect2(0, 0, 960, 540), Color("1b1f24"))
	for row in 26:
		var y := row * 21
		var off := 0 if row % 2 == 0 else 18
		for col in range(-1, 28):
			draw_rect(Rect2(col * 36 + off, y, 34, 19), Color("22272d"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	draw_rect(Rect2(0, 0, 960, 10), Color("7d3a5c"))
	for i in 26:
		var x := rng.randf_range(0, 960)
		var dl := rng.randf_range(10, 90) + sin(t * 0.6 + i) * 4.0
		var c := Color("7d3a5c") if rng.randf() < 0.75 else Color("847334")
		draw_rect(Rect2(x, 8, rng.randf_range(3, 7), dl), c)
		draw_rect(Rect2(x - 1, 8 + dl, 7, 5), c)


func _draw_row(i: int, label: String, col := Color.WHITE, center := false) -> void:
	var r := _row_rect(i)
	var on := i == sel
	draw_rect(r, Color(0.93, 0.35, 0.62, 0.30) if on else Color(0, 0, 0, 0.35))
	if on:
		draw_rect(Rect2(r.position, Vector2(4, r.size.y)), PINK)
	var y := r.position.y + r.size.y * 0.5 + 6.0
	if center:
		_txt_c(r.position.x + r.size.x * 0.5, y, label, col, 16)
	else:
		_txt(Vector2(r.position.x + 14, y), label, col, 16)


func _draw_back() -> void:
	draw_rect(BACK_RECT, Color(0, 0, 0, 0.45))
	_txt(BACK_RECT.position + Vector2(14, 26), "もどる (X)", GREY, 16)


func _draw_title() -> void:
	_txt_c(480, 96, "げすいどう おそうじゲー", PINK, 48)
	_txt_c(480, 128, "- しさくばん -", PALE, 16)
	# 主人公（待機のコマ）を2倍で
	var cat := _tex("res://assets/cat_idle_%d.png" % (int(t * 5.0) % 4))
	if cat == null:
		cat = _tex("res://assets/cat_idle_0.png")
	if cat != null:
		draw_texture_rect(cat, Rect2(480 - 128, 132, 256, 256), false)
	_draw_row(0, "はじめる", Color.WHITE, true)
	_draw_row(1, "ギャラリー  %d / %d" % [Gallery.collected(), Gallery.ENTRIES.size()], Color.WHITE, true)
	_txt_c(480, 522, "W S / やじるし : えらぶ    Z / Enter : けってい    X / Esc : もどる", GREY, 16)


func _draw_panel() -> void:
	draw_rect(PANEL, Color(0, 0, 0, 0.5))
	draw_rect(PANEL, Color("3a4148"), false, 2.0)


func _draw_stage() -> void:
	_txt(Vector2(LIST_X, 54), "ステージを えらぶ", PINK, 32)
	for i in GameState.STAGES.size():
		_draw_row(i, GameState.STAGES[i].name)
	_draw_back()
	_draw_panel()
	var s: Dictionary = GameState.STAGES[sel]
	# 出てくる敵を並べる
	var icons: Array = []
	if s.wani: icons.append("res://assets/wani_idle.png")
	if s.dobe: icons.append("res://assets/dobe_idle.png")
	if s.shark: icons.append("res://assets/same_base.png")
	var n := icons.size()
	var k_scale := 0.5 if n >= 3 else 1.0   # 3体は並びきらないので半分の大きさで
	var total := 0.0
	for p in icons:
		var tx0 := _tex(p)
		total += tx0.get_size().x * k_scale if tx0 != null else 0.0
	var x := PANEL.position.x + (PANEL.size.x - total) * 0.5
	for k in n:
		var tx := _tex(icons[k])
		if tx == null:
			continue
		var sz := tx.get_size() * k_scale
		var bob := roundf(sin(t * 2.0 + k * 1.7) * 3.0)
		draw_texture_rect(tx, Rect2(roundf(x), PANEL.position.y + 330.0 - sz.y + bob, sz.x, sz.y), false)
		x += sz.x
	_txt_c(PANEL.get_center().x, PANEL.position.y + 400, s.name, Color.WHITE, 32)
	_txt_c(PANEL.get_center().x, PANEL.position.y + 436, s.sub, PALE, 16)
	_txt_c(PANEL.get_center().x, PANEL.position.y + 486, "たえられるだけ たえる。クリアは まだ ない", GREY, 16)


func _draw_gallery() -> void:
	_txt(Vector2(LIST_X, 54), "ギャラリー", PINK, 32)
	_txt(Vector2(LIST_X + 190, 54), "%d / %d" % [Gallery.collected(), Gallery.ENTRIES.size()], GREY, 16)
	for i in Gallery.ENTRIES.size():
		var e: Dictionary = Gallery.ENTRIES[i]
		var seen: bool = cfg.get_value("seen", e.id, false)
		_draw_row(i, e.name if seen else "？？？", Color.WHITE if seen else GREY)
	_draw_back()
	_draw_panel()
	var e: Dictionary = Gallery.ENTRIES[sel]
	var seen: bool = cfg.get_value("seen", e.id, false)
	var tx := _tex("res://assets/%s_%d.png" % [e.frames, int(t * e.fps) % int(e.n)])
	if tx != null:
		# まだ見ていない負け方は影だけ
		draw_texture_rect(tx, Rect2(PANEL.position.x, PANEL.position.y - 30, 512, 512), false, Color.WHITE if seen else Color(0, 0, 0, 0.85))
	draw_rect(Rect2(PANEL.position.x + 2, PANEL.end.y - 62, PANEL.size.x - 4, 60), Color(0, 0, 0, 0.6))
	if seen:
		_txt_c(PANEL.get_center().x, PANEL.end.y - 36, e.name, Color.WHITE, 16)
		_txt_c(PANEL.get_center().x, PANEL.end.y - 12, "%s    やられた かいすう %d" % [e.who, int(cfg.get_value("count", e.id, 0))], PALE, 16)
	else:
		_txt_c(PANEL.get_center().x, PANEL.end.y - 36, "？？？", GREY, 16)
		_txt_c(PANEL.get_center().x, PANEL.end.y - 12, "あいて : %s" % e.who, GREY, 16)
