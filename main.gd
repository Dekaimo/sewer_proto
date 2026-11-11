extends Node2D
## 試作：下水道の汚れ・拘束・連携の仕組みを確認するためのシーン
## 絵は仮（四角形）。PixelLabの素材ができたら Sprite に差し替える。

const PlayerScript = preload("res://player.gd")
const EnemyScript = preload("res://enemy.gd")
const HudScript = preload("res://hud.gd")
const SfxScript = preload("res://sfx.gd")

const FLOOR_Y := 150.0
const ARENA_L := 10.0
const ARENA_R := 310.0

var player
var sfx
var enemies: Array = []
var floor_splats: Array = []   # {x, w}
var token_holder = null        # 同時に攻撃できる敵は1体だけ（攻撃権トークン）
var game_over := false
var survive_time := 0.0


func _ready() -> void:
	randomize()
	_setup_input()
	sfx = SfxScript.new()
	add_child(sfx)
	player = PlayerScript.new()
	player.main = self
	player.position = Vector2(160, FLOOR_Y)
	add_child(player)
	for x in [50.0, 280.0]:
		var e = EnemyScript.new()
		e.main = self
		e.position = Vector2(x, FLOOR_Y)
		add_child(e)
		enemies.append(e)
	var hud = HudScript.new()
	hud.main = self
	hud.z_index = 10
	add_child(hud)


func _process(delta: float) -> void:
	if game_over:
		if Input.is_action_just_pressed("restart"):
			get_tree().reload_current_scene()
		return
	survive_time += delta


# ---------- 入力 ----------
func _setup_input() -> void:
	_add_keys("left", [KEY_LEFT, KEY_A])
	_add_keys("right", [KEY_RIGHT, KEY_D])
	_add_keys("jump", [KEY_UP, KEY_W, KEY_SPACE])
	_add_keys("attack", [KEY_Z, KEY_J])
	_add_keys("clean", [KEY_X, KEY_K])
	_add_keys("restart", [KEY_R])


func _add_keys(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


# ---------- 敵の連携（ディレクター） ----------
func request_token(e) -> bool:
	if token_holder == null or not is_instance_valid(token_holder):
		token_holder = e
		return true
	return token_holder == e


func release_token(e) -> void:
	if token_holder == e:
		token_holder = null


func holding_enemy():
	for e in enemies:
		if e.state == "hold":
			return e
	return null


func on_player_defeated() -> void:
	game_over = true


# ---------- 床の汚れ ----------
func add_floor_splat(x: float, w: float) -> void:
	floor_splats.append({"x": clampf(x, ARENA_L, ARENA_R), "w": w})
	if floor_splats.size() > 60:
		floor_splats.pop_front()
	queue_redraw()


func clean_floor(x0: float, x1: float) -> int:
	var before := floor_splats.size()
	floor_splats = floor_splats.filter(func(s): return s.x + s.w * 0.5 < x0 or s.x - s.w * 0.5 > x1)
	queue_redraw()
	return before - floor_splats.size()


func splat_under(x: float) -> bool:
	for s in floor_splats:
		if absf(s.x - x) < s.w * 0.5:
			return true
	return false


# ---------- 背景 ----------
func _draw() -> void:
	draw_rect(Rect2(0, 0, 320, 180), Color("1b1f24"))
	# レンガ
	for row in range(0, 9):
		var y := 10 + row * 14
		var off := 0 if row % 2 == 0 else 12
		for col in range(-1, 14):
			draw_rect(Rect2(col * 24 + off, y, 23, 13), Color("262c33"))
	# 配管
	draw_rect(Rect2(0, 30, 320, 6), Color("3a4148"))
	draw_rect(Rect2(0, 31, 320, 1), Color("525b63"))
	# 床
	draw_rect(Rect2(0, FLOOR_Y, 320, 30), Color("30363c"))
	draw_rect(Rect2(0, FLOOR_Y, 320, 1), Color("4b545c"))
	# 水路
	draw_rect(Rect2(0, 166, 320, 14), Color("1d3a3a"))
	draw_rect(Rect2(0, 166, 320, 1), Color("2f5b58"))
	# 床のペンキ
	for s in floor_splats:
		var x0 = s.x - s.w * 0.5
		draw_rect(Rect2(x0, FLOOR_Y - 1, s.w, 3), Color("ec5a9e"))
		draw_rect(Rect2(x0 + s.w * 0.3, FLOOR_Y, s.w * 0.3, 1), Color("f9d84d"))
