extends Node2D
## ペンキワニ（仮絵）。攻撃権トークンで交互に攻め、相方が掴んでいる間は反対側から連携する。

var main
var facing := -1
var state := "approach"   # approach / windup / lunge / recover / hold / assist / idle
var t := 0.0
var stun := 0.0
var vel_x := 0.0
var lunge_dir := 1
var assist_timer := 0.0
var wob := 0.0


func _process(delta: float) -> void:
	wob += delta
	if main.game_over:
		state = "idle"
		queue_redraw()
		return
	var p = main.player
	stun -= delta
	if stun > 0.0:
		position.x += vel_x * delta
		vel_x = move_toward(vel_x, 0.0, 300.0 * delta)
		_clamp()
		queue_redraw()
		return

	var dx: float = p.position.x - position.x
	match state:
		"approach":
			if absf(dx) > 1.0:
				facing = 1 if dx > 0 else -1
			var h = main.holding_enemy()
			if h != null and h != self:
				state = "assist"
			elif p.state == "normal":
				if absf(dx) > 34.0:
					position.x += facing * 28.0 * delta
				elif absf(dx) < 20.0:
					position.x -= facing * 15.0 * delta
				elif main.request_token(self):
					state = "windup"
					t = 0.5
		"windup":
			t -= delta
			if t <= 0.0:
				state = "lunge"
				t = 0.35
				lunge_dir = facing
		"lunge":
			t -= delta
			position.x += lunge_dir * 150.0 * delta
			var close: bool = absf(p.position.x - position.x) < 12.0 and p.position.y > position.y - 22.0
			if close and p.state == "normal":
				if randf() < 0.45 and p.can_be_grabbed():
					p.grab(self)
					state = "hold"
				else:
					if p.take_hit(position.x, 2, 4):
						main.add_floor_splat(p.position.x, 14.0)
					state = "recover"
					t = 0.6
			elif t <= 0.0:
				main.add_floor_splat(position.x + lunge_dir * 8.0, 8.0)
				state = "recover"
				t = 0.6
		"recover":
			t -= delta
			if t <= 0.0:
				main.release_token(self)
				state = "approach"
		"hold":
			if p.state != "grabbed" or p.grabbed_by != self:
				main.release_token(self)
				state = "recover"
				t = 0.8
		"assist":
			var h2 = main.holding_enemy()
			if h2 == null or h2 == self:
				state = "approach"
			else:
				var target_x: float = clampf(p.position.x - h2.facing * 14.0, main.ARENA_L, main.ARENA_R)
				position.x = move_toward(position.x, target_x, 45.0 * delta)
				if absf(dx) > 1.0:
					facing = 1 if dx > 0 else -1
				assist_timer -= delta
				if absf(position.x - target_x) < 3.0 and assist_timer <= 0.0:
					assist_timer = 0.9
					p.assist_splash()
					main.add_floor_splat(p.position.x, 10.0)
	_clamp()
	queue_redraw()


func _clamp() -> void:
	position.x = clampf(position.x, main.ARENA_L, main.ARENA_R)


func on_hit(dir: int) -> void:
	if state == "hold":
		return
	stun = 0.5
	vel_x = dir * 120.0
	if state == "windup" or state == "lunge":
		main.release_token(self)
		state = "approach"


func on_escaped() -> void:
	stun = 1.2
	vel_x = -facing * 80.0
	state = "recover"
	t = 0.0


func _draw() -> void:
	var pink := Color("ec5a9e")
	var dark := Color("b8357a")
	var yel := Color("f9d84d")
	var s := 1.0 + (0.08 if state == "windup" and int(wob * 20) % 2 == 0 else 0.0)
	var f := float(facing)
	# 溶けた下半身（水たまり）
	draw_rect(Rect2(-15, -4, 30, 4), dark)
	draw_rect(Rect2(-12, -12, 24, 9), pink)
	# 胴体（筋肉質）
	draw_rect(Rect2(-10 * s, -34 * s, 20 * s, 23 * s), pink)
	draw_rect(Rect2(-10 * s, -34 * s, 20 * s, 2), Color("f489bd"))
	# マーブル模様
	draw_line(Vector2(-8, -30), Vector2(4, -22), yel, 1.0)
	draw_line(Vector2(6, -18), Vector2(-4, -10), yel, 1.0)
	# 頭（ワニ）
	draw_rect(Rect2(-6 + f * 4, -44, 12, 10), pink)
	draw_rect(Rect2(f * 8 - (0 if f > 0 else 9), -40, 9, 5), pink)   # 口先
	draw_rect(Rect2(-1 + f * 4, -42, 2, 2), Color.WHITE)               # 目
	# トゲ
	for i in 3:
		draw_rect(Rect2(-f * (2 + i * 3), -47 + i * 2, 2, 3), dark)
	# 腕
	var arm_x := f * 10.0
	if state == "hold" or state == "lunge":
		draw_rect(Rect2(arm_x - (0 if f > 0 else 10), -30, 10, 5), pink)
	else:
		draw_rect(Rect2(arm_x - 3, -30, 6, 14), pink)
	# 垂れるしずく
	var drip := int(wob * 6) % 6
	draw_rect(Rect2(-9, -12 + drip, 1, 2), pink)
	draw_rect(Rect2(8, -10 + (drip + 3) % 6, 1, 2), pink)
	if state == "windup":
		draw_rect(Rect2(-1, -56, 2, 5), yel)
		draw_rect(Rect2(-1, -50, 2, 1), yel)
