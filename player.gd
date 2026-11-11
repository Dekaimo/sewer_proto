extends Node2D
## 主人公（黒猫）。汚れはシェーダー＋マスク画像で表現する。
## 絵は assets/cat_0..3.png（128x128）。0=待機 1=構え 2=突き 3=掲げ

const DIRT_SHADER = preload("res://dirt.gdshader")
const FRAMES := [
	preload("res://assets/cat_0.png"),
	preload("res://assets/cat_1.png"),
	preload("res://assets/cat_2.png"),
	preload("res://assets/cat_3.png"),
]
const IDLE_ANIM := [
	preload("res://assets/cat_idle_0.png"),
	preload("res://assets/cat_idle_1.png"),
	preload("res://assets/cat_idle_2.png"),
	preload("res://assets/cat_idle_3.png"),
]
const WALK := [
	preload("res://assets/cat_walk_0.png"),
	preload("res://assets/cat_walk_1.png"),
	preload("res://assets/cat_walk_2.png"),
	preload("res://assets/cat_walk_3.png"),
]
const W := 128
const H := 128
const FEET_Y := 119          # 絵の中で足が接地している行
const HP_MAX := 250.0
const DIRT_R := 5            # 汚れの塗り半径の倍率

var main
var sprite: Sprite2D
var base_img: Image
var mask_img: Image
var mask_tex: ImageTexture
var opaque_px: Array[Vector2i] = []

var state := "normal"   # normal / slipped / grabbed / swallowed / defeated
var swallower = null     # 呑み込んでいるサメ
var crucifier = null     # 磔にしているワニ
var swallow_combo := false   # ワニごと呑まれた（地中で2対1）
var slip_t := 0.0
var hidden_in_hug := false   # 抱きつきの1枚絵に描かれている間は自分を表示しない       # 転んでいる残り時間
var vel := Vector2.ZERO
var facing := 1
var on_floor := true
var z := 0.0     # ジャンプの高さ（position.y は床の上での奥行き）
var vz := 0.0
var grabbed_by = null
var struggle := 0.0
var last_dir := 0

var drip_timer := 0.0
var floor_timer := 0.0
var clean_timer := 0.0
var attack_timer := 0.0
var attack_cd := 0.0
var invuln := 0.0
var hitstun := 0.0
var cleaning := false
var hp := HP_MAX
var bob := 0.0

# マウス操作
var lmb_held := false
var lmb_time := 0.0
var queued_attack := false
var queued_jump := false


func _ready() -> void:
	base_img = FRAMES[0].get_image()
	base_img.convert(Image.FORMAT_RGBA8)
	for y in H:
		for x in W:
			if base_img.get_pixel(x, y).a > 0.0:
				opaque_px.append(Vector2i(x, y))

	mask_img = Image.create(W, H, false, Image.FORMAT_RGBA8)
	mask_img.fill(Color.BLACK)
	mask_tex = ImageTexture.create_from_image(mask_img)

	sprite = Sprite2D.new()
	sprite.texture = FRAMES[0]
	sprite.centered = false
	sprite.offset = Vector2(-W / 2, -FEET_Y - 1)
	var mat := ShaderMaterial.new()
	mat.shader = DIRT_SHADER
	mat.set_shader_parameter("dirt_mask", mask_tex)
	sprite.material = mat
	add_child(sprite)


# ---------- 汚れ ----------
# mask_img の赤 = ペンキの厚み（0〜1）。dirty は汚れている画素の集合。
var dirty := {}
var drip_flow_t := 0.0


func contamination() -> float:
	return float(dirty.size()) / float(max(opaque_px.size(), 1))


func _paint_px(x: int, y: int, amount: float) -> bool:
	if x < 0 or y < 0 or x >= W or y >= H:
		return false
	if base_img.get_pixel(x, y).a == 0.0:
		return false
	var v := mask_img.get_pixel(x, y).r
	if v >= 1.0:
		return false
	mask_img.set_pixel(x, y, Color(minf(v + amount, 1.0), 0, 0))
	dirty[Vector2i(x, y)] = true
	return true


## ベチャッと付く汚れ：いびつな塊＋下に垂れる筋
func add_dirt(center: Vector2i, r: int) -> void:
	r *= DIRT_R
	var blobs := randi_range(3, 5)
	for b in blobs:
		var c := center + Vector2i(randi_range(-r, r) / 2, randi_range(-r, r) / 2)
		var br := randf_range(r * 0.45, r * 0.9)
		var ib := int(ceil(br))
		for y in range(c.y - ib, c.y + ib + 1):
			for x in range(c.x - ib, c.x + ib + 1):
				var d := Vector2(x - c.x, (y - c.y) * 1.15).length()
				if d <= br:
					_paint_px(x, y, 0.75 if d < br * 0.6 else 0.45)
	# 垂れ
	for k in randi_range(1, 3):
		var dx := center.x + randi_range(-r, r)
		var y0 := center.y + randi_range(0, r)
		var ln := randi_range(r, r * 3)
		for y in range(y0, y0 + ln):
			if not _paint_px(dx, y, 0.6):
				break
			if randf() < 0.25:
				_paint_px(dx + 1, y, 0.5)
	mask_tex.update(mask_img)


## 汚れがじわじわ下に流れていく
func _flow_dirt() -> void:
	if dirty.is_empty():
		return
	var keys := dirty.keys()
	var changed := false
	for i in mini(10, keys.size()):
		var q: Vector2i = keys[randi() % keys.size()]
		var v := mask_img.get_pixel(q.x, q.y).r
		if v < 0.5 or q.y + 1 >= H:
			continue
		var below := mask_img.get_pixel(q.x, q.y + 1).r
		if below < v - 0.2 and _paint_px(q.x, q.y + 1, v * 0.8 - below):
			changed = true
	if changed:
		mask_tex.update(mask_img)


# 汚れているほど被ダメージが増える（最大1.5倍）
func damage(amount: float) -> void:
	if state == "defeated":
		return
	hp -= amount * (1.0 + 0.5 * contamination())
	if hp <= 0.0:
		hp = 0.0
		_defeat()


func random_body_point() -> Vector2i:
	return opaque_px.pick_random()


func remove_dirt(n: int) -> void:
	if dirty.is_empty():
		return
	var keys := dirty.keys()
	for i in n:
		var q: Vector2i = keys[randi() % keys.size()]
		if not dirty.has(q):
			continue
		var v := mask_img.get_pixel(q.x, q.y).r - 0.5
		if v <= 0.05:
			mask_img.set_pixel(q.x, q.y, Color.BLACK)
			dirty.erase(q)
		else:
			mask_img.set_pixel(q.x, q.y, Color(v, 0, 0))
	mask_tex.update(mask_img)


# ---------- 被弾・拘束 ----------
func can_be_grabbed() -> bool:
	return (state == "normal" or state == "slipped") and invuln <= 0.0


func take_hit(from_x: float, r: int, count: int) -> bool:
	if state != "normal" or invuln > 0.0:
		return false
	for i in count:
		add_dirt(random_body_point(), r)
	damage(8.0)
	main.sfx.play("hit")
	# 飛び散って後ろの壁も汚れる
	main.splat_wall(position + Vector2(-facing * 30.0, -randf_range(40.0, 120.0)), 28.0)
	vel.x = (1.0 if position.x > from_x else -1.0) * 220.0
	vz = 120.0
	on_floor = false
	hitstun = 0.3
	invuln = 0.6
	return true


func grab(enemy) -> void:
	state = "grabbed"
	sprite.rotation = 0.0
	grabbed_by = enemy
	struggle = 0.2
	main.sfx.play("grab")
	last_dir = 0
	vel = Vector2.ZERO


func assist_splash() -> void:
	# もう1体の連携攻撃：大きく汚れて、抵抗ゲージが削られる
	add_dirt(random_body_point(), 3)
	damage(5.0)
	main.sfx.play("assist")
	main.splat_wall(position + Vector2(randf_range(-60.0, 60.0), -randf_range(60.0, 160.0)), 34.0)
	struggle = maxf(struggle - 0.15, 0.0)


func _escape() -> void:
	var e = grabbed_by
	state = "normal"
	grabbed_by = null
	hidden_in_hug = false   # 抱きつきの絵から自分の表示に戻す
	invuln = 1.0
	main.sfx.play("escape")
	on_floor = false
	if is_instance_valid(e):
		vel = Vector2(-e.facing * 260.0, 0.0)
		vz = 220.0
		e.on_escaped()
	else:
		vel = Vector2.ZERO
		vz = 220.0


func _defeat() -> void:
	var was_crucified := state == "crucified"
	state = "defeated"
	if was_crucified:
		hidden_in_hug = true
	main.sfx.play("defeat")
	main.on_player_defeated(grabbed_by)
	grabbed_by = null


# ---------- マウス ----------
# 左クリック短押し：モップ（カーソル方向）／左長押し：カーソルへ歩く
# 右長押し：自分を拭く／中クリック・ホイール上：ジャンプ
# 捕まったとき：マウスを左右に振る
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				lmb_held = true
				lmb_time = 0.0
				if state == "grabbed":
					struggle += 0.04
			else:
				if lmb_held and lmb_time < 0.18:
					queued_attack = true
				lmb_held = false
		elif mb.pressed and (mb.button_index == MOUSE_BUTTON_MIDDLE or mb.button_index == MOUSE_BUTTON_WHEEL_UP):
			queued_jump = true
	elif event is InputEventMouseMotion and (state == "grabbed" or state == "swallowed" or state == "crucified"):
		var rx: float = (event as InputEventMouseMotion).relative.x
		if absf(rx) >= 4.0:
			var d := 1 if rx > 0 else -1
			if d != last_dir:
				struggle += 0.09
				last_dir = d


# ---------- 更新 ----------
func _process(delta: float) -> void:
	if lmb_held:
		lmb_time += delta
	invuln -= delta
	attack_cd -= delta
	attack_timer -= delta
	hitstun -= delta
	drip_flow_t -= delta
	if drip_flow_t <= 0.0:
		drip_flow_t = 0.08
		_flow_dirt()
	match state:
		"normal":
			_update_normal(delta)
		"slipped":
			_update_slipped(delta)
		"grabbed":
			_update_grabbed(delta)
		"swallowed":
			_update_swallowed(delta)
		"crucified":
			_update_crucified(delta)
	_update_frame(delta)
	z_index = int(position.y)   # 手前にいるほど前に描く
	sprite.flip_h = facing < 0
	if state != "grabbed" and state != "crucified":
		hidden_in_hug = false
	if state == "crucified":
		hidden_in_hug = true
	sprite.visible = state != "defeated" and state != "swallowed" and not hidden_in_hug and not (invuln > 0.0 and state == "normal" and int(invuln * 20) % 2 == 0)
	queue_redraw()


func _update_frame(delta: float) -> void:
	var f := 0
	if attack_timer > 0.0:
		f = 1 if attack_timer > 0.12 else 2
	elif cleaning:
		f = 3
	sprite.texture = FRAMES[f]
	sprite.position = Vector2(0.0, -z)
	if state == "normal" and on_floor and vel.length() > 8.0 and f == 0:
		# 歩きアニメ（速さに合わせてコマ送り）
		bob += delta * vel.length() / 14.0
		sprite.texture = WALK[int(bob) % 4]
	elif state == "normal" and f == 0:
		# 待機の呼吸
		sprite.texture = IDLE_ANIM[int(Time.get_ticks_msec() / 220) % 4]
	elif state == "slipped":
		sprite.position = Vector2(facing * 55.0, -32.0)   # 横倒しで床に寝そべる（足元を中心に）


func _update_normal(delta: float) -> void:
	var c := contamination()
	var inp := Vector2(Input.get_axis("left", "right"), Input.get_axis("up", "down"))
	var mouse := get_global_mouse_position()
	var mouse_x := mouse.x
	if inp == Vector2.ZERO and lmb_held and lmb_time >= 0.18 and mouse.distance_to(position) > 8.0:
		inp = (mouse - position).normalized()
	if inp.length() > 1.0:
		inp = inp.normalized()
	var want_clean := Input.is_action_pressed("clean") or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	cleaning = want_clean and on_floor and hitstun <= 0.0
	if hitstun > 0.0 or cleaning:
		inp = Vector2.ZERO
	if absf(inp.x) > 0.1:
		facing = 1 if inp.x > 0 else -1

	# 自分を拭く（その場で動けなくなる代わりに汚れを少しずつ落とす）
	if cleaning:
		clean_timer += delta
		if clean_timer > 0.1:
			clean_timer = 0.0
			remove_dirt(40)
			main.sfx.play("wipe", -4.0, 0.3)

	var speed := 140.0 * (1.0 - 0.55 * c)
	# 床のドロドロ：厚いほど遅く、ヌルヌル滑り、足元から汚れていく
	var g: float = main.goop_at(position) if on_floor else 0.0
	if g > 0.1:
		speed *= 1.0 - 0.35 * g
		floor_timer += delta * (0.5 + vel.length() / 140.0)
		if floor_timer > 0.5 - 0.3 * g:
			floor_timer = 0.0
			# 厚いほど高い位置まで跳ねる（足→脚→胴）
			var top := int(lerpf(110.0, 70.0, g))
			add_dirt(Vector2i(randi_range(40, 88), randi_range(top, 118)), 1)
			main.sfx.play("step_paint", -3.0, 0.2)

	if hitstun > 0.0:
		vel = vel.move_toward(Vector2.ZERO, 700.0 * delta)
	else:
		# 地面が乾いていればキビキビ、ドロドロだと止まりにくく曲がりにくい
		var accel := lerpf(1400.0, 220.0, g)
		var target := Vector2(inp.x * speed, inp.y * speed * 0.6)   # 奥行き方向は少し遅い
		# 勢いがついた状態で急に切り返す／止まると転ぶことがある
		if g > 0.45 and absf(vel.x) > 90.0 and signf(target.x) != signf(vel.x) and randf() < 2.5 * g * delta:
			_slip()
			return
		vel = vel.move_toward(target, accel * delta)

	var jump := Input.is_action_just_pressed("jump") or queued_jump
	queued_jump = false
	if on_floor and jump and not cleaning:
		vz = 360.0 * (1.0 - 0.4 * c)
		on_floor = false

	var mouse_attack := queued_attack
	queued_attack = false
	if mouse_attack and absf(mouse_x - position.x) > 4.0:
		facing = 1 if mouse_x > position.x else -1
	if (Input.is_action_just_pressed("attack") or mouse_attack) and attack_cd <= 0.0 and not cleaning and hitstun <= 0.0:
		attack_timer = 0.24
		attack_cd = 0.4
		_do_attack()

	position += vel * delta
	position.x = clampf(position.x, main.ARENA_L, main.ARENA_R)
	position.y = clampf(position.y, main.DEPTH_MIN, main.DEPTH_MAX)
	if not on_floor:
		vz -= 900.0 * delta
		z += vz * delta
		if z <= 0.0:
			var landing_speed := -vz
			z = 0.0
			vz = 0.0
			on_floor = true
			# ドロドロの上に着地：跳ねて汚れる。勢いがあると足を取られて転ぶ
			var lg: float = main.goop_at(position)
			if lg > 0.2:
				for i in 2:
					add_dirt(Vector2i(randi_range(40, 88), randi_range(95, 118)), 1)
				main.add_goop(position, 30.0, 0.05)
				main.sfx.play("step_paint")
				if lg > 0.5 and landing_speed > 250.0 and randf() < 0.5 * lg:
					_slip()


func _do_attack() -> void:
	# モップ（筆）攻撃：前方の床掃除＋敵を押し返す
	var x0 := position.x + (10.0 if facing > 0 else -60.0)
	var x1 := x0 + 50.0
	main.clean_floor(Vector2((x0 + x1) * 0.5, position.y), 80.0, 0.35)
	main.sfx.play("mop", -2.0)
	for e in main.enemies:
		if not e.active():
			continue
		var ex: float = e.position.x
		if ex > x0 - 50.0 and ex < x1 + 50.0 and absf(e.position.y - position.y) < 30.0:
			e.on_hit(facing)
			if randf() < 0.3:
				add_dirt(Vector2i(64 + facing * 30, randi_range(60, 90)), 1)  # 跳ね返り


# ---------- サメに丸呑みされる ----------
func get_swallowed(shark, combo: bool) -> bool:
	if state == "grabbed" and is_instance_valid(grabbed_by):
		grabbed_by = null
	state = "swallowed"
	swallower = shark
	swallow_combo = combo
	hidden_in_hug = false
	sprite.rotation = 0.0
	struggle = 0.1
	last_dir = 0
	vel = Vector2.ZERO
	z = 0.0
	# 呑まれた瞬間に全身ドロドロ
	for i in (10 if combo else 6):
		add_dirt(random_body_point(), 3)
	damage(6.0)
	main.sfx.play("defeat", -4.0)
	return true


func _update_swallowed(delta: float) -> void:
	if not is_instance_valid(swallower):
		state = "normal"
		return
	position = swallower.position
	# 2対1のときは抜け出しにくく、汚れるのも速い
	struggle -= (0.2 if swallow_combo else 0.15) * delta
	var d := 0
	if Input.is_action_just_pressed("left"):
		d = -1
	elif Input.is_action_just_pressed("right"):
		d = 1
	if d != 0 and d != last_dir:
		struggle += 0.05 if swallow_combo else 0.07
		last_dir = d
	drip_timer += delta
	if drip_timer > (0.14 if swallow_combo else 0.24):
		drip_timer = 0.0
		add_dirt(random_body_point(), 2)
		damage(2.0 if swallow_combo else 1.2)
		if state == "swallowed":
			main.sfx.play("grab_loop", -4.0, 0.3)
	struggle = clampf(struggle, 0.0, 1.0)
	if struggle >= 1.0 and state == "swallowed":
		# 床から飛び出して脱出
		state = "normal"
		var s = swallower
		swallower = null
		invuln = 1.4
		on_floor = false
		vz = 320.0
		vel = Vector2(randf_range(-160.0, 160.0), 0.0)
		main.add_goop(position, 120.0, 0.4)
		main.sfx.play("escape")
		s.on_escaped()


# ---------- 磔 ----------
func get_crucified(w) -> void:
	state = "crucified"
	crucifier = w
	grabbed_by = null
	hidden_in_hug = true
	struggle = 0.15
	last_dir = 0
	vel = Vector2.ZERO
	vz = 0.0
	z = 0.0
	on_floor = true
	position = w.position
	for i in 6:
		add_dirt(random_body_point(), 3)
	damage(8.0)


func _update_crucified(delta: float) -> void:
	if not is_instance_valid(crucifier):
		state = "normal"
		return
	position = crucifier.position + Vector2(0, 1)
	# 腕を括られているので抜けにくい
	struggle -= 0.12 * delta
	var d := 0
	if Input.is_action_just_pressed("left"):
		d = -1
	elif Input.is_action_just_pressed("right"):
		d = 1
	if d != 0 and d != last_dir:
		struggle += 0.06
		last_dir = d
	drip_timer += delta
	if drip_timer > 0.3:
		drip_timer = 0.0
		# 上から垂れてくるので、上の方から汚れていく
		var pt: Vector2i = random_body_point()
		add_dirt(Vector2i(pt.x, mini(pt.y, randi_range(10, 70))), 2)
		damage(1.2)
	struggle = clampf(struggle, 0.0, 1.0)
	if struggle >= 1.0:
		var w = crucifier
		crucifier = null
		state = "normal"
		hidden_in_hug = false
		invuln = 1.2
		on_floor = false
		z = 120.0
		vz = 0.0
		vel = Vector2(randf_range(-120.0, 120.0), 0.0)
		main.sfx.play("escape")
		main.add_goop(position, 100.0, 0.3)
		if is_instance_valid(w):
			w.on_escaped()


# ---------- 転倒 ----------
func _slip() -> void:
	state = "slipped"
	slip_t = 1.1
	struggle = 0.0
	last_dir = 0
	vel.x *= 0.6
	vel.y = 0.0
	main.sfx.play("hit")
	# 倒れ込んだ側がべったり汚れる
	for i in 5:
		add_dirt(Vector2i(randi_range(30, 98), randi_range(40, 118)), 2)
	main.add_goop(position, 70.0, 0.25)
	damage(3.0)
	# 90度回転なのでドットは崩れない
	sprite.rotation = -PI / 2 * facing


func _update_slipped(delta: float) -> void:
	vel.x = move_toward(vel.x, 0.0, 120.0 * delta)
	position.x = clampf(position.x + vel.x * delta, main.ARENA_L, main.ARENA_R)
	# 起き上がる：左右連打で早くなる
	var d := 0
	if Input.is_action_just_pressed("left"):
		d = -1
	elif Input.is_action_just_pressed("right"):
		d = 1
	if d != 0 and d != last_dir:
		slip_t -= 0.12
		last_dir = d
	slip_t -= delta
	floor_timer += delta
	if floor_timer > 0.3:
		floor_timer = 0.0
		add_dirt(random_body_point(), 1)
	if slip_t <= 0.0:
		state = "normal"
		sprite.rotation = 0.0
		invuln = 0.4


func _update_grabbed(delta: float) -> void:
	if not is_instance_valid(grabbed_by):
		state = "normal"
		return
	position = grabbed_by.position + Vector2(grabbed_by.facing * 40, 1)
	z = 0.0
	facing = -grabbed_by.facing
	struggle -= 0.22 * delta
	var d := 0
	if Input.is_action_just_pressed("left"):
		d = -1
	elif Input.is_action_just_pressed("right"):
		d = 1
	if d != 0 and d != last_dir:
		struggle += 0.09
		last_dir = d
	if Input.is_action_just_pressed("attack") or Input.is_action_just_pressed("clean"):
		struggle += 0.04
	# もがいている感じの小刻みな揺れ
	sprite.position.x = sin(Time.get_ticks_msec() / 40.0) * 1.5
	drip_timer += delta
	if drip_timer > 0.35:
		drip_timer = 0.0
		add_dirt(random_body_point(), 2)
		damage(1.5)
		if state == "grabbed":
			main.sfx.play("grab_loop", -2.0)
	struggle = clampf(struggle, 0.0, 1.0)
	if struggle >= 1.0 and state == "grabbed":
		sprite.position.x = 0.0
		_escape()


func _draw() -> void:
	# 足元の影（ジャンプ中も床に残す）
	if state != "defeated" and state != "swallowed" and not hidden_in_hug:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.25))
		draw_circle(Vector2.ZERO, 30.0, Color(0, 0, 0, 0.35))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if cleaning and state == "normal":
		var t := Time.get_ticks_msec() / 120
		for i in 3:
			var px := float((t * 7 + i * 11) % 40) - 20.0
			var py := -10.0 - float((t * 3 + i * 9) % 100)
			draw_rect(Rect2(px, py, 2, 2), Color("bfefff"))
