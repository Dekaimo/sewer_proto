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
const W := 128
const H := 128
const FEET_Y := 119          # 絵の中で足が接地している行
const HP_MAX := 100.0
const DIRT_R := 3            # 汚れの塗り半径の倍率

var main
var sprite: Sprite2D
var base_img: Image
var mask_img: Image
var mask_tex: ImageTexture
var opaque_px: Array[Vector2i] = []
var dirty_list: Array[Vector2i] = []

var state := "normal"   # normal / slipped / grabbed / defeated
var slip_t := 0.0       # 転んでいる残り時間
var vel := Vector2.ZERO
var facing := 1
var on_floor := true
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
func contamination() -> float:
	return float(dirty_list.size()) / float(max(opaque_px.size(), 1))


func add_dirt(center: Vector2i, r: int) -> void:
	r *= DIRT_R
	var changed := false
	for y in range(center.y - r, center.y + r + 1):
		for x in range(center.x - r, center.x + r + 1):
			if x < 0 or y < 0 or x >= W or y >= H:
				continue
			if Vector2(x - center.x, y - center.y).length() > r + 0.3:
				continue
			if base_img.get_pixel(x, y).a == 0.0:
				continue
			if mask_img.get_pixel(x, y).r > 0.5:
				continue
			mask_img.set_pixel(x, y, Color.WHITE)
			dirty_list.append(Vector2i(x, y))
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
	for i in n:
		if dirty_list.is_empty():
			break
		var idx := randi() % dirty_list.size()
		var p: Vector2i = dirty_list[idx]
		dirty_list.remove_at(idx)
		mask_img.set_pixel(p.x, p.y, Color.BLACK)
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
	vel.x = (1.0 if position.x > from_x else -1.0) * 220.0
	vel.y = -120.0
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
	struggle = maxf(struggle - 0.15, 0.0)


func _escape() -> void:
	var e = grabbed_by
	state = "normal"
	grabbed_by = null
	invuln = 1.0
	main.sfx.play("escape")
	position.y = main.FLOOR_Y - 1
	on_floor = false
	if is_instance_valid(e):
		vel = Vector2(-e.facing * 260.0, -220.0)
		e.on_escaped()
	else:
		vel = Vector2(0.0, -220.0)


func _defeat() -> void:
	state = "defeated"
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
	elif event is InputEventMouseMotion and state == "grabbed":
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
	match state:
		"normal":
			_update_normal(delta)
		"slipped":
			_update_slipped(delta)
		"grabbed":
			_update_grabbed(delta)
	_update_frame(delta)
	sprite.flip_h = facing < 0
	sprite.visible = state != "defeated" and not (invuln > 0.0 and state == "normal" and int(invuln * 20) % 2 == 0)
	queue_redraw()


func _update_frame(delta: float) -> void:
	var f := 0
	if attack_timer > 0.0:
		f = 1 if attack_timer > 0.12 else 2
	elif cleaning:
		f = 3
	sprite.texture = FRAMES[f]
	# 歩いているときは上下に揺らす（歩きアニメの代わり）
	if state == "normal" and on_floor and absf(vel.x) > 1.0:
		bob += delta * 12.0
		sprite.position.y = -absf(sin(bob)) * 3.0
	elif state == "slipped":
		sprite.position = Vector2(facing * 55.0, -32.0)   # 横倒しで床に寝そべる（足元を中心に）
	else:
		sprite.position.y = 0.0


func _update_normal(delta: float) -> void:
	var c := contamination()
	var dir := Input.get_axis("left", "right")
	var mouse_x := get_global_mouse_position().x
	if dir == 0.0 and lmb_held and lmb_time >= 0.18 and absf(mouse_x - position.x) > 8.0:
		dir = 1.0 if mouse_x > position.x else -1.0
	var want_clean := Input.is_action_pressed("clean") or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	cleaning = want_clean and on_floor and hitstun <= 0.0
	if hitstun > 0.0 or cleaning:
		dir = 0.0
	if dir != 0.0:
		facing = 1 if dir > 0 else -1

	# 自分を拭く（その場で動けなくなる代わりに汚れを少しずつ落とす）
	if cleaning:
		clean_timer += delta
		if clean_timer > 0.1:
			clean_timer = 0.0
			remove_dirt(12)
			main.sfx.play("wipe", -4.0, 0.3)

	var speed := 140.0 * (1.0 - 0.55 * c)
	# 床のドロドロ：厚いほど遅く、ヌルヌル滑り、足元から汚れていく
	var g: float = main.goop_at(position.x) if on_floor else 0.0
	if g > 0.1:
		speed *= 1.0 - 0.35 * g
		floor_timer += delta * (0.5 + absf(vel.x) / 140.0)
		if floor_timer > 0.5 - 0.3 * g:
			floor_timer = 0.0
			# 厚いほど高い位置まで跳ねる（足→脚→胴）
			var top := int(lerpf(110.0, 70.0, g))
			add_dirt(Vector2i(randi_range(40, 88), randi_range(top, 118)), 1)
			main.sfx.play("step_paint", -3.0, 0.2)

	if hitstun > 0.0:
		vel.x = move_toward(vel.x, 0.0, 700.0 * delta)
	else:
		# 地面が乾いていればキビキビ、ドロドロだと止まりにくく曲がりにくい
		var accel := lerpf(1400.0, 220.0, g)
		var target := dir * speed
		# 勢いがついた状態で急に切り返す／止まると転ぶことがある
		if g > 0.45 and absf(vel.x) > 90.0 and signf(target) != signf(vel.x) and randf() < 2.5 * g * delta:
			_slip()
			return
		vel.x = move_toward(vel.x, target, accel * delta)

	var jump := Input.is_action_just_pressed("jump") or queued_jump
	queued_jump = false
	if on_floor and jump and not cleaning:
		vel.y = -360.0 * (1.0 - 0.4 * c)
		on_floor = false

	var mouse_attack := queued_attack
	queued_attack = false
	if mouse_attack and absf(mouse_x - position.x) > 4.0:
		facing = 1 if mouse_x > position.x else -1
	if (Input.is_action_just_pressed("attack") or mouse_attack) and attack_cd <= 0.0 and not cleaning and hitstun <= 0.0:
		attack_timer = 0.24
		attack_cd = 0.4
		_do_attack()

	vel.y += 900.0 * delta
	position += vel * delta
	if position.y >= main.FLOOR_Y:
		position.y = main.FLOOR_Y
		var landing_speed := vel.y
		vel.y = 0.0
		if not on_floor:
			on_floor = true
			# ドロドロの上に着地：跳ねて汚れる。勢いがあると足を取られて転ぶ
			var lg: float = main.goop_at(position.x)
			if lg > 0.2:
				for i in 2:
					add_dirt(Vector2i(randi_range(40, 88), randi_range(95, 118)), 1)
				main.add_goop(position.x, 30.0, 0.05)
				main.sfx.play("step_paint")
				if lg > 0.5 and landing_speed > 250.0 and randf() < 0.5 * lg:
					_slip()
	position.x = clampf(position.x, main.ARENA_L, main.ARENA_R)


func _do_attack() -> void:
	# モップ（筆）攻撃：前方の床掃除＋敵を押し返す
	var x0 := position.x + (10.0 if facing > 0 else -60.0)
	var x1 := x0 + 50.0
	main.clean_floor(x0, x1, 0.35)
	main.sfx.play("mop", -2.0)
	for e in main.enemies:
		if not e.active():
			continue
		var ex: float = e.position.x
		if ex > x0 - 50.0 and ex < x1 + 50.0 and absf(e.position.y - position.y) < 80.0:
			e.on_hit(facing)
			if randf() < 0.3:
				add_dirt(Vector2i(64 + facing * 30, randi_range(60, 90)), 1)  # 跳ね返り


# ---------- 転倒 ----------
func _slip() -> void:
	state = "slipped"
	slip_t = 1.1
	struggle = 0.0
	last_dir = 0
	vel.x *= 0.6
	main.sfx.play("hit")
	# 倒れ込んだ側がべったり汚れる
	for i in 5:
		add_dirt(Vector2i(randi_range(30, 98), randi_range(40, 118)), 2)
	main.add_goop(position.x, 50.0, 0.1)
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
	position = grabbed_by.position + Vector2(grabbed_by.facing * 40, -50)
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
	if state != "defeated":
		var gy: float = main.FLOOR_Y - position.y
		draw_set_transform(Vector2(0, gy), 0.0, Vector2(1.0, 0.25))
		draw_circle(Vector2.ZERO, 30.0, Color(0, 0, 0, 0.35))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if cleaning and state == "normal":
		var t := Time.get_ticks_msec() / 120
		for i in 3:
			var px := float((t * 7 + i * 11) % 40) - 20.0
			var py := -10.0 - float((t * 3 + i * 9) % 100)
			draw_rect(Rect2(px, py, 2, 2), Color("bfefff"))
