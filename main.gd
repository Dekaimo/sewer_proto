extends Node2D
## 試作：下水道の汚れ・拘束・連携・床のドロドロの仕組みを確認するシーン

const PlayerScript = preload("res://player.gd")
const EnemyScript = preload("res://enemy.gd")
const HudScript = preload("res://hud.gd")
const SfxScript = preload("res://sfx.gd")
const FloorShader = preload("res://floor.gdshader")
const WallShader = preload("res://wall_paint.gdshader")

const VIEW_W := 960.0
const VIEW_H := 540.0
const FLOOR_TOP := 430.0   # 壁と床の境目
const FLOOR_Y := 488.0     # 足元の線（床の奥行きの中ほど）
const ARENA_L := 30.0
const ARENA_R := 930.0

var player
var sfx
var enemies: Array = []
# 床のドロドロ（マリオサンシャインの「らくがき」風）。4pxごとの厚み 0〜1
const GOOP_CELL := 4.0
var goop := PackedFloat32Array()
var goop_img: Image
var goop_tex: ImageTexture
var goop_dirty := false
# 壁のペンキ（4pxごとの厚み）。時間とともに壁全体がペンキまみれになっていく
const WALL_CELL := 4
var wall_img: Image
var wall_tex: ImageTexture
var wall_dirty := false
var ambient_t := 1.0
var flow_t := 0.0
var spread_goop_t := 0.0
var token_holder = null        # 同時に攻撃できる敵は1体だけ（攻撃権トークン）
var game_over := false
var survive_time := 0.0


func _ready() -> void:
	randomize()
	_setup_input()
	sfx = SfxScript.new()
	add_child(sfx)
	# 壁のペンキ層
	_init_wall()
	var wl := ColorRect.new()
	wl.size = Vector2(VIEW_W, FLOOR_TOP)
	var wm := ShaderMaterial.new()
	wm.shader = WallShader
	wm.set_shader_parameter("wall_tex", wall_tex)
	wm.set_shader_parameter("size", wl.size)
	wl.material = wm
	wl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(wl)
	# ペンキまみれの床（シェーダー）
	var fl := ColorRect.new()
	fl.position = Vector2(0, FLOOR_TOP)
	fl.size = Vector2(VIEW_W, VIEW_H - FLOOR_TOP)
	var fm := ShaderMaterial.new()
	fm.shader = FloorShader
	fm.set_shader_parameter("size", fl.size)
	_init_goop()
	fm.set_shader_parameter("goop_tex", goop_tex)
	fm.set_shader_parameter("feet_v", (FLOOR_Y - FLOOR_TOP) / fl.size.y)
	fl.material = fm
	fl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fl)
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
	_update_mess(delta)
	if goop_dirty:
		goop_dirty = false
		for i in goop.size():
			goop_img.set_pixel(i, 0, Color(goop[i], 0, 0))
		goop_tex.update(goop_img)


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


# ---------- 床のドロドロ ----------
func _init_goop() -> void:
	var n := int(VIEW_W / GOOP_CELL)
	goop.resize(n)
	goop_img = Image.create(n, 1, false, Image.FORMAT_RF)
	goop_tex = ImageTexture.create_from_image(goop_img)
	# 最初からあちこちにドロドロがある
	add_goop(150.0, 90.0, 0.8)
	add_goop(560.0, 60.0, 0.6)
	add_goop(780.0, 160.0, 1.0)   # ワニの足元


## x を中心に幅 w のドロドロを amount だけ足す（中心ほど厚い）
func add_goop(x: float, w: float, amount: float) -> void:
	var i0 := int((x - w * 0.5) / GOOP_CELL)
	var i1 := int((x + w * 0.5) / GOOP_CELL)
	for i in range(maxi(i0, 0), mini(i1 + 1, goop.size())):
		var cx := (i + 0.5) * GOOP_CELL
		var k := 1.0 - absf(cx - x) / (w * 0.5 + 0.01)
		if k > 0.0:
			goop[i] = minf(goop[i] + amount * (0.4 + 0.6 * k), 1.0)
	goop_dirty = true


# 互換用：敵の攻撃などで床が汚れる
func add_floor_splat(x: float, w: float) -> void:
	add_goop(x, w * 1.6, 0.5)


## モップ（筆）で範囲のドロドロを薄くする。消えた量を返す
func clean_floor(x0: float, x1: float, power := 0.45) -> float:
	var removed := 0.0
	for i in range(maxi(int(x0 / GOOP_CELL), 0), mini(int(x1 / GOOP_CELL) + 1, goop.size())):
		var before := goop[i]
		goop[i] = maxf(goop[i] - power, 0.0)
		removed += before - goop[i]
	goop_dirty = true
	return removed


## 足元のドロドロの厚み（0〜1）
func goop_at(x: float) -> float:
	var i := int(x / GOOP_CELL)
	if i < 0 or i >= goop.size():
		return 0.0
	return goop[i]


func splat_under(x: float) -> bool:
	return goop_at(x) > 0.15


# ---------- 壁のペンキと、全体の汚れの進行 ----------
func _init_wall() -> void:
	wall_img = Image.create(int(VIEW_W) / WALL_CELL, int(ceil(FLOOR_TOP / WALL_CELL)), false, Image.FORMAT_RF)
	wall_tex = ImageTexture.create_from_image(wall_img)
	# 最初から少し汚れている
	for i in 6:
		splat_wall(Vector2(randf_range(0, VIEW_W), randf_range(150, FLOOR_TOP - 30)), randf_range(14, 30), 0.8)


## 壁にベチャッとペンキを付ける（いびつな塊＋垂れ）
func splat_wall(pos: Vector2, r: float, amount := 1.0) -> void:
	var cw := wall_img.get_width()
	var ch := wall_img.get_height()
	var c := pos / WALL_CELL
	var rc := r / WALL_CELL
	for b in randi_range(3, 6):
		var bc := c + Vector2(randf_range(-rc, rc), randf_range(-rc, rc) * 0.6)
		var br := randf_range(rc * 0.4, rc * 0.85)
		for y in range(int(bc.y - br) - 1, int(bc.y + br) + 2):
			for x in range(int(bc.x - br) - 1, int(bc.x + br) + 2):
				if x < 0 or y < 0 or x >= cw or y >= ch:
					continue
				var d := Vector2(x - bc.x, y - bc.y).length() / maxf(br, 0.5)
				if d <= 1.0:
					var v := wall_img.get_pixel(x, y).r
					wall_img.set_pixel(x, y, Color(minf(v + amount * (1.2 - d), 1.0), 0, 0))
	# 垂れ
	for k in randi_range(2, 4):
		var dx := int(c.x + randf_range(-rc, rc))
		var ln := randi_range(3, 18)
		for y in range(int(c.y), int(c.y) + ln):
			if dx < 0 or dx >= cw or y < 0 or y >= ch:
				break
			var v2 := wall_img.get_pixel(dx, y).r
			wall_img.set_pixel(dx, y, Color(minf(v2 + amount * 0.8, 1.0), 0, 0))
	wall_dirty = true


func _update_mess(delta: float) -> void:
	# 時間がたつほど汚れるペースが上がる（最終的には壁も床もペンキまみれ）
	ambient_t -= delta
	if ambient_t <= 0.0:
		ambient_t = maxf(0.35, 2.5 - survive_time * 0.03)
		var e = enemies[0] if not enemies.is_empty() else null
		# ワニの周りほど汚れやすい
		var x: float = randf_range(0, VIEW_W)
		if e != null and randf() < 0.6:
			x = clampf(e.position.x + randf_range(-220, 220), 0, VIEW_W)
		splat_wall(Vector2(x, randf_range(120, FLOOR_TOP - 10)), randf_range(12, 34), 0.9)
		# 配管から床に垂れて、床のドロドロも増える
		add_goop(randf_range(0, VIEW_W), randf_range(20, 60), 0.15 + minf(survive_time * 0.004, 0.35))
	# 壁のペンキが下に流れる
	flow_t -= delta
	if flow_t <= 0.0:
		flow_t = 0.12
		var cw := wall_img.get_width()
		var ch := wall_img.get_height()
		for i in 60:
			var x2 := randi() % cw
			var y2 := randi() % (ch - 1)
			var v := wall_img.get_pixel(x2, y2).r
			if v > 0.5 and wall_img.get_pixel(x2, y2 + 1).r < v - 0.15:
				wall_img.set_pixel(x2, y2 + 1, Color(v * 0.92, 0, 0))
				wall_dirty = true
		if wall_dirty:
			wall_dirty = false
			wall_tex.update(wall_img)
	# 床のドロドロが横ににじんで広がる
	spread_goop_t -= delta
	if spread_goop_t <= 0.0:
		spread_goop_t = 0.4
		var src := goop.duplicate()
		for i in range(1, goop.size() - 1):
			var nb := maxf(src[i - 1], src[i + 1]) * 0.93
			if nb > goop[i]:
				goop[i] = lerpf(goop[i], nb, 0.35)
		goop_dirty = true


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
		var c2 := Color("7d3a5c") if rng.randf() < 0.75 else Color("847334")
		draw_rect(Rect2(x, 92, rng.randf_range(2, 6), dl), c2)
		draw_rect(Rect2(x - 1, 92 + dl, 6, 5), c2)
	# 床との境目の影
	draw_rect(Rect2(0, FLOOR_TOP - 6, VIEW_W, 6), Color(0, 0, 0, 0.35))
