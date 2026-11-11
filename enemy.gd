extends Node2D
## ペンキワニ。攻撃権トークンで交互に攻め、相方が掴んでいる間は反対側から連携する。
## 絵は 256x256。元絵は左向き。

const IDLE = preload("res://assets/wani_idle.png")
const FEET_Y := 232      # 水たまりの中ほどを足元の線に合わせる（床に広がって見えるように）
const FLANK := 95.0       # 挟み撃ちのときにプレイヤーから取る距離
const REACH := 60.0       # 突進が当たる距離

var main
var facing := -1
var state := "emerge"   # emerge / approach / windup / lunge / recover / hold / assist / swallow / idle
var t := 0.0
var stun := 0.0
var vel_x := 0.0
var lunge_dir := 1
var assist_timer := 0.0
var anim_t := 0.0
var sprite: Sprite2D
var emerge_frames: Array[Texture2D] = []
var swallow_frames: Array[Texture2D] = []


func _ready() -> void:
	for i in 9:
		emerge_frames.append(load("res://assets/wani_emerge_%d.png" % i))
		swallow_frames.append(load("res://assets/wani_swallow_%d.png" % i))
	sprite = Sprite2D.new()
	sprite.texture = emerge_frames[0]
	sprite.centered = false
	sprite.offset = Vector2(-128, -FEET_Y - 1)
	add_child(sprite)
	anim_t = -randf_range(0.0, 0.6)   # 2体の出現タイミングを少しずらす


func active() -> bool:
	return state != "emerge" and state != "swallow" and state != "idle"


func _process(delta: float) -> void:
	anim_t += delta
	sprite.flip_h = facing > 0
	sprite.scale = Vector2.ONE
	sprite.position = Vector2.ZERO

	if state == "emerge":
		var i := clampi(int(anim_t * 10.0), 0, 8)
		sprite.texture = emerge_frames[i]
		if anim_t > 1.1:
			state = "approach"
			sprite.texture = IDLE
		return
	if state == "swallow":
		var j := clampi(int(anim_t * 7.0), 0, 8)
		sprite.texture = swallow_frames[j]
		return
	if main.game_over:
		state = "idle"
		return

	var p = main.player
	stun -= delta
	if stun > 0.0:
		position.x += vel_x * delta
		vel_x = move_toward(vel_x, 0.0, 600.0 * delta)
		sprite.position.x = sin(anim_t * 60.0) * 2.0
		_clamp()
		return

	var dx: float = p.position.x - position.x
	match state:
		"approach":
			var h = main.holding_enemy()
			if h != null and h != self:
				state = "assist"
			elif p.state == "normal":
				# 挟み撃ち：相方と反対側の位置へ回り込む（プレイヤーをすり抜けてよい）
				var tx: float = clampf(p.position.x + _flank_side(p) * FLANK, main.ARENA_L, main.ARENA_R)
				var to_slot: float = tx - position.x
				if absf(to_slot) > 6.0:
					position.x += signf(to_slot) * 60.0 * delta
				elif main.request_token(self):
					state = "windup"
					t = 0.5
			dx = p.position.x - position.x
			if absf(dx) > 2.0:
				facing = 1 if dx > 0 else -1
		"windup":
			t -= delta
			# 溜め：少し縮んでから伸びる
			sprite.scale = Vector2(1.04, 0.96)
			sprite.position.x = -facing * 4.0
			if t <= 0.0:
				state = "lunge"
				t = 0.35
				lunge_dir = facing
		"lunge":
			t -= delta
			position.x += lunge_dir * 280.0 * delta
			var close: bool = absf(p.position.x - position.x) < REACH and p.position.y > position.y - 100.0
			if close and p.state == "normal":
				if randf() < 0.45 and p.can_be_grabbed():
					p.grab(self)
					state = "hold"
				else:
					if p.take_hit(position.x, 2, 4):
						main.add_floor_splat(p.position.x, 40.0)
					state = "recover"
					t = 0.6
			elif t <= 0.0:
				main.add_floor_splat(position.x + lunge_dir * 40.0, 24.0)
				state = "recover"
				t = 0.6
		"recover":
			t -= delta
			if t <= 0.0:
				main.release_token(self)
				state = "approach"
		"hold":
			# 掴んでいる間はゆっくり脈打つ
			sprite.scale = Vector2(1.0, 1.0 + sin(anim_t * 5.0) * 0.015)
			if p.state != "grabbed" or p.grabbed_by != self:
				main.release_token(self)
				state = "recover"
				t = 0.8
		"assist":
			var h2 = main.holding_enemy()
			if h2 == null or h2 == self:
				state = "approach"
			else:
				# 掴んでいる敵の反対側（プレイヤーの向こう側）に回る
				var target_x: float = clampf(p.position.x + h2.facing * 50.0, main.ARENA_L, main.ARENA_R)
				position.x = move_toward(position.x, target_x, 90.0 * delta)
				if absf(dx) > 2.0:
					facing = 1 if dx > 0 else -1
				assist_timer -= delta
				if absf(position.x - target_x) < 6.0 and assist_timer <= 0.0:
					assist_timer = 0.9
					p.assist_splash()
					main.add_floor_splat(p.position.x, 30.0)
	_clamp()


## とどめ：プレイヤーを抱えて水たまりに沈む
func play_swallow(p) -> void:
	state = "swallow"
	anim_t = 0.0
	position.x = clampf(p.position.x - facing * 10.0, main.ARENA_L, main.ARENA_R)
	z_index = 5


## 1体目は今いる側、2体目以降は1体目の反対側を受け持つ
func _flank_side(p) -> float:
	var lead = main.enemies[0]
	var lead_side: float = 1.0 if lead.position.x >= p.position.x else -1.0
	if lead == self:
		var lx: float = p.position.x + lead_side * FLANK
		if lx < main.ARENA_L or lx > main.ARENA_R:
			return -lead_side
		return lead_side
	return -lead_side


func _clamp() -> void:
	position.x = clampf(position.x, main.ARENA_L, main.ARENA_R)


func on_hit(dir: int) -> void:
	if state == "hold" or not active():
		return
	stun = 0.5
	vel_x = dir * 220.0
	if state == "windup" or state == "lunge":
		main.release_token(self)
		state = "approach"


func on_escaped() -> void:
	stun = 1.2
	vel_x = -facing * 150.0
	state = "recover"
	t = 0.0
