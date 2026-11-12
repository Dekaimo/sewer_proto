extends Node2D
## 試作：下水道の汚れ・拘束・連携・床のドロドロの仕組みを確認するシーン

const PlayerScript = preload("res://player.gd")
const EnemyScript = preload("res://enemy.gd")
const HudScript = preload("res://hud.gd")
const SfxScript = preload("res://sfx.gd")
const SharkScript = preload("res://shark.gd")
const DobeScript = preload("res://doberman.gd")
const BellyScript = preload("res://belly_view.gd")
const FinisherScript = preload("res://finisher.gd")
const TouchScript = preload("res://touch_ui.gd")
const FloorShader = preload("res://floor.gdshader")
const WallShader = preload("res://wall_paint.gdshader")

const VIEW_W := 960.0
const VIEW_H := 540.0
const FLOOR_TOP := 330.0   # 壁と床の境目
const FLOOR_Y := 440.0     # 開始時の立ち位置（奥行き）
const DEPTH_MIN := 352.0   # 歩ける範囲のいちばん奥
const DEPTH_MAX := 516.0   # いちばん手前
const ARENA_L := 30.0
const ARENA_R := 930.0

var player
var sfx
var enemies: Array = []
var sharks: Array = []
var finisher = null   # フィニッシュ演出（終わるまでゲームオーバー画面は出さない）
var cam: Camera2D
var zoom_t := 0.0
var zoom_focus := Vector2.ZERO
var dobes: Array = []
var heaves: Array = []   # このフレームの床の盛り上がり（地中で暴れている）: [x, y, 半径, 高さ]
var rings: Array = []    # 床の波紋 {pos, t, power}
var floor_mat: ShaderMaterial
var dobe_spawn_t := 18.0   # ペンキドーベルマン（素材ができるまでは出さない）
var shark_spawn_t := 9.0   # ペンキサメが現れるまで
# 床のドロドロ（マリオサンシャインの「らくがき」風）。床全体をマス目に分けた厚み 0〜1
const GOOP_CX := 6.0   # 1マスの横幅
const GOOP_CY := 3.0   # 1マスの縦幅（床は奥行きが潰れて見えるので半分）
var goop_w := 0
var goop_h := 0
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
	fl.material = fm
	floor_mat = fm
	fl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fl)
	player = PlayerScript.new()
	player.main = self
	player.position = Vector2(300, FLOOR_Y)
	add_child(player)
	for x in [760.0]:   # ペンキワニは1体（2体目は別の敵として後で追加）
		var e = EnemyScript.new()
		e.main = self
		e.position = Vector2(x, FLOOR_Y)
		add_child(e)
		enemies.append(e)
	var hud = HudScript.new()
	hud.main = self
	# HUDはカメラのズームの影響を受けないように別レイヤーへ
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	layer.add_child(hud)
	var touch = TouchScript.new()
	layer.add_child(touch)
	var belly = BellyScript.new()
	belly.main = self
	layer.add_child(belly)
	cam = Camera2D.new()
	cam.anchor_mode = Camera2D.ANCHOR_MODE_FIXED_TOP_LEFT
	add_child(cam)
	cam.make_current()


func _process(delta: float) -> void:
	_update_zoom(delta)
	_upload_heaves(delta)
	if game_over:
		if Input.is_action_just_pressed("restart"):
			Engine.time_scale = 1.0
			get_tree().reload_current_scene()
		return
	survive_time += delta
	if dobe_spawn_t > 0.0 and (DobeScript.has_art() or DobeScript.DEBUG_SHOW):
		dobe_spawn_t -= delta
		if dobe_spawn_t <= 0.0:
			var d = DobeScript.new()
			d.main = self
			d.position = Vector2(ARENA_L + 40.0 if player.position.x > VIEW_W * 0.5 else ARENA_R - 40.0, FLOOR_Y)
			add_child(d)
			dobes.append(d)
	if shark_spawn_t > 0.0:
		shark_spawn_t -= delta
		if shark_spawn_t <= 0.0:
			_spawn_shark()
	_update_mess(delta)
	if goop_dirty:
		goop_dirty = false
		var bytes := PackedByteArray()
		bytes.resize(goop.size())
		for i in goop.size():
			bytes[i] = int(clampf(goop[i], 0.0, 1.0) * 255.0)
		goop_img.set_data(goop_w, goop_h, false, Image.FORMAT_R8, bytes)
		goop_tex.update(goop_img)


# ---------- 入力 ----------
func _setup_input() -> void:
	_add_keys("left", [KEY_LEFT, KEY_A])
	_add_keys("right", [KEY_RIGHT, KEY_D])
	_add_keys("up", [KEY_UP, KEY_W])
	_add_keys("down", [KEY_DOWN, KEY_S])
	_add_keys("jump", [KEY_SPACE])
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
## 序盤の手加減：0（開始直後）→ 1（RAMP_TIME 秒生き延びた）。敵の潜行速度・狙いの正確さ・攻撃間隔に掛ける
const RAMP_TIME := 120.0
func ramp() -> float:
	return clampf(survive_time / RAMP_TIME, 0.0, 1.0)


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


## 呑み込まれる瞬間などに、その場所へ一瞬ズームしてスローにする
func zoom_moment(focus: Vector2, dur := 0.7, slow := true) -> void:
	zoom_focus = focus
	zoom_t = dur
	Engine.time_scale = 0.45 if slow else 1.0


func _update_zoom(delta: float) -> void:
	# スロー中でも実時間で戻るように補正
	var real: float = delta / maxf(Engine.time_scale, 0.01)
	var target_zoom := 1.0
	if zoom_t > 0.0:
		zoom_t -= real
		target_zoom = 2.0   # ドット絵がきれいに見える整数倍
		if zoom_t <= 0.0:
			Engine.time_scale = 1.0
	var z: float = lerpf(cam.zoom.x, target_zoom, clampf(real * 14.0, 0.0, 1.0))
	if absf(z - target_zoom) < 0.02:
		z = target_zoom
	cam.zoom = Vector2(z, z)
	# 左上基準のカメラ：注目点が画面中央に来るように、画面の外に出ない範囲で寄せる
	var view := Vector2(VIEW_W, VIEW_H) / z
	var tl := zoom_focus - view * 0.5 if z > 1.01 else Vector2.ZERO
	tl.x = clampf(tl.x, 0.0, VIEW_W - view.x)
	tl.y = clampf(tl.y, 0.0, VIEW_H - view.y)
	cam.position = tl


func _spawn_shark() -> void:
	var s = SharkScript.new()
	s.main = self
	# ワニと反対側の端から、床の下を泳いでくる（挟み撃ち）
	var ref_x: float = enemies[0].position.x if not enemies.is_empty() else VIEW_W
	var x := ARENA_L + 20.0 if ref_x > player.position.x else ARENA_R - 20.0
	s.position = Vector2(x, randf_range(DEPTH_MIN + 20.0, DEPTH_MAX - 20.0))
	add_child(s)
	sharks.append(s)


func on_player_defeated(grabber) -> void:
	game_over = true
	if player.crucifier != null and is_instance_valid(player.crucifier):
		# 晒し上げられたまま力尽きた：ワニはそのまま揺らし続け、画面にはその姿が残る
		var fin = FinisherScript.new()
		fin.main = self
		add_child(fin)
		fin.setup("crucify", player.crucifier.position)
		finisher = fin
		return
	if player.state == "pinned" or player.state == "held":
		# ドーベルマン絡みの負け。専用のとどめは素材ができてから（いまは地上の負けを流用）
		for d in dobes:
			d.visible = false
		for s2 in get_children():
			if s2.has_method("can_maw"):
				s2.state = "swim"
		var near = enemies[0] if enemies.size() > 0 else null
		_start_finisher("hug", player.position if near == null else player.position)
		return
	var sw = player.swallower
	if sw != null and is_instance_valid(sw):
		for d in dobes:
			if d.state == "in_shark":
				d.visible = false
		# 地中で力尽きた：相手ごとのフィニッシュ演出
		var kind := "wani" if sw.has_method("get_swallowed") else ("duo" if player.swallow_combo else "shark")
		var at: Vector2 = sw.position
		if kind == "duo" or kind == "shark":
			if sw.caught_wani != null and is_instance_valid(sw.caught_wani):
				sw.caught_wani.visible = false
		sw.visible = false
		_start_finisher(kind, at)
		return
	# 地上で力尽きた：掴んでいた敵（いなければ一番近い敵）の位置で、抱えて沈む演出
	var e = grabber
	if e == null or not is_instance_valid(e):
		for c in enemies:
			if e == null or absf(c.position.x - player.position.x) < absf(e.position.x - player.position.x):
				e = c
	_start_finisher("hug", e.position if e != null else player.position)


func _start_finisher(kind: String, at: Vector2) -> void:
	finisher = FinisherScript.new()
	finisher.main = self
	add_child(finisher)
	# 演出は画面の右寄りで見せる（左側にゲームオーバーの文字を出すので）
	var fx := 300.0 if kind == "duo" else 620.0   # 2対1は右にワニが出てくるので少し左に
	finisher.setup(kind, Vector2(clampf(at.x, fx, VIEW_W - (380.0 if kind == "duo" else 150.0)), clampf(at.y, DEPTH_MIN, DEPTH_MAX)))
	if kind == "hug":
		# 地上の負け：今まで通り、ワニが抱えて水たまりに沈む絵をそのまま使う
		for c in enemies:
			c.visible = false
	for s in sharks:
		if kind == "hug":
			s.visible = false


func finisher_done() -> bool:
	return finisher == null or finisher.done


# ---------- 床のドロドロ ----------
func _init_goop() -> void:
	goop_w = int(VIEW_W / GOOP_CX)
	goop_h = int((VIEW_H - FLOOR_TOP) / GOOP_CY)
	goop.resize(goop_w * goop_h)
	# 8bit（スマホのブラウザでも線形補間できる形式）
	goop_img = Image.create(goop_w, goop_h, false, Image.FORMAT_R8)
	goop_tex = ImageTexture.create_from_image(goop_img)
	# 最初からあちこちにドロドロがある
	add_goop(Vector2(150, 400), 110.0, 0.8)
	add_goop(Vector2(520, 490), 90.0, 0.6)
	add_goop(Vector2(330, 370), 70.0, 0.5)
	add_goop(Vector2(760, 440), 240.0, 1.0)   # ワニの足元


## p を中心に横幅 w のドロドロを amount だけ足す（中心ほど厚い。奥行き方向は潰れた楕円）
func add_goop(p: Vector2, w: float, amount: float) -> void:
	_paint_goop(p, w, amount)


func add_floor_splat(p: Vector2, w: float) -> void:
	_paint_goop(p, w * 1.6, 0.5)


## 筆で p のまわりのドロドロを薄くする
## 地中で暴れているものが、床のペンキを下から押し上げる（毎フレーム呼ぶ）
func add_heave(world: Vector2, radius: float, height: float) -> void:
	if is_nan(height) or is_nan(radius) or height <= 0.0:
		return
	if heaves.size() < 12:
		heaves.append(Vector4(world.x, world.y - FLOOR_TOP, radius, height))


## 床に波紋を立てる（強く暴れたとき）
func add_ring(world: Vector2, power := 3.0) -> void:
	rings.append({"pos": world, "t": 0.0, "power": power})


func _upload_heaves(delta: float) -> void:
	if floor_mat == null:
		return
	var arr := PackedVector4Array()
	for h in heaves:
		arr.append(h)
	while arr.size() < 12:
		arr.append(Vector4.ZERO)
	floor_mat.set_shader_parameter("heaves", arr)
	floor_mat.set_shader_parameter("heave_n", heaves.size())
	heaves.clear()
	var ra := PackedVector4Array()
	for r in rings:
		r.t += delta
	rings = rings.filter(func(r): return r.t < 1.2)
	for r in rings:
		if ra.size() < 6:
			var k: float = r.t / 1.2
			ra.append(Vector4(r.pos.x, r.pos.y - FLOOR_TOP, 10.0 + k * 90.0, r.power * (1.0 - k)))
	var rn := ra.size()
	while ra.size() < 6:
		ra.append(Vector4.ZERO)
	floor_mat.set_shader_parameter("rings", ra)
	floor_mat.set_shader_parameter("ring_n", rn)


func clean_floor(p: Vector2, w: float, power := 0.45) -> void:
	_paint_goop(p, w, -power)


func _paint_goop(p: Vector2, w: float, amount: float) -> void:
	var rx := w * 0.5 + 0.01
	var ry := rx * 0.45
	var x0 := maxi(int((p.x - rx) / GOOP_CX), 0)
	var x1 := mini(int((p.x + rx) / GOOP_CX), goop_w - 1)
	var y0 := maxi(int((p.y - ry - FLOOR_TOP) / GOOP_CY), 0)
	var y1 := mini(int((p.y + ry - FLOOR_TOP) / GOOP_CY), goop_h - 1)
	for cy in range(y0, y1 + 1):
		var dy := ((cy + 0.5) * GOOP_CY + FLOOR_TOP - p.y) / ry
		for cx in range(x0, x1 + 1):
			var dx := ((cx + 0.5) * GOOP_CX - p.x) / rx
			var d := sqrt(dx * dx + dy * dy)
			if d < 1.0:
				var i := cy * goop_w + cx
				if amount > 0.0:
					goop[i] = minf(goop[i] + amount * (0.4 + 0.6 * (1.0 - d)), 1.0)
				else:
					goop[i] = maxf(goop[i] + amount, 0.0)
	goop_dirty = true


## 足元のドロドロの厚み（0〜1）
func goop_at(p: Vector2) -> float:
	var cx := int(p.x / GOOP_CX)
	var cy := int((p.y - FLOOR_TOP) / GOOP_CY)
	if cx < 0 or cy < 0 or cx >= goop_w or cy >= goop_h:
		return 0.0
	return goop[cy * goop_w + cx]


# ---------- 壁のペンキと、全体の汚れの進行 ----------
func _init_wall() -> void:
	wall_img = Image.create(int(VIEW_W) / WALL_CELL, int(ceil(FLOOR_TOP / WALL_CELL)), false, Image.FORMAT_R8)
	wall_tex = ImageTexture.create_from_image(wall_img)
	# 最初から少し汚れている
	for i in 6:
		splat_wall(Vector2(randf_range(0, VIEW_W), randf_range(150, FLOOR_TOP - 30)), randf_range(14, 30), 0.8)


## 壁にベチャッとペンキを付ける（いびつな塊＋垂れ）
func splat_wall(pos: Vector2, r: float, amount := 1.0) -> void:
	# 床の高さを指定されたら、壁の下の方に付ける
	if pos.y > FLOOR_TOP - 20.0:
		pos.y = randf_range(FLOOR_TOP - 150.0, FLOOR_TOP - 20.0)
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
		add_goop(Vector2(randf_range(0, VIEW_W), randf_range(FLOOR_TOP + 10, VIEW_H)), randf_range(30, 80), 0.2 + minf(survive_time * 0.004, 0.35))
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
		spread_goop_t = 0.6
		var src := goop.duplicate()
		for cy in range(1, goop_h - 1):
			var row := cy * goop_w
			for cx in range(1, goop_w - 1):
				var i := row + cx
				var nb := maxf(maxf(src[i - 1], src[i + 1]), maxf(src[i - goop_w], src[i + goop_w])) * 0.9
				if nb > src[i]:
					goop[i] = lerpf(src[i], nb, 0.3)
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
