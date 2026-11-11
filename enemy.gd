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
var spread_t := 0.0
var ambush_cd := 4.0     # 床に潜って奇襲するまでの待ち
var lurk_t := 0.0
var ambush_done := false
var slide_v := 0.0       # 抱きつきの勢いで掴んだあと滑る速さ
# ポーズ絵（生成できたものだけ使う。無ければ待機絵）
var pose := {}
var anims := {}          # 生成したアニメ（コマ配列）
var anim_masks := {}     # 2体が1枚に描かれたコマの、主人公部分のマスク
const HUG_SHADER = preload("res://hug_dirt.gdshader")
var hug_mat: ShaderMaterial
var hold_t := 0.0
var last_x := 0.0
var last_y := 0.0
var swallowed_by = null
var anim_t := 0.0
var sprite: Sprite2D
var emerge_frames: Array[Texture2D] = []
var swallow_frames: Array[Texture2D] = []
var flex_frames: Array[Texture2D] = []


func _ready() -> void:
	for i in 9:
		emerge_frames.append(load("res://assets/wani_emerge_%d.png" % i))
		swallow_frames.append(load("res://assets/wani_swallow_%d.png" % i))
		flex_frames.append(load("res://assets/wani_flex_%d.png" % i))
	for k in ["windup", "spread", "hug"]:
		var path := "res://assets/wani_pose_%s.png" % k
		pose[k] = load(path) if ResourceLoader.exists(path) else IDLE
	var counts := {"windup": 8, "charge": 6, "grab": 6, "hug": 9, "idle_anim": 8, "move": 8}
	for k in counts:
		var arr: Array[Texture2D] = []
		var masks: Array[Texture2D] = []
		for i in counts[k]:
			arr.append(load("res://assets/wani_%s_%d.png" % [k, i]))
			var mp := "res://assets/masks/wani_%s_%d_mask.png" % [k, i]
			masks.append(load(mp) if ResourceLoader.exists(mp) else null)
		anims[k] = arr
		anim_masks[k] = masks
	hug_mat = ShaderMaterial.new()
	hug_mat.shader = HUG_SHADER
	sprite = Sprite2D.new()
	sprite.texture = emerge_frames[0]
	sprite.centered = false
	sprite.offset = Vector2(-128, -FEET_Y - 1)
	add_child(sprite)
	anim_t = -randf_range(0.0, 0.6)   # 2体の出現タイミングを少しずらす


func active() -> bool:
	return not state in ["emerge", "swallow", "idle", "sink", "lurk", "ambush", "swallowed"]


func _process(delta: float) -> void:
	anim_t += delta
	z_index = int(position.y)   # 手前にいるほど前に描く
	sprite.flip_h = facing > 0
	sprite.scale = Vector2.ONE
	sprite.position = Vector2.ZERO

	if state == "emerge":
		# 水たまりから形成 → マッスルポーズを決めてから戦闘開始
		if anim_t < 0.9:
			sprite.texture = emerge_frames[clampi(int(anim_t * 10.0), 0, 8)]
		else:
			var fi := clampi(int((anim_t - 0.9) * 8.0), 0, 8)
			# ポーズ（5〜6コマ目）で少し溜める
			if anim_t - 0.9 > 0.6 and anim_t - 0.9 < 1.2:
				fi = 5
			elif anim_t - 0.9 >= 1.2:
				fi = clampi(6 + int((anim_t - 2.1) * 8.0), 6, 8)
			sprite.texture = flex_frames[fi]
		if anim_t > 2.6:
			state = "approach"
			sprite.texture = IDLE
		return
	if state == "swallow":
		var j := clampi(int(anim_t * 7.0), 0, 8)
		sprite.texture = swallow_frames[j]
		return
	if state == "swallowed":
		# サメの腹の中（主人公と一緒に地中）
		if is_instance_valid(swallowed_by):
			position = swallowed_by.position
		sprite.visible = false
		return
	if main.game_over:
		state = "idle"
		sprite.visible = true
		return
	if state == "sink" or state == "lurk" or state == "ambush":
		_update_ambush(delta)
		return
	# 普段は呼吸、動いているときは這う動き（下の各状態で上書きされる）
	var moved := absf(position.x - last_x) + absf(position.y - last_y) > 0.3
	last_x = position.x
	last_y = position.y
	if moved and state in ["approach", "assist"]:
		sprite.texture = anims["move"][int(anim_t * 9.0) % 8]
	else:
		sprite.texture = anims["idle_anim"][int(anim_t * 7.0) % 8]

	var p = main.player
	stun -= delta
	if stun > 0.0:
		position.x += vel_x * delta
		vel_x = move_toward(vel_x, 0.0, 600.0 * delta)
		sprite.position.x = sin(anim_t * 60.0) * 2.0
		_clamp()
		return

	# 足元の水たまりからドロドロがじわじわ広がる
	spread_t -= delta
	if spread_t <= 0.0:
		spread_t = 1.0
		main.add_goop(position, 150.0, 0.12)

	var dx: float = p.position.x - position.x
	match state:
		"approach":
			var h = main.holding_enemy()
			if h != null and h != self:
				state = "assist"
			elif (p.state == "normal" or p.state == "slipped") and _want_ambush(delta, p) and main.request_token(self):
				# ドロドロに潜って、プレイヤーの足元から飛び出す
				state = "sink"
				anim_t = 0.0
			elif p.state == "normal" or p.state == "slipped":
				# 挟み撃ち：相方と反対側の位置へ回り込む（プレイヤーをすり抜けてよい）
				var tx: float = clampf(p.position.x + _flank_side(p) * FLANK, main.ARENA_L, main.ARENA_R)
				var to_slot: float = tx - position.x
				# 奥行きも合わせに行く（奥・手前にずれれば攻撃を外せる）
				position.y = move_toward(position.y, p.position.y, 45.0 * delta)
				if absf(to_slot) > 6.0:
					position.x += signf(to_slot) * 60.0 * delta
				elif absf(p.position.y - position.y) < 14.0 and main.request_token(self):
					# 抱きつき突進（本命）か、普通の殴り
					if randf() < 0.6:
						state = "hug_windup"
						t = 0.85
					else:
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
			main.add_goop(position, 40.0, 0.04)   # 突進した跡にドロドロが残る
			var close: bool = _in_reach(p, REACH)
			if close and (p.state == "normal" or p.state == "slipped"):
				# 殴りは被弾のみ。転んでいるところだけは掴む
				if p.state == "slipped" and p.can_be_grabbed():
					p.grab(self)
					_start_hold()
				else:
					if p.take_hit(position.x, 2, 4):
						main.add_floor_splat(p.position, 40.0)
					state = "recover"
					t = 0.6
			elif t <= 0.0:
				main.add_floor_splat(position + Vector2(lunge_dir * 40.0, 0.0), 24.0)
				main.splat_wall(Vector2(position.x + lunge_dir * 60.0, position.y - randf_range(80.0, 200.0)), 40.0)
				state = "recover"
				t = 0.6
		"recover":
			t -= delta
			if t <= 0.0:
				main.release_token(self)
				state = "approach"
		"hug_windup":
			# 後ろにググッと体重をかけて力を溜める
			t -= delta
			var k: float = clampf(1.0 - t / 0.85, 0.0, 1.0)
			sprite.texture = anims["windup"][clampi(int(k * 8.0), 0, 7)]
			sprite.position.x = -facing * 8.0 * k
			if t < 0.2:
				sprite.position.x += sin(anim_t * 70.0) * 2.0   # 震えて、来るぞ
			if t <= 0.0:
				state = "charge"
				t = 0.55
				anim_t = 0.0
				lunge_dir = facing
				main.sfx.play("grab", -6.0)
		"charge":
			# 両腕を広げて突進
			t -= delta
			sprite.texture = anims["charge"][clampi(int(anim_t * 14.0), 0, 5)]
			position.x += lunge_dir * 380.0 * delta
			main.add_goop(position, 40.0, 0.05)
			var hit: bool = _in_reach(p, REACH + 10.0)
			if hit and p.can_be_grabbed():
				p.grab(self)
				_hug_impact(p)
				_start_hold()
				slide_v = lunge_dir * 300.0
			elif t <= 0.0:
				# 空振り：勢い余ってつんのめる
				main.add_floor_splat(position + Vector2(lunge_dir * 50.0, 0.0), 40.0)
				main.splat_wall(Vector2(position.x + lunge_dir * 80.0, position.y - randf_range(60.0, 180.0)), 36.0)
				state = "recover"
				t = 0.9
		"hold":
			_update_hold_sprite(delta, p)
			# 抱きついた勢いのままジュルジュル滑ってから止まる（ドロドロが厚いほど長く滑る）
			if slide_v != 0.0:
				var g: float = main.goop_at(position)
				slide_v = move_toward(slide_v, 0.0, lerpf(900.0, 260.0, g) * delta)
				position.x += slide_v * delta
				main.add_goop(position, 50.0, 0.06)
				if absf(slide_v) > 60.0 and randf() < 0.3:
					p.add_dirt(p.random_body_point(), 1)
				if position.x <= main.ARENA_L or position.x >= main.ARENA_R:
					slide_v = 0.0
					main.splat_wall(Vector2(position.x, position.y - 120.0), 60.0)
			# 掴んでいる間はゆっくり脈打つ
			sprite.scale = Vector2(1.0, 1.0 + sin(anim_t * 5.0) * 0.015)
			if p.state != "grabbed" or p.grabbed_by != self:
				_end_hold()
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
					main.add_floor_splat(p.position, 30.0)
	_clamp()


# ---------- 床に潜っての奇襲 ----------
func _want_ambush(delta: float, p) -> bool:
	ambush_cd -= delta
	if ambush_cd > 0.0:
		return false
	# プレイヤーがドロドロの上にいる、または遠くにいるときに狙う
	var on_goop: bool = main.goop_at(p.position) > 0.25
	var far: bool = absf(p.position.x - position.x) > 260.0
	if on_goop or far:
		ambush_cd = randf_range(5.0, 9.0)
		return true
	return false


func _update_ambush(delta: float) -> void:
	var p = main.player
	match state:
		"sink":
			# 出現アニメを逆再生して床に溶ける
			var i := 8 - clampi(int(anim_t * 14.0), 0, 8)
			sprite.texture = emerge_frames[i]
			if anim_t > 0.7:
				state = "lurk"
				lurk_t = 0.0
				sprite.visible = false
		"lurk":
			# 床の下を移動。ドロドロのある所しか通れない。泡だけが見える
			lurk_t += delta
			var dx: float = p.position.x - position.x
			var to_p: Vector2 = p.position - position
			# ドロドロの中は速く、乾いた床はゆっくり（通った跡がドロドロになる）
			var sp: float = 200.0 if main.goop_at(position) > 0.12 else 70.0
			if to_p.length() > 4.0:
				position += to_p.normalized() * Vector2(1.0, 0.6) * sp * delta
				main.add_goop(position, 36.0, 0.04)
			var under: bool = to_p.length() < 12.0 and p.state != "grabbed"
			if (under and lurk_t > 0.6) or lurk_t > 4.5:
				state = "ambush"
				anim_t = 0.0
				ambush_done = false
				sprite.visible = true
				facing = 1 if dx >= 0 else -1
				main.sfx.play("grab", -2.0)
			queue_redraw()
		"ambush":
			var j := clampi(int(anim_t * 16.0), 0, 8)
			sprite.texture = emerge_frames[j]
			if j >= 4 and not ambush_done:
				ambush_done = true
				main.add_goop(position, 90.0, 0.3)
				main.splat_wall(Vector2(position.x, position.y - randf_range(60.0, 180.0)), 40.0)
				var close: bool = _in_reach(p, REACH)
				if close and p.can_be_grabbed():
					p.grab(self)
					_start_hold()
					queue_redraw()
					return
			if anim_t > 0.6:
				state = "recover"
				t = 0.5
				sprite.texture = IDLE
				queue_redraw()


func _draw() -> void:
	# 潜っている間の泡（ここにいる、というサイン）
	if state != "lurk":
		return
	var tt := Time.get_ticks_msec() / 1000.0
	draw_set_transform(Vector2(0, 4), 0.0, Vector2(1.0, 0.3))
	draw_circle(Vector2.ZERO, 34.0, Color(0.55, 0.12, 0.35, 0.55))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for k in 5:
		var ph := fmod(tt * 1.6 + k * 0.37, 1.0)
		var bx := sin(k * 2.3 + tt * 1.3) * 26.0
		var r := 4.0 + 6.0 * ph
		var c := Color("ec5a9e") if k % 2 == 0 else Color("f9d84d")
		c.a = 1.0 - ph * 0.7
		draw_circle(Vector2(bx, -2.0 - ph * 10.0), r + 1.0, Color(0.35, 0.05, 0.2, c.a))
		draw_circle(Vector2(bx, -2.0 - ph * 10.0), r, c)
		draw_arc(Vector2(bx, -2.0 - ph * 10.0), r, PI * 1.1, PI * 1.6, 6, Color(1, 0.9, 0.95, c.a), 1.0)


# ---------- 抱きつき中（ワニ＋主人公の1枚絵） ----------
func _start_hold() -> void:
	state = "hold"
	hold_t = 0.0
	sprite.material = hug_mat
	main.player.sprite.visible = false
	main.player.hidden_in_hug = true


func _end_hold() -> void:
	sprite.material = null
	main.player.hidden_in_hug = false


func _update_hold_sprite(delta: float, p) -> void:
	hold_t += delta
	hug_mat.set_shader_parameter("contamination", p.contamination())
	var key := "grab"
	var idx := 0
	if hold_t < 0.5:
		# 捕まえた瞬間：ベチャッと抱え込む
		idx = clampi(int(hold_t * 12.0), 0, 5)
	else:
		# 抱えたまま、ゆっくりこねるように締め付ける（往復で再生）
		key = "hug"
		var f := int((hold_t - 0.5) * 8.0) % 16
		idx = f if f < 9 else 16 - f
	sprite.texture = anims[key][idx]
	hug_mat.set_shader_parameter("cat_mask", anim_masks[key][idx])


## 抱きつかれた瞬間：勢いでペンキが派手に飛び散る
func _hug_impact(p) -> void:
	for i in 7:
		p.add_dirt(p.random_body_point(), 3)
	p.damage(6.0)
	for i in 3:
		main.splat_wall(Vector2(p.position.x + randf_range(-120.0, 120.0), p.position.y - randf_range(50.0, 220.0)), randf_range(30.0, 55.0))
	main.add_goop(p.position, 160.0, 0.4)
	main.sfx.play("assist")


## とどめ：プレイヤーを抱えて水たまりに沈む
func play_swallow(p) -> void:
	_end_hold()
	state = "swallow"
	anim_t = 0.0
	position.x = clampf(p.position.x - facing * 10.0, main.ARENA_L, main.ARENA_R)
	position.y = p.position.y


# ---------- サメにまとめて呑まれる ----------
func get_swallowed(shark) -> void:
	_end_hold()
	main.release_token(self)
	state = "swallowed"
	swallowed_by = shark
	sprite.visible = false


## 主人公が脱出したら、ワニも吐き出されて床から形成し直す
func spit_out(pos: Vector2) -> void:
	swallowed_by = null
	position = pos
	_clamp()
	sprite.visible = true
	state = "emerge"
	anim_t = 0.6   # 水たまりから少し盛り上がったところから
	stun = 0.0


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


func _in_reach(p, r: float) -> bool:
	# 横の距離・奥行き・高さ（ジャンプで飛び越えられる）がすべて近いときだけ届く
	return absf(p.position.x - position.x) < r and absf(p.position.y - position.y) < 24.0 and p.z < 70.0


func _clamp() -> void:
	position.x = clampf(position.x, main.ARENA_L, main.ARENA_R)
	position.y = clampf(position.y, main.DEPTH_MIN, main.DEPTH_MAX)


func on_hit(dir: int) -> void:
	if state == "hold" or not active():
		return
	stun = 0.5
	vel_x = dir * 220.0
	if state == "windup" or state == "lunge" or state == "hug_windup":
		main.release_token(self)
		state = "approach"


func on_escaped() -> void:
	_end_hold()
	stun = 1.2
	vel_x = -facing * 150.0
	state = "recover"
	t = 0.0
