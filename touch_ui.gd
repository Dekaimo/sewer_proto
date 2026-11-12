extends Node2D
## スマホ用のタッチ操作。タッチ画面のときだけ出る。
## 左半分：どこを触ってもそこがスティックの中心（上下左右に移動。捕まったら左右に振ると連打になる）
## 右下：ボタン（ジャンプ／攻撃／拭く[押している間]）
## キーボードと同じ入力（left/right/up/down/jump/attack/clean）を押したことにするので、ゲーム側は変更不要。
## 捕まっている間は、画面のどこをタップしても「もがく」（左右の交互入力）になる。スティックを振るより楽。

const BTN := [
	{"action": "jump", "label": "JUMP", "pos": Vector2(866, 432), "r": 62.0},
	{"action": "attack", "label": "ATK", "pos": Vector2(736, 474), "r": 54.0},
	{"action": "clean", "label": "WIPE", "pos": Vector2(876, 284), "r": 48.0},
]
const DEAD := 18.0
const MAX_R := 70.0

var stick_id := -1
var stick_center := Vector2.ZERO
var stick_pos := Vector2.ZERO
var btn_touch := {}    # touch index -> action
var held := {}         # action -> true


func _ready() -> void:
	visible = DisplayServer.is_touchscreen_available()
	set_process_input(visible)


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		var p := _to_view(t.position)
		if t.pressed:
			# リトライ（ゲームオーバー画面）
			var main = get_parent().get_parent()
			if main.game_over and main.finisher_done():
				Input.action_press("restart")
				await get_tree().process_frame
				Input.action_release("restart")
				return
			# 捕まっている：どこをタップしても左右の交互入力（もがく）
			if _caught(main):
				# スティックを握ったまま捕まったら、スティックは離したことにする
				if stick_id >= 0:
					stick_id = -1
					_set_dirs(Vector2.ZERO)
				_mash()
				get_viewport().set_input_as_handled()
				return
			var hit := _button_at(p)
			if hit != "":
				btn_touch[t.index] = hit
				_press(hit)
			elif p.x < 480.0 and stick_id < 0:
				stick_id = t.index
				stick_center = p
				stick_pos = p
		else:
			if btn_touch.has(t.index):
				_release(btn_touch[t.index])
				btn_touch.erase(t.index)
			if t.index == stick_id:
				stick_id = -1
				_set_dirs(Vector2.ZERO)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == stick_id:
			stick_pos = _to_view(d.position)
			var v := stick_pos - stick_center
			if v.length() > MAX_R:
				stick_center = stick_pos - v.normalized() * MAX_R   # 指についてくる
			_set_dirs(stick_pos - stick_center)
		get_viewport().set_input_as_handled()


func _caught(main) -> bool:
	var p = main.player
	return p != null and not main.game_over and not (p.state in ["normal", "defeated"])


func _mash() -> void:
	# キー入力のふりをせず、主人公に直接「1回もがいた」と伝える（スティックの指とぶつからない）
	var main = get_parent().get_parent()
	main.player.touch_mash = mini(main.player.touch_mash + 1, 3)


func _to_view(screen_pos: Vector2) -> Vector2:
	# 画面の座標 → ゲームの 960x540 の座標
	return get_global_transform_with_canvas().affine_inverse() * screen_pos


func _button_at(p: Vector2) -> String:
	for b in BTN:
		if p.distance_to(b.pos) < b.r + 10.0:
			return b.action
	return ""


func _set_dirs(v: Vector2) -> void:
	_set_held("left", v.x < -DEAD)
	_set_held("right", v.x > DEAD)
	_set_held("up", v.y < -DEAD)
	_set_held("down", v.y > DEAD)


func _set_held(action: String, on: bool) -> void:
	if on and not held.get(action, false):
		_press(action)
	elif not on and held.get(action, false):
		_release(action)


func _press(action: String) -> void:
	held[action] = true
	Input.action_press(action)


func _release(action: String) -> void:
	held[action] = false
	Input.action_release(action)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if not visible:
		return
	# スティック
	if stick_id >= 0:
		draw_circle(stick_center, MAX_R, Color(1, 1, 1, 0.12))
		draw_arc(stick_center, MAX_R, 0, TAU, 32, Color(1, 1, 1, 0.35), 2.0)
		var k := (stick_pos - stick_center).limit_length(MAX_R)
		draw_circle(stick_center + k, 26.0, Color(1, 1, 1, 0.35))
	else:
		draw_string(ThemeDB.fallback_font, Vector2(40, 500), "drag here to move", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.35))
	var main = get_parent().get_parent()
	if _caught(main):
		draw_string(ThemeDB.fallback_font, Vector2(330, 120), "TAP TAP TAP!", HORIZONTAL_ALIGNMENT_LEFT, -1, 40, Color(1, 1, 1, 0.55 + 0.35 * sin(Time.get_ticks_msec() * 0.02)))
	# ボタン
	for b in BTN:
		var on: bool = held.get(b.action, false)
		draw_circle(b.pos, b.r, Color(1, 1, 1, 0.30 if on else 0.14))
		draw_arc(b.pos, b.r, 0, TAU, 32, Color(1, 1, 1, 0.5), 2.0)
		var w: float = b.label.length() * 9.0
		draw_string(ThemeDB.fallback_font, b.pos + Vector2(-w * 0.5, 6), b.label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.8))
