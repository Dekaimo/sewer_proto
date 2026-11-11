extends Node2D
## 試作：下水道の汚れ・拘束・連携の仕組みを確認するためのシーン
## 絵は仮（四角形）。PixelLabの素材ができたら Sprite に差し替える。

const PlayerScript = preload("res://player.gd")
const EnemyScript = preload("res://enemy.gd")
const HudScript = preload("res://hud.gd")
const SfxScript = preload("res://sfx.gd")
const FloorShader = preload("res://floor.gdshader")

const VIEW_W := 960.0
const VIEW_H := 540.0
const FLOOR_TOP := 430.0   # 壁と床の境目
const FLOOR_Y := 488.0     # 足元の線（床の奥行きの中ほど）
const ARENA_L := 30.0
const ARENA_R := 930.0

var player
var sfx
var enemies: Array = []
var floor_splats: Array = []   # {x, w}
var token_holder = null        # 同時に攻撃できる敵は1体だけ（攻撃権トークン）
var game_over := false
var survive_time := 0.0
var splat_layer: Node2D


func _ready() -> void:
	randomize()
	_setup_input()
	sfx = SfxScript.new()
	add_child(sfx)
	# ペンキまみれの床（シェーダー）
	var fl := ColorRect.new()
	fl.position = Vector2(0, FLOOR_TOP)
	fl.size = Vector2(VIEW_W, VIEW_H - FLOOR_TOP)
	var fm := ShaderMaterial.new()
	fm.shader = FloorShader
	fm.set_shader_parameter("size", fl.size)
	fl.material = fm
	fl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fl)
	splat_layer = Node2D.new()
	splat_layer.draw.connect(_draw_splats)
	add_child(splat_layer)
	player = PlayerScript.new()
	player.main = self
	player.position = Vector2(300, FLOOR_Y)
	player.z_index = 2
	add_child(player)
	for x in [760.0]:   # ペンキワニは1体（2体目は別の敵として後で追加）
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


func on_player_defeated(grabber) -> void:
	game_over = true
	# とどめ演出：掴んでいた敵（いなければ一番近い敵）が抱えて沈む
	var e = grabber
	if e == null or not is_instance_valid(e):
		for c in enemies:
			if e == null or absf(c.position.x - player.position.x) < absf(e.position.x - player.position.x):
				e = c
	if e != null:
		e.play_swallow(player)


# ---------- 床の汚れ ----------
func add_floor_splat(x: float, w: float) -> void:
	floor_splats.append({"x": clampf(x, ARENA_L, ARENA_R), "w": w})
	if floor_splats.size() > 60:
		floor_splats.pop_front()
	splat_layer.queue_redraw()


func clean_floor(x0: float, x1: float) -> int:
	var before := floor_splats.size()
	floor_splats = floor_splats.filter(func(s): return s.x + s.w * 0.5 < x0 or s.x - s.w * 0.5 > x1)
	splat_layer.queue_redraw()
	return before - floor_splats.size()


func splat_under(x: float) -> bool:
	for s in floor_splats:
		if absf(s.x - x) < s.w * 0.5:
			return true
	return false


# ---------- 背景 ----------
func _draw() -> void:
	draw_rect(Rect2(0, 0, VIEW_W, FLOOR_TOP), Color("1b1f24"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	# レンガ
	for row in range(0, 20):
		var y := 30 + row * 21
		if y > FLOOR_TOP:
			break
		var off := 0 if row % 2 == 0 else 18
		for col in range(-1, 28):
			draw_rect(Rect2(col * 36 + off, y, 34, minf(19, FLOOR_TOP - y)), Color("262c33"))
	# 壁のペンキ染み（にじみ＋垂れ）
	for i in 12:
		var cx := rng.randf_range(0, VIEW_W)
		var cy := rng.randf_range(130, FLOOR_TOP - 60)
		var col := Color("8a2f5f") if rng.randf() < 0.75 else Color("8f7c2c")
		col.a = 0.45
		for k in 4:
			draw_circle(Vector2(cx + rng.randf_range(-18, 18), cy + rng.randf_range(-6, 6)), rng.randf_range(6, 14), col)
		for k in rng.randi_range(2, 4):
			var dx := cx + rng.randf_range(-16, 16)
			var dl := rng.randf_range(10, 70)
			draw_rect(Rect2(dx - 1.5, cy, 3, dl), col)
			draw_circle(Vector2(dx, cy + dl), 3.0, col)
	# 床際にたまったペンキ
	for i in 30:
		var col2 := Color("6e2650")
		col2.a = 0.6
		draw_circle(Vector2(rng.randf_range(0, VIEW_W), FLOOR_TOP - rng.randf_range(0, 6)), rng.randf_range(6, 18), col2)
	# 配管と、そこから垂れるペンキ
	draw_rect(Rect2(0, 80, VIEW_W, 12), Color("3a4148"))
	draw_rect(Rect2(0, 81, VIEW_W, 2), Color("525b63"))
	for i in 22:
		var x := rng.randf_range(0, VIEW_W)
		var dl := rng.randf_range(8, 120)
		var c2 := Color("ec5a9e") if rng.randf() < 0.75 else Color("f9d84d")
		draw_rect(Rect2(x, 92, rng.randf_range(2, 6), dl), c2)
		draw_rect(Rect2(x - 1, 92 + dl, 6, 5), c2)
	# 床との境目の影
	draw_rect(Rect2(0, FLOOR_TOP - 6, VIEW_W, 6), Color(0, 0, 0, 0.35))


# 戦闘中に増える床のペンキ（床シェーダーの上に描く）
func _draw_splats() -> void:
	for s in floor_splats:
		var c := Vector2(s.x, FLOOR_Y + 2)
		splat_layer.draw_set_transform(c, 0.0, Vector2(1.0, 0.28))
		splat_layer.draw_circle(Vector2.ZERO, s.w * 0.55, Color("b8357a"))
		splat_layer.draw_circle(Vector2(0, -4), s.w * 0.45, Color("ec5a9e"))
		splat_layer.draw_circle(Vector2(s.w * 0.12, -8), s.w * 0.12, Color("f9d84d"))
	splat_layer.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
