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
var sandwicher = null    # 磔の正面から抱きついているドーベルマン
var push := 0.0          # ドーベルマンを押し返すゲージ
var held_by = null       # 羽交い締めにしているドーベルマン
var engulfer = null      # ヒップドロップで取り込んでいる相手（ドーベルマン → ひり出された粘液のとぐろ）
var pin_frames: Array[Texture2D] = []   # 地面で上下から挟まれている合成絵（cat_pinned_0..）
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
# 疲労：HPで段階（0=元気 1=へばり 2=ふらふら）、汚れの量で重さ（遅さ）を上乗せ
var tired_anims := {}        # "idle1" / "walk1" / "idle2" / "walk2" / "stumble" / "getup" / "land" → コマ配列（素材があれば）
var land_t := 0.0            # 着地でひざが沈んでいる残り時間
var stumble_t := 0.0         # つまずいている残り時間
var wobble := 0.0
var sweat: Array = []
var collapse_again := false  # 起き上がりかけてまた崩れる
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
	var pi := 0
	while ResourceLoader.exists("res://assets/cat_pinned_%d.png" % pi):
		pin_frames.append(load("res://assets/cat_pinned_%d.png" % pi))
		pi += 1
	for k in ["idle1", "walk1", "idle2", "walk2", "stumble", "getup", "land"]:
		var arr: Array[Texture2D] = []
		var i := 0
		while ResourceLoader.exists("res://assets/cat_%s_%d.png" % [k, i]):
			arr.append(load("res://assets/cat_%s_%d.png" % [k, i]))
			i += 1
		if arr.size() > 0:
			tired_anims[k] = arr
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


func fatigue() -> int:
	var r := hp / HP_MAX
	if r > 0.6:
		return 0
	return 1 if r > 0.3 else 2


func _tired(k: String, idx: int, fallback: Texture2D) -> Texture2D:
	if tired_anims.has(k):
		var arr: Array = tired_anims[k]
		return arr[posmod(idx, arr.size())]
	return fallback


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
## ダメージの調整（長く弄ばれるように）：捕まっている間の削れはかなり控えめに、殴られる・抱きつかれる瞬間はやや控えめに
const RESTRAINED_DMG := 0.3   # 捕まっている間（抱きつき・磔・挟み込み・羽交い締め・腹の中）
const HIT_DMG := 0.6          # それ以外（殴られる・抱きつかれた瞬間など）
const DIRT_DMG := 0.25        # 汚れによる上乗せ（汚れきって 1.25 倍）
func damage(amount: float) -> void:
	if state == "defeated":
		return
	var restrained: bool = state in ["grabbed", "held", "crucified", "pinned", "swallowed", "engulfed"]
	hp -= amount * (RESTRAINED_DMG if restrained else HIT_DMG) * (1.0 + DIRT_DMG * contamination())
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
	# 地面でワニとドーベルマンに挟まれたまま力尽きた：2体がさらに抱き合って主人公を体内に取り込み、そのまま抱き潰し続ける
	if state == "pinned" and ResourceLoader.exists("res://assets/trio_absorb_0.png"):
		trio_finish = true
		trio_t = 0.0
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
		"held":
			_update_held(delta)
		"pinned":
			_update_pinned(delta)
		"engulfed":
			_update_engulfed(delta)
	_update_frame(delta)
	z_index = int(position.y)   # 手前にいるほど前に描く
	sprite.flip_h = facing < 0
	if state != "grabbed" and state != "crucified" and state != "held":
		hidden_in_hug = false
	if state == "crucified":
		hidden_in_hug = true
	sprite.visible = state != "defeated" and state != "swallowed" and state != "engulfed" and not hidden_in_hug and not (invuln > 0.0 and state == "normal" and int(invuln * 20) % 2 == 0)
	var sandwiching: bool = state == "pinned" or trio_finish
	if not sandwiching and pin_base != null:
		pin_base.visible = false
		pin_over.visible = false
	elif sandwiching and pin_base != null and pin_base.visible:
		sprite.visible = false   # サンドイッチの絵の中に描かれている
	queue_redraw()


## 地面のサンドイッチ（3対1から抜けた後）：下にワニ（抱きつきの絵を横倒し・上下反転）、
## 真ん中に主人公、上からドーベルマンがのしかかってネバネバに抱きしめる。絵がそろっていれば true
var pin_base: Sprite2D
var pin_over: Sprite2D
var pin_mat: ShaderMaterial
## ワニとドーベルマンが抱き合って主人公を挟んだ絵（3対1の小窓と、抜けた後の地面で使う）
var embrace_frames: Array = []
var embrace_masks: Array = []
var embrace_tex: Texture2D = null    # 今のコマ（小窓が読む）
var embrace_mask: Texture2D = null
## 締め上げのループ：寄せきった所で止めて、ゆっくり緩む
func _load_seq(prefix: String, tex: Array, masks: Array) -> void:
	var i := 0
	while ResourceLoader.exists("res://assets/%s_%d.png" % [prefix, i]):
		tex.append(load("res://assets/%s_%d.png" % [prefix, i]))
		var mp := "res://assets/masks/%s_%d_mask.png" % [prefix, i]
		masks.append(load(mp) if ResourceLoader.exists(mp) else null)
		i += 1


## 3対1の挟み込み：基本は「締め上げ」、ときどき「押しつぶし（左右に擦りつぶす）」に切り替える
var pin_intro := ""          # 3対1から抜けた直後の出現シーン："rise" / "drag" / ""
var pin_intro_t := 0.0
var pin_shark = null
var pin_sink_t := 8.0
var rise_frames: Array = []
var rise_masks: Array = []
var drag_frames: Array = []
var drag_masks: Array = []
var trio_finish := false     # 挟まれたまま負けた（取り込み→抱き潰しが続く）
var trio_t := 0.0
const TRIO_ABSORB_T := 3.0   # 抱き寄せる→押しつけて密着→ドプンと沈む
var absorb_frames: Array = []
var absorb_masks: Array = []
var absorbed_frames: Array = []
var absorbed_masks: Array = []
var crush_frames: Array = []
var crush_masks: Array = []
const EMBRACE_CYCLE := 1.25    # 1ループの秒数（少し速め）
const EMBRACE_PATTERN := [0, 0, 0, 1, 1]   # 0=締め上げ 1=押しつぶし を1ループずつ
func embrace_step() -> void:
	if embrace_frames.is_empty():
		_load_seq("embrace", embrace_frames, embrace_masks)
		_load_seq("embrace_crush", crush_frames, crush_masks)
		if embrace_frames.is_empty():
			embrace_frames.append(null)
	if embrace_frames[0] == null:
		return
	var tt := Time.get_ticks_msec() / 1000.0
	if pin_intro != "" and not trio_finish:
		if rise_frames.is_empty():
			_load_seq("trio_rise", rise_frames, rise_masks)
			_load_seq("trio_drag", drag_frames, drag_masks)
		var arr: Array = rise_frames if pin_intro == "rise" else drag_frames
		var marr: Array = rise_masks if pin_intro == "rise" else drag_masks
		if not arr.is_empty():
			var f := pin_intro_t / (PIN_RISE_T if pin_intro == "rise" else PIN_SINK_T)
			var ii := clampi(int(f * arr.size()), 0, arr.size() - 1)
			embrace_tex = arr[ii]
			embrace_mask = marr[ii]
			return
	if trio_finish:
		if absorb_frames.is_empty():
			_load_seq("trio_absorb", absorb_frames, absorb_masks)
			_load_seq("trio_absorbed", absorbed_frames, absorbed_masks)
		if trio_t < TRIO_ABSORB_T and not absorb_frames.is_empty():
			# さらに抱き合って、主人公がゆっくり2体の体の中に沈んでいく
			var ai := clampi(int(trio_t / TRIO_ABSORB_T * absorb_frames.size()), 0, absorb_frames.size() - 1)
			embrace_tex = absorb_frames[ai]
			embrace_mask = absorb_masks[ai]
			return
		if not absorbed_frames.is_empty():
			# 取り込んだまま、目を細めて抱き潰し続ける（終わらない）
			var li := int((trio_t - TRIO_ABSORB_T) * 5.0) % absorbed_frames.size()
			embrace_tex = absorbed_frames[li]
			embrace_mask = null
			return
	var cyc_i := int(tt / EMBRACE_CYCLE)
	var use_crush: bool = not crush_frames.is_empty() and EMBRACE_PATTERN[cyc_i % EMBRACE_PATTERN.size()] == 1
	var arr: Array = crush_frames if use_crush else embrace_frames
	var marr: Array = crush_masks if use_crush else embrace_masks
	var f := fmod(tt, EMBRACE_CYCLE) / EMBRACE_CYCLE
	var idx := clampi(int(f * arr.size()), 0, arr.size() - 1)
	embrace_tex = arr[idx]
	embrace_mask = marr[idx]
func _draw_sandwich() -> bool:
	var w = null
	for e in main.enemies:
		if is_instance_valid(e) and e.state == "pinned":
			w = e
	if w == null:
		return false
	if pin_base == null:
		pin_base = Sprite2D.new()
		pin_base.centered = true
		pin_base.region_enabled = true
		pin_base.rotation = 0.0
		add_child(pin_base)
		pin_over = Sprite2D.new()
		add_child(pin_over)
		pin_mat = ShaderMaterial.new()
		pin_mat.shader = load("res://hug_dirt.gdshader")
	var tt := Time.get_ticks_msec() / 1000.0
	var sq := absf(sin(tt * 3.2))
	sprite.visible = false
	pin_over.visible = false
	pin_base.visible = true
	embrace_step()
	if embrace_tex != null:
		# 下のワニ（床のベトベトに半分沈む）と上からのしかかるドーベルマンが抱き合い、胸の間に主人公が挟まっている（等倍・寝かせた向きの絵）
		pin_base.rotation = 0.0
		pin_base.texture = embrace_tex
		pin_base.region_rect = Rect2(0, 0, 256, 256)
		# 主人公の部分のマスクがあるときだけ汚れを乗せる（無ければそのまま）
		pin_mat.set_shader_parameter("cat_mask", embrace_mask)
		pin_mat.set_shader_parameter("contamination", contamination())
		pin_base.material = pin_mat if embrace_mask != null else null
		# 上から押しつぶされるたびに、ぐにゅっと潰れる
		pin_base.scale = Vector2.ONE
		pin_base.position = Vector2(0, -104.0)   # 絵の下端（床の水たまり、236行目）を床に合わせる（少し沈める）
		return true
	if not w.anims.has("hug"):
		return false
	var f := int(tt * 8.0) % 16
	var fi := f if f < 9 else 16 - f
	pin_base.rotation = -PI / 2.0
	pin_base.texture = w.anims["hug"][fi]
	pin_base.region_rect = Rect2(24, 0, 150, 205)
	w.hug_mat.set_shader_parameter("cat_mask", w.anim_masks["hug"][fi])
	w.hug_mat.set_shader_parameter("contamination", contamination())
	pin_base.material = w.hug_mat
	pin_base.position = Vector2(0, -78.0 + sq * 3.0).round()
	return true


## 取り込んだあとも攻撃が続く：ネチャネチャという音と、床・壁へのペンキ
func _trio_finish_step(delta: float) -> void:
	trio_t += delta
	var before := int((trio_t - delta) / 0.45)
	if int(trio_t / 0.45) != before:
		main.sfx.play_any(["gurgle", "grab_loop"], -4.0 if trio_t > TRIO_ABSORB_T else -1.0, 0.2)
		main.add_goop(position + Vector2(randf_range(-80, 80), randf_range(-10, 10)), 60.0, 0.25)
		if trio_t > TRIO_ABSORB_T and randf() < 0.4:
			main.splat_wall(Vector2(position.x + randf_range(-160, 160), main.FLOOR_TOP - randf_range(20, 160)), randf_range(25, 50))


func _update_frame(delta: float) -> void:
	var f := 0
	if attack_timer > 0.0:
		f = 1 if attack_timer > 0.12 else 2
	elif cleaning:
		f = 3
	sprite.texture = FRAMES[f]
	sprite.position = Vector2(0.0, -z)
	sprite.scale = Vector2.ONE
	var ft := fatigue()
	if state == "normal":
		sprite.rotation = 0.0
	if state == "normal" and stumble_t > 0.0:
		# つまずき：前につんのめって、ひざをつく
		var k := 1.0 - stumble_t / 0.9
		sprite.texture = _tired("stumble", int(k * 8.0), FRAMES[0])
		if not tired_anims.has("stumble"):
			sprite.rotation = facing * 0.35 * sin(k * PI)
			sprite.position.y += 10.0 * sin(k * PI)
	elif state == "normal" and on_floor and land_t > 0.0 and f == 0:
		# 着地：ひざがガクッと沈む（疲れているほど深く長く）
		sprite.texture = _tired("land", int((1.0 - land_t / 0.45) * 4.0), _tired("idle%d" % ft, 0, IDLE_ANIM[0]) if ft > 0 else IDLE_ANIM[0])
		if not tired_anims.has("land"):
			var sq := land_t / (0.2 + 0.12 * ft)
			sprite.scale = Vector2(1.0 + 0.12 * sq, 1.0 - 0.16 * sq)
	elif state == "normal" and on_floor and vel.length() > 8.0 and f == 0:
		# 歩きアニメ（速さに合わせてコマ送り）。疲れていると足を引きずり、ふらふらは左右によろける
		bob += delta * vel.length() / (14.0 if ft == 0 else 11.0)
		sprite.texture = WALK[int(bob) % 4] if ft == 0 else _tired("walk%d" % ft, int(bob), WALK[int(bob) % 4])
		if ft > 0:
			sprite.rotation = facing * (0.04 if ft == 1 else 0.07) + sin(bob * 0.8) * (0.03 if ft == 1 else 0.08)
			sprite.position.y += absf(sin(bob * 1.57)) * (1.0 if ft == 1 else 2.0)
	elif state == "normal" and f == 0:
		# 待機の呼吸（疲れているほど肩で大きく、速く息をする）
		var ms: int = [220, 160, 120][ft]
		var fi := int(Time.get_ticks_msec() / ms)
		sprite.texture = IDLE_ANIM[fi % 4] if ft == 0 else _tired("idle%d" % ft, fi, IDLE_ANIM[fi % 4])
		if ft > 0:
			# 肩で息をする：前かがみ気味に、呼吸に合わせて縦に伸び縮み
			var br := sin(Time.get_ticks_msec() / 1000.0 * (6.0 if ft == 1 else 8.5))
			sprite.scale = Vector2(1.0 - 0.015 * br * ft, 1.0 + 0.025 * br * ft)
			sprite.rotation = facing * (0.05 if ft == 1 else 0.09)
	elif state == "pinned" or trio_finish:
		if trio_finish:
			_trio_finish_step(delta)
		if _draw_sandwich():
			pass
		elif pin_frames.size() > 0:
			sprite.texture = pin_frames[int(Time.get_ticks_msec() / 110) % pin_frames.size()]
		else:
			# 仮：横倒しで小刻みにもがく
			sprite.texture = FRAMES[1 + int(Time.get_ticks_msec() / 90) % 3]
			sprite.rotation = facing * PI * 0.5
			sprite.position = Vector2(facing * 55.0, -32.0) + Vector2(randf_range(-1, 1), 0).round()
	elif state == "held":
		sprite.texture = FRAMES[1 + int(Time.get_ticks_msec() / 90) % 3]
		sprite.position.x += randf_range(-1.5, 1.5)
	elif state == "slipped":
		sprite.position = Vector2(facing * 55.0, -32.0)   # 横倒しで床に寝そべる（足元を中心に）
		if tired_anims.has("getup") and slip_t < 0.5:
			# 起き上がり（素材があれば）
			sprite.rotation = 0.0
			sprite.position = Vector2(0.0, 0.0)
			sprite.texture = _tired("getup", int((1.0 - slip_t / 0.5) * 8.0), FRAMES[0])


func _update_normal(delta: float) -> void:
	touch_mash = 0   # 捕まっていないときのタップは持ち越さない
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

	var ft := fatigue()
	land_t -= delta
	if stumble_t > 0.0:
		stumble_t -= delta
		inp = Vector2.ZERO
	if land_t > 0.0 and ft > 0:
		inp *= 0.3
	# ペンキの重さ（汚れ）× 疲れ
	var speed: float = 140.0 * (1.0 - 0.55 * c) * [1.0, 0.8, 0.6][ft] * (1.15 if main.touch_mode else 1.0)
	# ふらふら：歩いていると勝手に左右（奥行き）によろけ、ときどきつまずく
	if ft == 2 and inp != Vector2.ZERO:
		wobble += delta * 3.1
		inp.y += sin(wobble) * 0.45
		if stumble_t <= 0.0 and hitstun <= 0.0 and randf() < 0.13 * delta * (1.0 + c):
			_stumble()
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
		vz = 360.0 * (1.0 - 0.4 * c) * [1.0, 0.82, 0.62][ft]
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
			var ftl := fatigue()
			land_t = [0.12, 0.3, 0.45][ftl]
			# ふらふらだと着地でそのまま尻もちをつくことがある
			if ftl == 2 and landing_speed > 200.0 and randf() < 0.35:
				_slip()
				return
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
	for e in main.enemies + main.dobes:
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
	var trio: bool = swallower.has_method("is_trio") and swallower.is_trio()
	struggle -= (0.26 if trio else (0.2 if swallow_combo else 0.15)) * delta
	var d := _mash_input()
	if d != 0 and d != last_dir:
		struggle += 0.035 if trio else (0.05 if swallow_combo else 0.07)
		last_dir = d
	drip_timer += delta
	if drip_timer > (0.1 if trio else (0.14 if swallow_combo else 0.24)):
		drip_timer = 0.0
		add_dirt(random_body_point(), 3 if trio else 2)
		damage(0.9 if trio else (1.0 if swallow_combo else 1.2))
		if state == "swallowed":
			main.sfx.play("grab_loop", -4.0, 0.3)
	struggle = clampf(struggle, 0.0, 1.0)
	if struggle >= 1.0 and state == "swallowed" and trio:
		# 3対1から抜けた…が、吐き出された先でワニ（下）とドーベルマン（上）に地面で挟まれる
		var s3 = swallower
		swallower = null
		state = "pinned"
		# すぐには挟まない：地面のネバネバが盛り上がって挟み込みに移る（rise）か、そのまま地中へ引きずり戻される（drag）
		pin_shark = s3
		pin_intro = "rise"        # 挟まれた姿のまま、地面から溶け出るように湧いてくる
		pin_intro_t = 0.0
		pin_sink_t = randf_range(6.0, 10.0)
		struggle = 0.15
		last_dir = 0
		vel = Vector2.ZERO
		z = 0.0
		on_floor = true
		main.add_goop(position, 160.0, 0.6)
		main.sfx.play("grab", 0.0)
		main.zoom_moment(position + Vector2(0, -40), 0.9)
		s3.on_escaped()
		return
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


# ---------- ヒップドロップで尻から取り込まれる（ドーベルマン）→ 粘液のとぐろに包まれてひり出される ----------
func get_engulfed(holder) -> void:
	if state == "grabbed" and is_instance_valid(grabbed_by):
		grabbed_by = null
	state = "engulfed"
	engulfer = holder
	struggle = 0.15
	last_dir = 0
	vel = Vector2.ZERO
	z = 0.0
	vz = 0.0
	on_floor = true
	sprite.rotation = 0.0
	for i in 6:
		add_dirt(random_body_point(), 3)
	damage(5.0)
	main.sfx.play("defeat", -4.0)


## とぐろに入れ替わる（中身ごと受け渡す）
func pass_engulf(holder) -> void:
	engulfer = holder
	if state == "defeated":
		return
	struggle = 0.1
	last_dir = 0


func _update_engulfed(delta: float) -> void:
	if engulfer == null or not is_instance_valid(engulfer):
		state = "normal"
		return
	position = engulfer.position
	var in_mound: bool = engulfer.has_method("on_engulf_escape")
	# ドーベルマンの中ではほとんど抗えない（もがけるのは、とぐろになってから）
	var can_escape: bool = in_mound or (engulfer.has_method("engulf_can_escape") and engulfer.engulf_can_escape())
	struggle -= (0.12 if in_mound else 0.2) * delta
	var d := _mash_input()
	if d != 0 and d != last_dir:
		struggle += (0.06 if in_mound else 0.04) if can_escape else 0.0
		last_dir = d
		if in_mound:
			engulfer.on_struggle()
	drip_timer += delta
	if drip_timer > 0.28:
		drip_timer = 0.0
		add_dirt(random_body_point(), 2)
		damage(0.9)
	struggle = clampf(struggle, 0.0, 1.0)
	if struggle >= 1.0 and state == "engulfed":
		var e = engulfer
		engulfer = null
		position = e.position
		for i in 6:
			add_dirt(random_body_point(), 3)
		if in_mound:
			# とぐろが破裂して、ドロドロのまま転がり出る
			e.on_engulf_escape()
			state = "normal"
			_slip()
			invuln = 1.6
		else:
			# 呑み込まれきる前に尻から抜け出す
			state = "normal"
			invuln = 1.4
			on_floor = false
			vz = 260.0
			vel = Vector2(-e.facing * 200.0, 0.0)
			main.add_goop(position, 100.0, 0.4)
			main.sfx.play("escape")
			e.on_escaped()


# ---------- 羽交い締め（ドーベルマン）→ 正面でサメがゆっくり口を開ける ----------
func get_held(dobe) -> void:
	state = "held"
	held_by = dobe
	grabbed_by = null
	struggle = 0.2
	last_dir = 0
	vel = Vector2.ZERO
	z = 0.0
	on_floor = true
	hidden_in_hug = dobe.frames.has("hold")   # 合成絵があればそちらに描かれている
	for i in 3:
		add_dirt(random_body_point(), 2)
	main.sfx.play("grab")


## もがく入力：左右の押し始め。スマホのタップ（touch_mash）は「前回と逆の向き」として数える
var touch_mash := 0
func _mash_input() -> int:
	if Input.is_action_just_pressed("left"):
		return -1
	if Input.is_action_just_pressed("right"):
		return 1
	if touch_mash > 0:
		touch_mash -= 1
		return -last_dir if last_dir != 0 else 1
	return 0


func _update_held(delta: float) -> void:
	if held_by == null or not is_instance_valid(held_by):
		state = "normal"
		return
	# 口が開いていくほど焦って、振りほどく力が落ちていく（でも間に合えば助かる）
	struggle -= 0.16 * delta
	var d := _mash_input()
	if d != 0 and d != last_dir:
		struggle += 0.075
		last_dir = d
	drip_timer += delta
	if drip_timer > 0.3:
		drip_timer = 0.0
		add_dirt(random_body_point(), 1)
		damage(0.8)
	struggle = clampf(struggle, 0.0, 1.0)
	if struggle >= 1.0:
		var hb = held_by
		held_by = null
		state = "normal"
		invuln = 1.2
		vel = Vector2(facing * 180.0, 0.0)
		main.sfx.play("escape")
		hb.on_escaped()


# ---------- 地面で上下から挟まれる（3対1から抜けたあと） ----------
func _update_pinned(delta: float) -> void:
	if pin_intro != "":
		_update_pin_intro(delta)
		return
	_update_pinned_main(delta)


## 挟み込みの出入り：同じ「溶けて沈む」アニメを、出てくるときは逆再生、沈むときは順再生
const PIN_RISE_T := 2.2      # 挟まれた姿のまま地面から湧き出る
const PIN_SINK_T := 2.2      # 挟まれた姿のまま溶けて地面に沈む → 地中の3対1へ
func _update_pin_intro(delta: float) -> void:
	pin_intro_t += delta
	struggle = 0.15
	if fmod(pin_intro_t, 0.35) < delta:
		main.sfx.play_any(["gurgle", "grab_loop"], -3.0, 0.2)
		main.add_goop(position + Vector2(randf_range(-60, 60), randf_range(-8, 8)), 60.0, 0.25)
		add_dirt(random_body_point(), 2)
	if pin_intro == "rise" and pin_intro_t >= PIN_RISE_T:
		pin_intro = ""
		main.sfx.play("grab", 0.0)
		main.zoom_moment(position + Vector2(0, -40), 0.8)
	elif pin_intro == "sink" and pin_intro_t >= PIN_SINK_T:
		pin_intro = ""
		_drag_back_under()


## 地中へ引きずり戻される：サメの腹の中の3対1に戻る
func _drag_back_under() -> void:
	var sh = pin_shark
	var w = null
	for e in main.enemies:
		if is_instance_valid(e) and e.state == "pinned":
			w = e
	var d = null
	for x in main.dobes:
		if is_instance_valid(x) and x.state == "pin":
			d = x
	if sh == null or not is_instance_valid(sh) or w == null or d == null:
		return   # 戻れないときは、そのまま地面で挟み込み
	sh.position = position
	sh.caught_wani = w
	w.get_swallowed(sh)
	sh.caught_dobe = d
	d.get_swallowed(sh)
	sh.caught_player = get_swallowed(sh, true)
	sh._sink_after_attack()
	main.add_ring(position, 3.0)


func _update_pinned_main(delta: float) -> void:
	# ときどき、挟んだまま溶けて地面に沈み、地中へ引きずり戻す
	pin_sink_t -= delta
	if pin_sink_t <= 0.0:
		pin_sink_t = randf_range(6.0, 10.0)
		if randf() < 0.5 and pin_shark != null and is_instance_valid(pin_shark):
			pin_intro = "sink"
			pin_intro_t = 0.0
			main.sfx.play("gurgle", 0.0)
			return
	# 一度抜けたぶん少しだけ抜けやすい。そのかわり上からぐりぐり押しつけられて汚れる
	struggle -= 0.12 * delta
	var d := _mash_input()
	if d != 0 and d != last_dir:
		struggle += 0.08
		last_dir = d
	drip_timer += delta
	if drip_timer > 0.2:
		drip_timer = 0.0
		add_dirt(random_body_point(), 2)
		damage(1.5)
		if state == "pinned":
			main.sfx.play_any(["grab_loop", "gurgle"], -4.0, 0.2)
			main.add_goop(position + Vector2(randf_range(-40, 40), randf_range(-8, 8)), 50.0, 0.2)
	struggle = clampf(struggle, 0.0, 1.0)
	if struggle >= 1.0 and state == "pinned":
		state = "normal"
		invuln = 1.6
		on_floor = false
		vz = 260.0
		vel = Vector2(randf_range(-160.0, 160.0), 0.0)
		main.sfx.play("escape")
		main.add_goop(position, 120.0, 0.4)


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
	var d := _mash_input()
	var sandwiched: bool = sandwicher != null and is_instance_valid(sandwicher)
	if d != 0 and d != last_dir:
		last_dir = d
		if sandwiched and sandwicher.sub == "hug":
			# がっちり抱きしめられた：押し返せないが、もがけば少しずつ抜けられる
			struggle += 0.04
		elif sandwiched:
			# 押し問答の間：正面のドーベルマンを押し返しつつ、柱からも少しずつ抜けていく
			push += 0.09
			struggle += 0.02
		else:
			struggle += 0.06
	if sandwiched:
		if push >= 1.0:
			push = 0.0
			sandwicher.on_pushed(self)
		push = maxf(push - 0.25 * delta, 0.0)
	drip_timer += delta
	if drip_timer > (0.18 if sandwiched else 0.3):
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


# ---------- つまずき（ふらふらのとき） ----------
func _stumble() -> void:
	stumble_t = 0.9
	vel *= 0.3
	main.sfx.play("step_paint")
	add_dirt(Vector2i(randi_range(40, 88), randi_range(90, 118)), 1)


# ---------- 転倒 ----------
func _slip() -> void:
	state = "slipped"
	slip_t = [1.1, 1.5, 2.0][fatigue()]
	collapse_again = fatigue() == 2 and randf() < 0.5
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
	var d := _mash_input()
	if d != 0 and d != last_dir:
		slip_t -= 0.12
		last_dir = d
	slip_t -= delta
	floor_timer += delta
	if floor_timer > 0.3:
		floor_timer = 0.0
		add_dirt(random_body_point(), 1)
	if slip_t <= 0.0 and collapse_again:
		# 立ち上がりかけて、またベシャッと崩れる
		collapse_again = false
		slip_t = 0.9
		main.sfx.play("step_paint")
		main.add_goop(position, 50.0, 0.15)
		add_dirt(random_body_point(), 2)
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
	var d := _mash_input()
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
	# 汗と息切れ（疲れているときだけ）
	if state == "normal" and not hidden_in_hug:
		var ft := fatigue()
		if ft > 0 and randf() < (0.04 if ft == 1 else 0.09):
			sweat.append({"x": randf_range(-14.0, 14.0), "y": -100.0 - z + randf_range(0.0, 20.0), "vx": randf_range(-30.0, 30.0), "vy": -randf_range(30.0, 70.0), "life": 0.6})
		var tt := Time.get_ticks_msec() / 1000.0
		if ft > 0 and fmod(tt, 0.9 - 0.3 * ft) < 0.12:
			# 口元からハァハァの息
			draw_rect(Rect2(facing * 18.0 + facing * fmod(tt, 0.12) * 60.0, -78.0 - z, 3, 2), Color(1, 1, 1, 0.55))
	var dt := get_process_delta_time()
	for sw in sweat:
		sw.vy += 260.0 * dt
		sw.x += sw.vx * dt
		sw.y += sw.vy * dt
		sw.life -= dt
		draw_rect(Rect2(roundf(sw.x), roundf(sw.y), 2, 3), Color("bfe8ff"))
	sweat = sweat.filter(func(sw): return sw.life > 0.0)
	if cleaning and state == "normal":
		var t := Time.get_ticks_msec() / 120
		for i in 3:
			var px := float((t * 7 + i * 11) % 40) - 20.0
			var py := -10.0 - float((t * 3 + i * 9) % 100)
			draw_rect(Rect2(px, py, 2, 2), Color("bfefff"))
