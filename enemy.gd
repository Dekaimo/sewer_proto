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
const GooMound = preload("res://goo_mound.gd")
var hug_mat: ShaderMaterial
var hold_t := 0.0
var last_x := 0.0
var last_y := 0.0
var swallowed_by = null
var swallow_t := 0.0
var pull_at := 5.0        # 抱きついてから引きずり込むまで
var under_t := 0.0
var wander := 0.0
var view_mode := "inside" # 地中の見せ方（サメと同じ）
var erupt_t := 0.0
var gurgle_t := 0.0
var front: Node2D        # 床の盛り上がりを手前に描く
var mound: Sprite2D
var mound_frames: Array[Texture2D] = []
var mound_player = GooMound.Player.new()
var cru_t := 0.0
var cru_frames := {}
var cru_masks := {}
var drip_vis: Array = []
const CRU_SPLIT := 192     # 磔の絵：ここより上（主人公の足先まで）を持ち上げる
const CRU_TRUNK := 14      # 繰り返して並べる粘液の幹の帯（主人公が入らない行）
const CRU_LIFT := 90.0     # どれだけ高く持ち上げるか
var trunk: Sprite2D
var bend_mat: ShaderMaterial
var segs: Array[Sprite2D] = []   # しなる幹（下ほど揺れが小さく、遅れて追いかける）
const SEG_N := 9
var hist: Array[float] = []
var met_phase := 0.0
var depth_phase := 0.0
var met_amp := 1.0
var met_dir := 1.0
var met_speed := 1.3       # 揺れの速さ（負けたあとはさらに遅く・大きく）
var met_scale := 1.0
var absorb_y := 1.0
var cru_stage := 0         # 0=晒し 1=半分取り込まれる 2=ほぼ取り込まれる
var cru_base: Sprite2D
var sway := Vector2.ZERO     # 晒し上げ中の揺れ
var sway_v := Vector2.ZERO
var jolt_t := 0.0
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
	for k in ["pillar", "crucify", "absorb1", "absorb2"]:
		var pth := "res://assets/wani_%s.png" % k
		if ResourceLoader.exists(pth):
			cru_frames[k] = load(pth)
			var mp := "res://assets/masks/wani_%s_mask.png" % k
			if ResourceLoader.exists(mp):
				cru_masks[k] = load(mp)
	var morph: Array[Texture2D] = []
	for i in 8:
		var pth2 := "res://assets/wani_morph_%d.png" % i
		if ResourceLoader.exists(pth2):
			morph.append(load(pth2))
			var mp2 := "res://assets/masks/wani_morph_%d_mask.png" % i
			if ResourceLoader.exists(mp2):
				cru_masks["morph_%d" % i] = load(mp2)
	if morph.size() > 0:
		cru_frames["morph"] = morph
	var swayf: Array[Texture2D] = []
	for i in 8:
		var pth4 := "res://assets/wani_sway_%d.png" % i
		if ResourceLoader.exists(pth4):
			swayf.append(load(pth4))
			var mp4 := "res://assets/masks/wani_sway_%d_mask.png" % i
			if ResourceLoader.exists(mp4):
				cru_masks["sway_%d" % i] = load(mp4)
	if swayf.size() == 8:
		cru_frames["sway"] = swayf
	var burst: Array[Texture2D] = []
	for i in 7:
		var pth3 := "res://assets/wani_burst_%d.png" % i
		if ResourceLoader.exists(pth3):
			burst.append(load(pth3))
			var mp3 := "res://assets/masks/wani_burst_%d_mask.png" % i
			if ResourceLoader.exists(mp3):
				cru_masks["burst_%d" % i] = load(mp3)
	if burst.size() == 7:
		cru_frames["burst"] = burst
	hug_mat = ShaderMaterial.new()
	hug_mat.shader = HUG_SHADER
	sprite = Sprite2D.new()
	sprite.texture = emerge_frames[0]
	front = Node2D.new()
	front.draw.connect(_draw_front)
	bend_mat = ShaderMaterial.new()
	bend_mat.shader = preload("res://bend.gdshader")
	trunk = Sprite2D.new()
	trunk.centered = false
	trunk.region_enabled = true
	trunk.visible = false
	cru_base = Sprite2D.new()
	cru_base.centered = false
	cru_base.region_enabled = true
	cru_base.visible = false
	sprite.centered = false
	sprite.offset = Vector2(-128, -FEET_Y - 1)
	add_child(cru_base)
	add_child(trunk)
	for i in SEG_N:
		var sg := Sprite2D.new()
		sg.centered = false
		sg.region_enabled = true
		sg.visible = false
		add_child(sg)
		segs.append(sg)
	add_child(sprite)
	add_child(front)
	mound_frames = GooMound.load_frames()
	mound = Sprite2D.new()
	mound.centered = false
	mound.offset = Vector2(-128, -232)
	mound.visible = false
	add_child(mound)
	anim_t = -randf_range(0.0, 0.6)   # 2体の出現タイミングを少しずらす


func active() -> bool:
	return not state in ["emerge", "swallow", "idle", "sink", "lurk", "ambush", "swallowed", "pulldown", "under", "pillar", "crucify"]


func _process(delta: float) -> void:
	anim_t += delta
	z_index = int(position.y)   # 手前にいるほど前に描く
	sprite.flip_h = facing > 0
	sprite.scale = Vector2.ONE
	sprite.position = Vector2.ZERO
	sprite.region_enabled = false
	sprite.offset = Vector2(-128, -FEET_Y - 1)
	trunk.visible = false
	cru_base.visible = false
	for sg in segs:
		sg.visible = false
	front.queue_redraw()
	mound.visible = false
	if state == "pulldown" or state == "under":
		_update_pull(delta)
		# 盛り上がったドロドロ（沈みはじめは小さめにせり上がる）
		if mound_frames.size() == 8 and (state == "under" or under_t > 0.75):
			mound.visible = true
			var mp: Array = mound_player.step(delta, 0.7)
			mound.texture = mound_frames[mp[0]]
			mound.position = mp[1]
			mound.flip_h = mp[2]
		return

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
		swallow_t += delta
		if swallow_t < 0.8:
			# サメの大口に呑まれながら、主人公を抱えたままガクガク沈んでいく
			var k := swallow_t / 0.8
			var f := int(swallow_t * 14.0) % 9
			sprite.texture = anims["hug"][f]
			hug_mat.set_shader_parameter("cat_mask", anim_masks["hug"][f])
			hug_mat.set_shader_parameter("contamination", main.player.contamination())
			var vh := lerpf(float(FEET_Y), 0.0, pow(k, 1.6))
			sprite.region_enabled = true
			sprite.region_rect = Rect2(0, 0, 256, maxf(vh, 1.0))
			sprite.offset = Vector2(-128, -maxf(vh, 1.0))
			sprite.position = Vector2(sin(swallow_t * 80.0) * 3.0, 0).round()
			sprite.visible = true
			return
		# サメの腹の中（主人公と一緒に地中）
		if is_instance_valid(swallowed_by):
			position = swallowed_by.position
		sprite.material = null
		sprite.visible = false
		return
	if main.game_over and state == "crucify":
		_update_crucify(delta)   # 力尽きても揺らし続ける
		return
	if main.game_over:
		state = "idle"
		sprite.visible = true
		return
	if state == "pillar" or state == "crucify":
		_update_crucify(delta)
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
		spread_t = 0.5
		main.add_goop(position, 170.0, 0.15)
	# 動いた跡にはべったりペンキが残る（ナメクジのように）
	if absf(position.x - last_x) + absf(position.y - last_y) > 0.3:
		main.add_goop(position, 120.0, 0.6 * delta * 10.0)

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
			# 締め付けている間も、まわりにペンキがボタボタ広がっていく
			if fmod(hold_t, 0.5) < delta:
				main.add_goop(position + Vector2(randf_range(-90, 90), randf_range(-25, 25)), randf_range(50, 100), 0.35)
				if randf() < 0.5:
					main.splat_wall(Vector2(position.x + randf_range(-160, 160), main.FLOOR_TOP - randf_range(10, 150)), randf_range(25, 45))
			# しばらく抱えたら、そのまま床のドロドロの中へ引きずり込む
			if hold_t > pull_at and slide_v == 0.0 and p.state == "grabbed":
				state = "pulldown"
				under_t = 0.0
				main.sfx.play("defeat", -3.0)
				return
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
			# 泡の上をジャンプで越えようとした → 真下から粘液の柱で突き上げて磔にする
			if p.z > 25.0 and absf(dx) < 70.0 and absf(to_p.y) < 30.0 and p.state == "normal" and p.invuln <= 0.0:
				_start_pillar(p)
				return
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


# ---------- 磔（ジャンプで越えようとしたときの罰） ----------
func _start_pillar(p) -> void:
	state = "pillar"
	cru_t = 0.0
	position.x = p.position.x
	position.y = p.position.y
	sprite.visible = true
	main.release_token(self)
	main.request_token(self)
	p.get_crucified(self)
	main.sfx.play("assist", 2.0)
	main.sfx.play("grab", 0.0)
	main.zoom_moment(position + Vector2(0, -150), 1.2)
	main.add_goop(position, 220.0, 0.8)
	for i in 5:
		main.splat_wall(Vector2(position.x + randf_range(-220, 220), main.FLOOR_TOP - randf_range(10, 240)), randf_range(40, 75))


func _update_crucify(delta: float) -> void:
	var p = main.player
	cru_t += delta
	sprite.material = hug_mat
	hug_mat.set_shader_parameter("contamination", p.contamination())
	var has_art: bool = cru_frames.has("pillar") and cru_frames.has("crucify")
	if (p.state != "crucified" and p.state != "defeated") or p.crucifier != self:
		_end_hold()
		sprite.position = Vector2.ZERO
		sprite.visible = true
		state = "emerge"
		anim_t = 0.6
		return
	if state == "pillar":
		# 粘液の柱がグチュルルッと飛び出して、主人公を絡め取る（生成アニメ）→ 柱のまま少し震える
		sprite.region_enabled = false
		sprite.offset = Vector2(-128, -FEET_Y - 1)
		if cru_frames.has("burst") and cru_t < 0.6:
			var bi := clampi(int(cru_t / 0.6 * 7.0), 0, 6)
			sprite.texture = cru_frames["burst"][bi]
			_set_mask("burst", bi)
			sprite.position = Vector2.ZERO
		else:
			sprite.texture = cru_frames["pillar"] if has_art else IDLE
			_set_mask("pillar")
			sprite.position = Vector2(sin(cru_t * 80.0) * 2.0, 0).round()
		# 柱のまま少し震えてから、ワニの体に変わる
		if cru_t > 1.1:
			state = "crucify"
			cru_t = 0.0
			main.sfx.play("grab_loop", 2.0)
			main.add_goop(position, 160.0, 0.5)
		return
	# 晒し上げ：十字のポーズのままネットリぐらぐら揺らす。ときどきガクンと揺さぶる
	var transform_k := clampf(cru_t / 0.45, 0.0, 1.0)
	var tex: Texture2D
	if has_art and cru_frames.has("morph") and transform_k < 1.0:
		var arr: Array = cru_frames["morph"]
		var mi := clampi(int(transform_k * arr.size()), 0, arr.size() - 1)
		tex = arr[mi]
		_set_mask("morph", mi)
	else:
		var key := "crucify"
		if cru_stage == 2 and cru_frames.has("absorb2"):
			key = "absorb2"
		elif cru_stage >= 1 and cru_frames.has("absorb1"):
			key = "absorb1"
		tex = cru_frames[key] if has_art else IDLE
		_set_mask(key)
		# 奥・手前に揺れるループ（手前に倒れ込む／奥へ反る、の端で長めに止まる）
		if key == "crucify" and cru_frames.has("sway"):
			var dp := fmod(depth_phase, TAU) / TAU          # 0〜1
			var eased := dp + sin(dp * TAU * 2.0) * 0.06    # 端（コマ1付近と5付近）でためる
			var si := posmod(int(eased * 8.0), 8)
			tex = cru_frames["sway"][si]
			_set_mask("sway", si)
	# メトロノーム：端で一瞬ためて、ぐーっと反対側へ。ときどき勢い余って大きく振れる
	var prev_c := cos(met_phase)
	met_phase += delta * met_speed
	var c := cos(met_phase)
	if signf(c) != signf(prev_c):
		# 切り返し：ペンキがたっぷり飛び散る
		met_amp = 1.8 if randf() < 0.3 else randf_range(0.9, 1.2)
		var side := signf(sin(met_phase))
		main.sfx.play_any(["gurgle", "grab_loop"], 0.0)
		for i in 3:
			main.splat_wall(Vector2(position.x + side * randf_range(60, 260), main.FLOOR_TOP - randf_range(30, 260)), randf_range(35, 70) * met_amp)
			main.add_goop(position + Vector2(side * randf_range(40, 200), randf_range(-40, 40)), randf_range(50, 110), 0.5)
		for i in int(10 * met_amp):
			drip_vis.append({"x": side * randf_range(20.0, 110.0), "y": -randf_range(170.0, 260.0), "v": -randf_range(60.0, 200.0), "vx": side * randf_range(80.0, 260.0)})
		for i in 2:
			p.add_dirt(p.random_body_point(), 2)
	# 取り込み：段階に合わせて、粘液が主人公を下から呑み込んでいく（UVで0.48=首から下 / 0.35=帽子の先だけ残る）
	var target_y: float = [1.0, 0.48, 0.35][cru_stage]
	absorb_y = move_toward(absorb_y, target_y, delta * 0.12)
	hug_mat.set_shader_parameter("absorb_y", absorb_y)
	depth_phase += delta * met_speed * 0.55
	var s := sin(met_phase)
	var sx: float = 16.0 * met_amp * met_scale * signf(s) * pow(absf(s), 0.4)   # 左右は控えめ（主役は奥行きのループ）
	hist.push_front(sx)
	if hist.size() > 40:
		hist.pop_back()
	sway = Vector2(sx, -absf(sx) * 0.22)   # 振り切るとぐにゃっと沈む
	# 高く持ち上げる：上半身を持ち上げ、そのぶん粘液の幹を引き伸ばす（床の水たまりは動かさない）
	var lift: float = CRU_LIFT * ease(clampf(cru_t / 0.5, 0.0, 1.0), 0.4) - sway.y
	var feet := float(FEET_Y + 1)
	sprite.texture = tex
	sprite.region_enabled = true
	sprite.region_rect = Rect2(0, 0, 256, CRU_SPLIT)
	sprite.offset = Vector2(-128, -feet)
	sprite.position = Vector2(sway.x, -lift).round()
	# 幹：1枚を縦に引き伸ばし、シェーダーで行ごとになめらかにしならせる（下ほど小さく、遅れて追いかける）
	var total: float = CRU_TRUNK + lift
	var lag_x: float = hist[mini(14, hist.size() - 1)]
	for sg in segs:
		sg.visible = false
	var fl := -1.0 if sprite.flip_h else 1.0
	trunk.visible = true
	trunk.texture = tex
	trunk.material = bend_mat
	trunk.flip_h = sprite.flip_h
	trunk.region_rect = Rect2(0, CRU_SPLIT, 256, CRU_TRUNK)
	trunk.offset = Vector2(-128, 0)
	trunk.scale = Vector2(1.0, total / CRU_TRUNK)
	trunk.position = Vector2(0, -feet + CRU_SPLIT - lift)
	bend_mat.set_shader_parameter("v0", float(CRU_SPLIT) / 256.0)
	bend_mat.set_shader_parameter("v1", float(CRU_SPLIT + CRU_TRUNK) / 256.0)
	bend_mat.set_shader_parameter("total_h", roundf(total))
	bend_mat.set_shader_parameter("band_y0", float(CRU_SPLIT))
	bend_mat.set_shader_parameter("band_h", float(CRU_TRUNK))
	bend_mat.set_shader_parameter("flow", floorf(cru_t * 26.0))
	bend_mat.set_shader_parameter("top_off", roundf(sway.x) * fl)
	bend_mat.set_shader_parameter("mid_off", lag_x * 0.45 * fl)
	cru_base.visible = true
	cru_base.texture = tex
	cru_base.material = hug_mat
	cru_base.region_rect = Rect2(0, CRU_SPLIT + CRU_TRUNK, 256, 256 - CRU_SPLIT - CRU_TRUNK)
	cru_base.offset = Vector2(-128, -feet + CRU_SPLIT + CRU_TRUNK)
	cru_base.flip_h = sprite.flip_h
	cru_base.position = Vector2.ZERO
	# 揺れるたびにネバネバが垂れ落ちて、根元に溜まる
	if fmod(cru_t, 0.25) < delta:
		main.add_goop(position + Vector2(randf_range(-50, 50), randf_range(-15, 15)), randf_range(40, 80), 0.3)
	if randf() < 0.5:
		drip_vis.append({"x": randf_range(-90.0, 90.0) + sway.x, "y": -randf_range(140.0, 240.0), "v": 0.0, "vx": 0.0})
	if drip_vis.size() > 60:
		drip_vis.pop_front()
	for d in drip_vis:
		d.v += 500.0 * delta
		d.y += d.v * delta
		d.x += d.vx * delta
	drip_vis = drip_vis.filter(func(d): return d.y < 0.0)
	front.queue_redraw()


func _set_mask(key: String, idx := -1) -> void:
	var m = cru_masks.get(key if idx < 0 else "%s_%d" % [key, idx])
	hug_mat.set_shader_parameter("cat_mask", m)


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
	pull_at = randf_range(3.5, 6.5)
	sprite.material = hug_mat
	main.player.sprite.visible = false
	main.player.hidden_in_hug = true


func _end_hold() -> void:
	absorb_y = 1.0
	if hug_mat:
		hug_mat.set_shader_parameter("absorb_y", 1.0)
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


# ---------- 引きずり込みと地中攻撃 ----------
func is_dragging() -> bool:
	return state == "under"


func _update_pull(delta: float) -> void:
	var p = main.player
	under_t += delta
	if state == "pulldown":
		# 抱えたまま、床に沈んでいく（絵の下側から床に呑まれる）
		_update_hold_sprite(delta, p)
		var k := clampf(under_t / 1.4, 0.0, 1.0)
		var vh := lerpf(float(FEET_Y), 0.0, k * k)
		sprite.region_enabled = true
		sprite.region_rect = Rect2(0, 0, 256, maxf(vh, 1.0))
		sprite.offset = Vector2(-128, -maxf(vh, 1.0))
		sprite.position.y = sin(under_t * 30.0) * 1.5
		main.add_goop(position, 120.0, 0.04)
		if p.state != "grabbed":
			return
		if k >= 1.0:
			_end_hold()
			sprite.visible = false
			state = "under"
			under_t = 0.0
			view_mode = "splat"   # 小窓（胃袋の中）はサメ専用。ワニの地中は床の噴き上がりで見せる
			p.get_swallowed(self, false)
		return
	# 地中：主人公を抱えたまま床の下を這い回る
	if p.state != "swallowed" or p.swallower != self:
		sprite.visible = true
		state = "emerge"
		anim_t = 0.6
		return
	wander += delta
	var dir := Vector2(cos(wander * 0.6), sin(wander * 1.1) * 0.5)
	position += dir * 45.0 * delta
	_clamp()
	main.add_goop(position, 60.0, 0.05)
	gurgle_t -= delta
	if gurgle_t <= 0.0:
		gurgle_t = randf_range(0.35, 0.7)
		main.sfx.play_any(["gurgle", "grab_loop"], -2.0)
	if view_mode == "splat":
		erupt_t -= delta
		if erupt_t <= 0.0:
			erupt_t = randf_range(0.3, 0.7)
			var at := position + Vector2(randf_range(-60.0, 60.0), randf_range(-10.0, 10.0))
			main.add_goop(at, randf_range(60.0, 110.0), 0.5)
			main.splat_wall(Vector2(at.x + randf_range(-80.0, 80.0), main.FLOOR_TOP - randf_range(10.0, 170.0)), randf_range(30.0, 55.0))
			main.sfx.play("hit", -6.0)


## 床に沈んでいく境目・地中で暴れている盛り上がりを、絵より手前に描く
func _draw_front() -> void:
	if state == "crucify":
		for d in drip_vis:
			var big: bool = absf(d.vx) > 1.0
			var r: float = 5.0 if big else 2.5
			front.draw_circle(Vector2(d.x, d.y).round(), r + 1.5, Color("5a1240"))
			front.draw_circle(Vector2(d.x, d.y).round(), r, Color("ec5a9e") if int(d.x) % 3 else Color("f9d84d"))
		return
	if mound_frames.size() == 8:
		return   # 生成したドット絵の盛り上がりを使う
	if state == "pulldown":
		var k := clampf(under_t / 1.4, 0.0, 1.0)
		GooMound.draw(front, under_t, 120.0 + 60.0 * k, 0.4 + 0.6 * k)
	elif state == "under":
		GooMound.draw(front, under_t, 140.0, 0.8)


## 抱きつかれた瞬間：勢いでペンキが派手に飛び散る
func _hug_impact(p) -> void:
	for i in 7:
		p.add_dirt(p.random_body_point(), 3)
	p.damage(6.0)
	for i in 6:
		main.splat_wall(Vector2(p.position.x + randf_range(-220.0, 220.0), p.position.y - randf_range(50.0, 260.0)), randf_range(35.0, 70.0))
	main.add_goop(p.position, 260.0, 0.6)
	for i in 4:
		main.add_goop(p.position + Vector2(randf_range(-200, 200), randf_range(-40, 40)), randf_range(40, 90), 0.5)
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
	main.release_token(self)
	state = "swallowed"
	swallowed_by = shark
	# サメ側に「ワニごと呑み込む」アニメがあれば、そちらに2体とも描かれているので自分はすぐ消える
	swallow_t = 0.8 if shark.anims.has("combo") else 0.0
	# 抱えた主人公ごと、サメの口の中へ沈んでいく姿を少しだけ見せる（抱きつきの絵のまま）
	sprite.material = hug_mat
	sprite.visible = true


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
	if state == "pillar" or state == "crucify":
		_end_hold()
		sprite.position = Vector2.ZERO
		main.release_token(self)
		state = "recover"
		t = 1.0
		stun = 1.2
		return
	if state == "under" or state == "pulldown":
		# 地中から脱出された：床から形成し直す
		_end_hold()
		sprite.visible = true
		main.release_token(self)
		state = "emerge"
		anim_t = 0.6
		return
	_end_hold()
	stun = 1.2
	vel_x = -facing * 150.0
	state = "recover"
	t = 0.0


## 負けたあとの追撃の段階（finisher から呼ぶ）
func set_crucify_stage(st: int) -> void:
	if st == cru_stage:
		return
	cru_stage = st
	met_speed = [1.3, 0.9, 0.7][st]
	met_scale = [1.0, 1.3, 1.6][st]
	main.sfx.play("defeat", -2.0)
	main.sfx.play_any(["gurgle", "grab_loop"], 2.0)
	main.add_goop(position, 260.0, 0.8)
	for i in 6:
		main.splat_wall(Vector2(position.x + randf_range(-300, 300), main.FLOOR_TOP - randf_range(10, 260)), randf_range(50, 90))
