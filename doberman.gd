extends Node2D
## ペンキドーベルマン（ピンクのマーブル、幅広マッチョ、いたずら好き）
## 素材（assets/dobe_idle.png）がそろうまではゲームに出さない。
## DEBUG_SHOW を true にすると、仮の絵（ワニの待機を色替え）で動きだけ確認できる。
##
## いまの動き：
##   enter    水たまりから形成
##   prowl    主人公のまわりをうろつく。フェイント（飛びかかるフリ→寸止めしてニヤつく）
##   sandwich 主人公がワニに磔にされていると駆け寄り、正面から抱きついて胸をこすりつける（挟み撃ち）
##   pushed   押し返されたフリ：大げさによろけて離れる…が、すぐニヤニヤ戻ってきてさらに強く押しつける
##   recover  本当に押し返された：しばらく離れて様子をうかがう
## あとで：サメの腹の中の3対1（下から抱きつく）、地面での挟み撃ち、サメのゆっくり丸呑み、棺桶

const DEBUG_SHOW := false
const FEET_Y := 236

var main
var sprite: Sprite2D
var state := "enter"
var t := 0.0
var facing := -1
var vel_x := 0.0
var stun := 0.0
var feint_t := 3.0
var fake_left := 0          # あと何回「押されたフリ」をするか
var rub_t := 0.0
var push_off := 0.0         # 押し返されて離れている距離（見た目）
var frames := {}            # "idle" / "walk" / "rub" / "reel" … 素材があれば


static func has_art() -> bool:
	return ResourceLoader.exists("res://assets/dobe_idle.png")


func _ready() -> void:
	sprite = Sprite2D.new()
	sprite.centered = false
	sprite.offset = Vector2(-128, -FEET_Y)
	add_child(sprite)
	for k in ["idle", "walk", "rub", "reel", "emerge", "feint"]:
		var arr: Array[Texture2D] = []
		var i := 0
		while ResourceLoader.exists("res://assets/dobe_%s_%d.png" % [k, i]):
			arr.append(load("res://assets/dobe_%s_%d.png" % [k, i]))
			i += 1
		if arr.size() > 0:
			frames[k] = arr
	if has_art():
		sprite.texture = load("res://assets/dobe_idle.png")
	else:
		# 仮の絵：ワニの待機を少し暗く（デバッグ用）
		sprite.texture = load("res://assets/wani_idle.png")
		sprite.modulate = Color(0.75, 0.6, 0.9)
	t = 0.0


func active() -> bool:
	return state == "prowl" or state == "recover"


func _frame(k: String, i: int) -> void:
	if frames.has(k):
		var arr: Array = frames[k]
		sprite.texture = arr[posmod(i, arr.size())]


func _process(delta: float) -> void:
	t += delta
	z_index = int(position.y)
	sprite.flip_h = facing > 0
	var p = main.player
	if main.game_over and state != "sandwich":
		return
	stun -= delta
	match state:
		"enter":
			_frame("emerge", int(t * 10.0))
			if t > 1.2:
				state = "prowl"
				t = 0.0
		"prowl":
			_update_prowl(delta, p)
		"sandwich":
			_update_sandwich(delta, p)
		"pushed":
			_update_pushed(delta, p)
		"recover":
			vel_x = move_toward(vel_x, 0.0, 300.0 * delta)
			position.x += vel_x * delta
			_frame("idle", int(t * 6.0))
			if t > 2.5:
				state = "prowl"
				t = 0.0
	position.x = clampf(position.x, main.ARENA_L, main.ARENA_R)
	position.y = clampf(position.y, main.DEPTH_MIN, main.DEPTH_MAX)


func _update_prowl(delta: float, p) -> void:
	# 磔にされていたら、挟みに行く
	if p.state == "crucified" and p.crucifier != null and is_instance_valid(p.crucifier) and p.crucifier.state == "crucify":
		var tx: float = p.position.x - facing * 0.0
		facing = 1 if tx > position.x else -1
		var dx: float = tx + (-facing) * 34.0 - position.x
		position.x += clampf(dx, -260.0 * delta, 260.0 * delta)
		position.y = move_toward(position.y, p.position.y + 6.0, 120.0 * delta)
		_frame("walk", int(t * 10.0))
		if absf(dx) < 6.0:
			_start_sandwich(p)
		return
	# うろうろ：近づきすぎず、ときどきフェイント
	var dxp: float = p.position.x - position.x
	facing = 1 if dxp > 0 else -1
	var want := 140.0
	var mv: float = clampf((absf(dxp) - want) * 2.0, -110.0, 110.0) * signf(dxp)
	position.x += mv * delta
	position.y = move_toward(position.y, p.position.y, 50.0 * delta)
	_frame("walk" if absf(mv) > 10.0 else "idle", int(t * 8.0))
	feint_t -= delta
	if feint_t <= 0.0 and absf(dxp) < 220.0:
		# 飛びかかるフリ → 寸止め。主人公がジャンプや攻撃で反応したら、そのスキを他の敵が突く…はず
		feint_t = randf_range(3.0, 6.0)
		vel_x = facing * 260.0
		_frame("feint", 0)
		main.sfx.play("assist", -6.0, 0.2)
	if vel_x != 0.0:
		position.x += vel_x * delta
		vel_x = move_toward(vel_x, 0.0, 700.0 * delta)


# ---------- 磔の挟み撃ち ----------
func _start_sandwich(p) -> void:
	state = "sandwich"
	t = 0.0
	rub_t = 0.0
	push_off = 0.0
	fake_left = randi_range(1, 3)
	p.sandwicher = self
	p.push = 0.0
	main.sfx.play("grab")
	main.zoom_moment(p.position + Vector2(0, -150), 1.0)
	for i in 4:
		p.add_dirt(p.random_body_point(), 3)


func _update_sandwich(delta: float, p) -> void:
	if p.sandwicher != self or (p.state != "crucified" and p.state != "defeated"):
		_leave(false)
		return
	# 胸をこすりつける：ぐりぐりと上下に。こするたびにペンキが主人公にのる
	rub_t += delta * (2.4 if not main.game_over else 1.6)
	var r := sin(rub_t * TAU * 0.5)
	push_off = move_toward(push_off, 0.0, 90.0 * delta)
	sprite.position = Vector2(-facing * push_off, -40.0 - 70.0 + r * 8.0).round()   # 磔の高さまで伸び上がって抱きつく
	_frame("rub", int(rub_t * 4.0))
	if absf(r) > 0.97 and fmod(rub_t, 1.0) < delta * 2.4:
		main.sfx.play_any(["grab_loop", "gurgle"], -3.0, 0.2)
		for i in 2:
			p.add_dirt(p.random_body_point(), 2)
		p.damage(1.0)
		main.add_goop(p.position + Vector2(randf_range(-30, 30), 0), 50.0, 0.2)


## 主人公が押し返しゲージを満タンにした
func on_pushed(p) -> void:
	if fake_left > 0:
		# 押されたフリ：「うわー」とよろけて離れる…
		fake_left -= 1
		state = "pushed"
		t = 0.0
		main.sfx.play("hit", -4.0)
		return
	_leave(true)


func _update_pushed(delta: float, p) -> void:
	if p.sandwicher != self or (p.state != "crucified" and p.state != "defeated"):
		_leave(false)
		return
	# 0〜0.5秒：大げさによろけて離れる → 0.5〜1.1秒：振り向いてニヤッ → 戻ってきて前より強く押しつける
	if t < 0.5:
		push_off = lerpf(push_off, 70.0, 1.0 - exp(-delta * 10.0))
		_frame("reel", int(t * 10.0))
	elif t < 1.1:
		_frame("idle", 0)
	else:
		push_off = move_toward(push_off, 0.0, 400.0 * delta)
		if push_off <= 0.0:
			state = "sandwich"
			t = 0.0
			p.push = 0.0
			main.sfx.play("grab", 0.0)
			for i in 5:
				p.add_dirt(p.random_body_point(), 3)
			p.damage(3.0)
	sprite.position = Vector2(-facing * push_off, -110.0).round()


func _leave(real: bool) -> void:
	var p = main.player
	if p.sandwicher == self:
		p.sandwicher = null
	sprite.position = Vector2.ZERO
	state = "recover"
	t = 0.0
	vel_x = -facing * (260.0 if real else 120.0)
	if real:
		main.sfx.play("escape", -4.0)


func on_hit(dir: int) -> void:
	if not active():
		return
	stun = 0.4
	vel_x = dir * 200.0


func on_escaped() -> void:
	_leave(true)
