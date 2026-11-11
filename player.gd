extends Node2D
## 主人公（仮絵）。汚れはシェーダー＋マスク画像で表現する。

const W := 16
const H := 32
const DIRT_SHADER = preload("res://dirt.gdshader")
const HP_MAX := 100.0

var main
var sprite: Sprite2D
var base_img: Image
var mask_img: Image
var mask_tex: ImageTexture
var opaque_total := 0
var dirty_list: Array[Vector2i] = []

var state := "normal"   # normal / grabbed / defeated
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

# マウス操作
var lmb_held := false
var lmb_time := 0.0
var queued_attack := false
var queued_jump := false


func _ready() -> void:
	base_img = Image.create(W, H, false, Image.FORMAT_RGBA8)
	base_img.fill(Color(0, 0, 0, 0))
	base_img.fill_rect(Rect2i(4, 1, 8, 9), Color("e8c39e"))   # 頭
	base_img.fill_rect(Rect2i(3, 0, 10, 3), Color("3c6e91"))  # 帽子
	base_img.fill_rect(Rect2i(9, 4, 1, 2), Color("222222"))   # 目
	base_img.fill_rect(Rect2i(2, 10, 12, 14), Color("5b8fb9")) # つなぎ
	base_img.fill_rect(Rect2i(2, 16, 12, 1), Color("3c6e91"))
	base_img.fill_rect(Rect2i(3, 24, 4, 8), Color("2d3a46"))  # 脚
	base_img.fill_rect(Rect2i(9, 24, 4, 8), Color("2d3a46"))
	for y in H:
		for x in W:
			if base_img.get_pixel(x, y).a > 0.0:
				opaque_total += 1

	mask_img = Image.create(W, H, false, Image.FORMAT_RGBA8)
	mask_img.fill(Color.BLACK)
	mask_tex = ImageTexture.create_from_image(mask_img)

	sprite = Sprite2D.new()
	sprite.texture = ImageTexture.create_from_image(base_img)
	sprite.centered = false
	sprite.offset = Vector2(-W / 2, -H)
	var mat := ShaderMaterial.new()
	mat.shader = DIRT_SHADER
	mat.set_shader_parameter("dirt_mask", mask_tex)
	sprite.material = mat
	add_child(sprite)


# ---------- 汚れ ----------
func contamination() -> float:
	return float(dirty_list.size()) / float(max(opaque_total, 1))


func add_dirt(center: Vector2i, r: int) -> void:
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
	return Vector2i(randi_range(1, W - 2), randi_range(2, H - 2))


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
	return state == "normal" and invuln <= 0.0


func take_hit(from_x: float, r: int, count: int) -> bool:
	if state != "normal" or invuln > 0.0:
		return false
	for i in count:
		add_dirt(random_body_point(), r)
	damage(8.0)
	main.sfx.play("hit")
	vel.x = (1.0 if position.x > from_x else -1.0) * 120.0
	vel.y = -60.0
	on_floor = false
	hitstun = 0.3
	invuln = 0.6
	return true


func grab(enemy) -> void:
	state = "grabbed"
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
		vel = Vector2(-e.facing * 140.0, -120.0)
		e.on_escaped()
	else:
		vel = Vector2(0.0, -120.0)


func _defeat() -> void:
	state = "defeated"
	grabbed_by = null
	main.sfx.play("defeat")
	main.on_player_defeated()


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
		if absf(rx) >= 3.0:
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
		"grabbed":
			_update_grabbed(delta)
		"defeated":
			sprite.rotation = lerp_angle(sprite.rotation, PI / 2 * facing, 0.1)
	sprite.flip_h = facing < 0
	sprite.visible = not (invuln > 0.0 and state == "normal" and int(invuln * 20) % 2 == 0)
	queue_redraw()


func _update_normal(delta: float) -> void:
	var c := contamination()
	var dir := Input.get_axis("left", "right")
	var mouse_x := get_global_mouse_position().x
	if dir == 0.0 and lmb_held and lmb_time >= 0.18 and absf(mouse_x - position.x) > 4.0:
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
			remove_dirt(1)
			main.sfx.play("wipe", -4.0, 0.3)

	var speed := 75.0 * (1.0 - 0.55 * c)
	var on_paint: bool = on_floor and main.splat_under(position.x)
	if on_paint:
		speed *= 0.6
		floor_timer += delta
		if floor_timer > 0.6:
			floor_timer = 0.0
			add_dirt(Vector2i(randi_range(3, 12), randi_range(27, 31)), 1)
			main.sfx.play("step_paint", -3.0)

	if hitstun > 0.0:
		vel.x = move_toward(vel.x, 0.0, 400.0 * delta)
	else:
		vel.x = dir * speed

	var jump := Input.is_action_just_pressed("jump") or queued_jump
	queued_jump = false
	if on_floor and jump and not cleaning:
		vel.y = -190.0 * (1.0 - 0.4 * c)
		on_floor = false

	var mouse_attack := queued_attack
	queued_attack = false
	if mouse_attack and absf(mouse_x - position.x) > 2.0:
		facing = 1 if mouse_x > position.x else -1
	if (Input.is_action_just_pressed("attack") or mouse_attack) and attack_cd <= 0.0 and not cleaning and hitstun <= 0.0:
		attack_timer = 0.18
		attack_cd = 0.35
		_do_attack()

	vel.y += 500.0 * delta
	position += vel * delta
	if position.y >= main.FLOOR_Y:
		position.y = main.FLOOR_Y
		vel.y = 0.0
		on_floor = true
	position.x = clampf(position.x, main.ARENA_L, main.ARENA_R)


func _do_attack() -> void:
	# モップ攻撃：前方の床掃除＋敵を押し返す
	var x0 := position.x + (4.0 if facing > 0 else -26.0)
	var x1 := x0 + 22.0
	main.clean_floor(x0, x1)
	main.sfx.play("mop", -2.0)
	for e in main.enemies:
		var ex: float = e.position.x
		if ex > x0 - 6.0 and ex < x1 + 6.0 and absf(e.position.y - position.y) < 30.0:
			e.on_hit(facing)
			if randf() < 0.3:
				add_dirt(Vector2i(8 + facing * 5, randi_range(10, 20)), 1)  # 跳ね返り


func _update_grabbed(delta: float) -> void:
	if not is_instance_valid(grabbed_by):
		state = "normal"
		return
	position = grabbed_by.position + Vector2(grabbed_by.facing * 7, -3)
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
	drip_timer += delta
	if drip_timer > 0.35:
		drip_timer = 0.0
		add_dirt(random_body_point(), 2)
		damage(1.5)
		main.sfx.play("grab_loop", -2.0)
	struggle = clampf(struggle, 0.0, 1.0)
	if struggle >= 1.0 and state == "grabbed":
		_escape()


func _draw() -> void:
	if attack_timer > 0.0:
		var a := Vector2(facing * 5, -14)
		var b := Vector2(facing * 24, -6)
		draw_line(a, b, Color("c7b28a"), 1.0)
		draw_rect(Rect2(b.x - 3, b.y - 1, 6, 3), Color("dfe9ef"))
	if cleaning and state == "normal":
		var t := Time.get_ticks_msec() / 120
		for i in 3:
			var px := float((t * 7 + i * 11) % 14) - 7.0
			var py := -6.0 - float((t * 3 + i * 9) % 26)
			draw_rect(Rect2(px, py, 1, 1), Color("bfefff"))
