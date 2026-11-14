extends Node2D
## ペンキサメ。床の下をヒレだけ出して泳ぎ、真下から丸呑み／遠くからは大ジャンプでドボン。
## 呑んだ相手を床の下で引き回してドロドロにする。
## ワニに捕まっている主人公を狙うと、ワニごと呑み込んで「地中の2対1」になる（連携の登竜門）。
## 絵は assets/same_base.png（閉じ口）と assets/same_open.png（大口）。無ければ仮の図形で描く。

const BASE_PATH := "res://assets/same_base.png"
const GooMound = preload("res://goo_mound.gd")
const UnderHeave = preload("res://under_heave.gd")
const UnderOverlay = preload("res://under_overlay.gd")
const OPEN_PATH := "res://assets/same_open.png"
const FEET_Y := 182          # 絵の中で腹（水たまり）が床に着く行
const MOUTH_X := 92.0       # 横向きの絵の中心から口までの横の距離（アニメが無いとき用）
const BREACH_FEET := 218     # 突き上げ・沈むアニメで水たまりが床に着く行
const B2_FEET := 226         # 大きいアホ面版の突き上げ（右向きの絵）
const B2_MOUTH := 68.0       # その口の位置（絵の中心から前へ）
const DIVE_FEET := 236       # 急降下アニメ
const DIVE_MOUTH := 68.0     # 急降下の1コマ目で、絵の中心から口までの横の距離
const FIN_H := 52            # 泳いでいるとき床から出ている高さ（絵の上から何行ぶん＝背ビレ）

var main
var state := "swim"   # swim / gulp / leap / drag / spit / stunned
var facing := -1      # 元絵は左向き
var t := 0.0
var cd := 0.0          # 次の攻撃までの待ち
var aim := Vector2.ZERO  # 狙っている場所（少し前の主人公の位置）
var aim_t := 0.0
var leap_from := Vector2.ZERO
var leap_to := Vector2.ZERO
var z := 0.0
var caught_player := false
var caught_wani = null
var caught_dobe = null   # ドーベルマンも中にいる（3対1 / ドーベルマンとの2対1）
var maw_dobe = null      # ゆっくり丸呑み：主人公を羽交い締めにしているドーベルマン
var maw_flip := false
var maw_frames: Array[Texture2D] = []   # 正面向きで口をゆっくり開ける（same_front_0..）
const MAW_T := 3.2       # 口を開ききるまで（このあいだに振りほどけば助かる）
var view_mode := "inside"   # 地中の見せ方：inside=体内の小窓 / splat=見せずにペンキが噴き出すだけ
var erupt_t := 0.0
var eruptions: Array = []   # 噴き出しの見た目 {pos, t}
var gurgle_t := 0.0
var mound: Sprite2D
var mound_frames: Array[Texture2D] = []
var mound_player = GooMound.Player.new()
var heave = UnderHeave.new()   # 地中の獲物を、床のペンキの盛り上がりで見せる
var overlay   # 盛り上がりの上に重ねる、もがきのドット絵アニメ
var wander := 0.0
var sprite: Sprite2D
var tex_base: Texture2D
var tex_open: Texture2D
var anims := {}           # breach / sink / dive（各9コマ）
var tex_leap: Texture2D
var img_cache := {}       # 切れ目の幅を調べるための画像
var collar: Node2D        # 床との境目に重ねるドロドロ（画像の切れ目を隠す）
var cut_l := 0.0
var cut_r := 0.0
var cut_on := false


func _ready() -> void:
	overlay = UnderOverlay.new()
	add_child(overlay)
	var mi := 0
	while ResourceLoader.exists("res://assets/same_front_%d.png" % mi):
		maw_frames.append(load("res://assets/same_front_%d.png" % mi))
		mi += 1
	tex_base = load(BASE_PATH) if ResourceLoader.exists(BASE_PATH) else null
	tex_open = load(OPEN_PATH) if ResourceLoader.exists(OPEN_PATH) else tex_base
	var hk := 0
	while ResourceLoader.exists("res://assets/same_hugeat_%d.png" % hk):
		hugeat_frames.append(load("res://assets/same_hugeat_%d.png" % hk))
		var mpath := "res://assets/masks/same_hugeat_%d_mask.png" % hk
		hugeat_masks.append(load(mpath) if ResourceLoader.exists(mpath) else null)
		hk += 1
	for k in ["breach", "sink", "dive", "breach2", "sink2", "gulp", "struggle", "combo"]:
		var arr: Array[Texture2D] = []
		for i in 9:
			var path := "res://assets/same_%s_%d.png" % [k, i]
			if ResourceLoader.exists(path):
				arr.append(load(path))
		if arr.size() == 9:
			anims[k] = arr
	if ResourceLoader.exists("res://assets/same_leap.png"):
		tex_leap = load("res://assets/same_leap.png")
	sprite = Sprite2D.new()
	sprite.centered = false
	add_child(sprite)
	collar = Node2D.new()
	collar.draw.connect(_draw_collar)
	add_child(collar)
	mound_frames = GooMound.load_frames()
	mound = Sprite2D.new()
	mound.centered = false
	mound.offset = Vector2(-128, -232)
	mound.visible = false
	add_child(mound)
	cd = 2.0


## 正面向きの素材があれば、ドーベルマンと組んだ「ゆっくり丸呑み」ができる
func can_maw() -> bool:
	return maw_frames.size() > 0 and state == "swim" and cd <= 0.0 and not caught_player


func start_maw(p, dobe) -> void:
	state = "maw"
	t = 0.0
	maw_dobe = dobe
	# 獲物の向いている先に、獲物のほうを向いて頭だけ浮上する（絵は左向き＝口が左）
	maw_flip = p.facing < 0
	position = Vector2(clampf(p.position.x + p.facing * 158.0, main.ARENA_L, main.ARENA_R), clampf(p.position.y + 4.0, main.DEPTH_MIN, main.DEPTH_MAX))
	main.sfx.play("gurgle", 0.0)
	main.add_goop(position, 160.0, 0.5)


func _maw(delta: float, p) -> void:
	# 0〜0.8秒：ゴポゴポと浮上 → 〜MAW_T：汚い口をゆっくり開けていく → 2匹まとめてバクン
	if maw_dobe == null or not is_instance_valid(maw_dobe) or p.state != "held":
		# 振りほどかれた：口を閉じて、ばつが悪そうに沈む
		maw_dobe = null
		state = "swim"
		cd = 3.0
		main.sfx.play("gurgle", -4.0)
		return
	var k := clampf(t / MAW_T, 0.0, 1.0)
	if maw_frames.size() > 0:
		sprite.texture = maw_frames[int(ease(k, 2.2) * float(maw_frames.size() - 1))]
	gurgle_t -= delta
	if gurgle_t <= 0.0:
		gurgle_t = lerpf(0.6, 0.25, k)
		main.sfx.play_any(["gurgle", "grab_loop"], -6.0 + 4.0 * k)
		main.add_goop(position + Vector2(randf_range(-60, 60), 0), 60.0, 0.2)
	if t >= MAW_T:
		# バクン：羽交い締めにされたまま2匹まとめて呑み込む
		main.zoom_moment(position + Vector2(0, -100), 1.2)
		main.add_goop(position, 240.0, 0.8)
		for i in 5:
			main.splat_wall(Vector2(position.x + randf_range(-220.0, 220.0), main.FLOOR_TOP - randf_range(10.0, 220.0)), randf_range(35.0, 70.0))
		caught_dobe = maw_dobe
		maw_dobe = null
		caught_dobe.get_swallowed(self)
		caught_player = p.get_swallowed(self, true)
		main.sfx.play("assist", 2.0)
		# すぐには潜らない：口をバクンと閉じ、呑み込んで、2匹を抱えたままゆっくり床に沈んでいく
		state = "maw_gulp"
		t = 0.0


## 呑み込んだあと：口を閉じる（0〜0.35秒）→ ゴクンと溜める（〜0.6秒）→ 床に引きずり込むように沈む（〜1.5秒）→ 引き回しへ
const GULP_CLOSE := 0.35
const GULP_HOLD := 0.6
const GULP_SINK := 1.5
func _maw_gulp(delta: float) -> void:
	if maw_frames.size() > 0:
		if t < GULP_CLOSE:
			var k := 1.0 - ease(t / GULP_CLOSE, 0.4)
			sprite.texture = maw_frames[int(k * float(maw_frames.size() - 1))]
		else:
			sprite.texture = maw_frames[0]
	gurgle_t -= delta
	if gurgle_t <= 0.0:
		gurgle_t = 0.18
		main.sfx.play_any(["gurgle", "grab_loop"], -2.0)
		main.add_goop(position + Vector2(randf_range(-70, 70), 0), 70.0, 0.3)
	if t > GULP_HOLD and fmod(t, 0.2) < delta:
		main.add_ring(position, 2.0)
	if t >= GULP_SINK:
		_sink_after_attack()


## ドーベルマンが自分から口に飛び込んできた（地中で引き回し中の2対1 → 3対1）
func take_dobe(dobe) -> void:
	caught_dobe = dobe
	main.sfx.play("assist", 0.0)
	main.add_goop(position, 180.0, 0.6)
	main.zoom_moment(position + Vector2(0, -60), 0.8)


func is_trio() -> bool:
	return caught_wani != null and is_instance_valid(caught_wani) and caught_dobe != null and is_instance_valid(caught_dobe)


func is_dragging() -> bool:
	return state == "drag"


func underground() -> bool:
	return state in ["swim", "drag", "stunned"]


func _process(delta: float) -> void:
	t += delta
	cd -= delta
	wander += delta
	# 飛びかかるときは主人公より手前、下から飛び出すときは主人公の後ろ（大口の中に主人公が見える）
	if state == "leap" or state == "splash":
		z_index = int(position.y) + 3
	elif state == "gulp":
		# 下から突き上げるときは獲物の後ろ。ワニごと呑むときは手前から覆いかぶさる
		z_index = main.player.z_index - 1 if not gulped_combo else int(position.y) + 300
	else:
		z_index = int(position.y) - 2
	if main.game_over:
		# 負けたら引き回しも盛り上がりも止める（とどめの演出に任せる）
		if state == "drag" or overlay.visible:
			overlay.stop()
			mound.visible = false
			collar.visible = false
			eruptions.clear()
			state = "done"
		if state == "done":
			queue_redraw()
			return
		state = "swim"
	var p = main.player
	match state:
		"swim":
			_swim(delta, p)
		"stunned":
			if t > 1.2:
				state = "swim"
		"gulp":
			_gulp(delta, p)
		"leap":
			_leap(delta, p)
		"splash":
			if t > 0.6:
				_sink_after_attack()
		"drag":
			_drag(delta, p)
		"maw":
			_maw(delta, p)
		"maw_gulp":
			_maw_gulp(delta)
	for er in eruptions:
		er.t += delta
	eruptions = eruptions.filter(func(er): return er.t < 0.6)
	_update_sprite()
	# 引き回し中：床のドロドロが大きく盛り上がって蠢く（中に獲物）
	# 引き回し中：床のペンキそのものが下から押し上げられ、うねり、波紋が広がる（盛り上がりの絵は使わない）
	mound.visible = false
	if state == "drag":
		var inten := 1.0 if is_trio() else (0.75 if caught_wani != null else 0.45)
		heave.step(main, get_process_delta_time(), position, inten)
		overlay.allow_drag = caught_wani != null
		overlay.step(get_process_delta_time(), inten)
		sprite.visible = false
		collar.visible = false
	else:
		collar.visible = true
		if overlay.visible:
			overlay.stop()
	queue_redraw()


# ---------- 泳ぐ（ヒレだけ見えている） ----------
# 遊撃型：ふだんは主人公の周りを距離をとって回り込み、隙を見て一気に突っ込んで（すれ違いざまに）丸呑みを狙い、
# 外れたらそのまま走り抜けて離れ、また回り込む。遠くからの大ジャンプも混ぜる。
# ほかの敵が主人公を捕まえたら、連携で決めに来る（ワニの抱きつきへは一直線＝従来どおり）。
var prowl := "circle"     # circle（回り込み）/ windup（突っ込む前の溜め）/ dash（突っ込み）/ retreat（離れる）
var prowl_t := 0.0
var harass_t := 3.0
var orbit_side := 1
var dash_to := Vector2.ZERO
const ORBIT_R := 230.0

func _swim(delta: float, p) -> void:
	if main.game_over:
		return
	if p.state != "grabbed":
		_skirmish(delta, p)
		return
	prowl = "circle"
	var raw: Vector2 = p.position - position
	if absf(raw.x) > MOUTH_X + 10.0:
		facing = 1 if raw.x > 0 else -1
	# 口が主人公の真下に来る位置を目指す
	var mx: float = B2_MOUTH if anims.has("breach2") else (0.0 if anims.has("breach") else MOUTH_X)
	# 狙いは少し遅れて付いてくる（序盤ほど更新が遅い）。ワニに捕まっている獲物は動かないので正確
	aim_t -= delta
	if aim_t <= 0.0 or aim == Vector2.ZERO or p.state == "grabbed":
		aim = p.position
		aim_t = lerpf(1.0, 0.4, main.ramp())
	var target: Vector2 = aim - Vector2(facing * mx, 0.0)
	var to_p: Vector2 = target - position
	# ドロドロの中は速い。乾いた床も潜って進む（通った跡がドロドロになる）。序盤は遅め
	var sp: float = (120.0 if main.goop_at(position) > 0.12 else 65.0) * lerpf(0.55, 1.0, main.ramp())
	if p.state == "grabbed":
		sp *= 1.3   # ワニに捕まっている獲物には一直線
	var can_hunt: bool = p.state in ["normal", "slipped", "grabbed"] and cd <= 0.0
	# 遠くにいれば大ジャンプ
	if can_hunt and to_p.length() > 320.0 and p.state != "grabbed":
		_start_leap(p)
		return
	position += to_p.normalized() * Vector2(1.0, 0.6) * sp * delta if to_p.length() > 4.0 else Vector2.ZERO
	_clamp()
	main.add_goop(position, 70.0, 0.5 * get_process_delta_time() * 10.0)   # 泳いだ跡がはっきり残る
	# 真下に来たら丸呑み
	var real: Vector2 = p.position - Vector2(facing * mx, 0.0) - position
	if can_hunt and absf(real.x) < 16.0 and absf(real.y) < 14.0:
		state = "gulp"
		t = 0.0
		gulp_fast = p.state == "grabbed"
		main.sfx.play("grab", -4.0)
		# 飛び出す瞬間から寄って、呑まれるところを見せる
		main.zoom_moment(Vector2(position.x + facing * mx, position.y - 100.0), 1.5)


func _mouth_x() -> float:
	return B2_MOUTH if anims.has("breach2") else (0.0 if anims.has("breach") else MOUTH_X)


func _skirmish(delta: float, p) -> void:
	prowl_t += delta
	harass_t -= delta
	var r: float = main.ramp()
	var goo: bool = main.goop_at(position) > 0.12
	var free: bool = p.state in ["normal", "slipped"]
	var mx := _mouth_x()
	match prowl:
		"circle":
			# 主人公の左右どちらかに距離をとって並走し、ときどき反対側へ回り込む
			if randf() < delta * 0.15:
				orbit_side = -orbit_side
			var bob := sin(t * 1.3) * 40.0
			var tgt := Vector2(p.position.x + orbit_side * ORBIT_R, p.position.y + bob)
			tgt.x = clampf(tgt.x, main.ARENA_L + 20.0, main.ARENA_R - 20.0)
			if absf(tgt.x - p.position.x) < 120.0:
				orbit_side = -orbit_side   # 壁際で回り込めないときは反対側へ
			var to := tgt - position
			var sp: float = (150.0 if goo else 95.0) * lerpf(0.65, 1.0, r)
			if to.length() > 6.0:
				position += to.normalized() * Vector2(1.0, 0.7) * sp * delta
				if absf(to.x) > 20.0:
					facing = 1 if to.x > 0.0 else -1
			if free and cd <= 0.0 and harass_t <= 0.0:
				var dist := position.distance_to(p.position)
				if dist > 330.0 or (dist > 200.0 and randf() < 0.3):
					_start_leap(p)
					harass_t = lerpf(5.0, 2.5, r) + randf_range(0.0, 1.5)
					return
				prowl = "windup"
				prowl_t = 0.0
				facing = 1 if p.position.x > position.x else -1
		"windup":
			# 一瞬止まって狙いを定める（ヒレだけ小刻みに震える）
			facing = 1 if p.position.x > position.x else -1
			if prowl_t > lerpf(0.55, 0.3, r):
				# 少し先読みした位置を通り抜けるように突っ込む
				var aimp: Vector2 = p.position + p.vel * 0.3
				var dir := 1 if aimp.x > position.x else -1
				facing = dir
				dash_to = Vector2(aimp.x - dir * mx + dir * 170.0, aimp.y)
				dash_to.x = clampf(dash_to.x, main.ARENA_L, main.ARENA_R)
				prowl = "dash"
				prowl_t = 0.0
				main.sfx.play("step_paint", -2.0)
		"dash":
			var to := dash_to - position
			var sp: float = lerpf(210.0, 330.0, r) * (1.15 if goo else 1.0)
			position += to.normalized() * Vector2(1.0, 0.6) * sp * delta if to.length() > 6.0 else Vector2.ZERO
			main.add_goop(position, 60.0, 0.6 * delta * 10.0)
			var real: Vector2 = p.position - Vector2(facing * mx, 0.0) - position
			if free and p.invuln <= 0.0 and absf(real.x) < 22.0 and absf(real.y) < 18.0:
				prowl = "circle"
				harass_t = lerpf(5.0, 2.5, r)
				state = "gulp"
				t = 0.0
				gulp_fast = true   # すれ違いざまなので素早く呑む
				main.sfx.play("grab", -4.0)
				main.zoom_moment(Vector2(position.x + facing * mx, position.y - 100.0), 1.5)
				return
			if to.length() <= 8.0 or prowl_t > 2.5:
				prowl = "retreat"
				prowl_t = 0.0
		"retreat":
			# 外れたら走り抜けたまま離れて、また回り込みに戻る
			var away := 1 if position.x > p.position.x else -1
			orbit_side = away
			var tgt := Vector2(p.position.x + away * ORBIT_R, position.y)
			tgt.x = clampf(tgt.x, main.ARENA_L + 20.0, main.ARENA_R - 20.0)
			var to := tgt - position
			if to.length() > 6.0:
				position += to.normalized() * Vector2(1.0, 0.6) * 160.0 * delta
			if prowl_t > 0.8:
				prowl = "circle"
				prowl_t = 0.0
				harass_t = lerpf(4.0, 2.0, r) + randf_range(0.0, 1.5)
	_clamp()
	main.add_goop(position, 70.0, 0.5 * delta * 10.0)


# ---------- 真下から丸呑み ----------
var gulped_solo := false   # 1人を呑み込んだ（呑み込みのコマを見せる）
var gulped_combo := false  # ワニごと呑み込んだ
var gulp_fast := false
var hugeat := false        # ワニに抱きしめられた主人公ごと、下から大口でゆっくり丸呑み（専用アニメ）
var hug_flip := false
var hugeat_frames: Array[Texture2D] = []
var hugeat_masks: Array = []
var hugeat_mat: ShaderMaterial
const HUGEAT_T := 3.2     # ワニに捕まっている獲物を狙った（飛び出しざまに一気に呑んで、すぐドプンと沈む）


func _gulp(delta: float, p) -> void:
	# 突き上げ（0〜0.45秒、0.4秒で呑む）→ 呑み込むコマ（1人のとき）→ 口を閉じて沈む
	var b2: bool = anims.has("breach2")
	var bite := (0.28 if gulp_fast else 0.45) if b2 else (0.36 if anims.has("breach") else 0.3)
	# ワニに抱え込まれている獲物：専用アニメで、抱きしめられたまま下から丸呑み
	if gulp_fast and hugeat_frames.size() > 0 and not has_meta("gulped") and p.state == "grabbed" and is_instance_valid(p.grabbed_by):
		var w = p.grabbed_by
		set_meta("gulped", true)
		position = w.position
		hug_flip = w.sprite.flip_h
		facing = 1 if hug_flip else -1
		caught_wani = w
		w.get_swallowed(self)
		caught_player = p.get_swallowed(self, true)
		gulped_combo = true
		hugeat = true
		main.zoom_moment(position + Vector2(0, -120), HUGEAT_T + 0.4, false)
		main.sfx.play("gurgle", 0.0)
	if hugeat:
		var hf := int(t / HUGEAT_T * float(hugeat_frames.size()))
		if hf == 4 and not has_meta("hug_rise"):
			# サメが背後から突き上げる
			set_meta("hug_rise", true)
			main.add_goop(position, 220.0, 0.7)
			for i in 4:
				main.splat_wall(Vector2(position.x + randf_range(-200.0, 200.0), main.FLOOR_TOP - randf_range(10.0, 200.0)), randf_range(35.0, 65.0))
			main.sfx.play("assist", 0.0)
		if hf == 11 and not has_meta("hug_gulp"):
			set_meta("hug_gulp", true)
			main.sfx.play("defeat", -1.0)
			main.add_goop(position, 160.0, 0.5)
		if fmod(t, 0.35) < get_process_delta_time():
			main.sfx.play_any(["grab_loop", "gurgle"], -4.0, 0.1)
	var end := (HUGEAT_T + 0.7) if hugeat else ((2.45 if gulped_solo else (1.15 if gulped_combo else 1.25)) if b2 else (0.95 if anims.has("breach") else 0.7))
	if t >= bite and not has_meta("gulped"):
		set_meta("gulped", true)
		main.add_goop(position, 220.0, 0.7)
		for i in 5:
			main.splat_wall(Vector2(position.x + randf_range(-220.0, 220.0), main.FLOOR_TOP - randf_range(10.0, 220.0)), randf_range(35.0, 70.0))
			main.add_goop(position + Vector2(randf_range(-220, 220), randf_range(-40, 40)), randf_range(40, 100), 0.5)
		_try_swallow(p, 48.0, B2_MOUTH if b2 else (0.0 if anims.has("breach") else MOUTH_X))
		gulped_solo = caught_player and caught_wani == null and anims.has("gulp")
		gulped_combo = caught_player and caught_wani != null
		if gulped_combo:
			main.zoom_moment(Vector2(position.x + facing * B2_MOUTH, position.y - 110.0), 1.0)
		if gulped_solo:
			main.zoom_moment(Vector2(position.x + facing * B2_MOUTH, position.y - 110.0), 2.0)
	if t > end:
		remove_meta("gulped")
		if has_meta("plunged"):
			remove_meta("plunged")
		gulped_solo = false
		gulped_combo = false
		gulp_fast = false
		hugeat = false
		sprite.material = null
		for mk in ["hug_rise", "hug_gulp"]:
			if has_meta(mk):
				remove_meta(mk)
		_sink_after_attack()


# ---------- 大ジャンプしてドボン ----------
func _start_leap(p) -> void:
	state = "leap"
	t = 0.0
	leap_from = position
	# 着地点は主人公の今いる場所（動けば外せる）
	facing = 1 if p.position.x > position.x else -1
	var mo: float = DIVE_MOUTH if anims.has("dive") else MOUTH_X
	leap_to = p.position - Vector2(facing * mo, 0.0)
	leap_to.x = clampf(leap_to.x, main.ARENA_L, main.ARENA_R)
	main.sfx.play("grab", -2.0)


func _leap(delta: float, p) -> void:
	var dur := 1.0
	var k := clampf(t / dur, 0.0, 1.0)
	position = leap_from.lerp(leap_to, k)
	z = sin(k * PI) * 240.0
	if k >= 1.0 and state == "leap":
		z = 0.0
		main.add_goop(position, 220.0, 0.7)
		for i in 3:
			main.splat_wall(Vector2(position.x + randf_range(-160.0, 160.0), main.FLOOR_TOP - randf_range(20.0, 160.0)), randf_range(40.0, 70.0))
		main.sfx.play("assist")
		_try_swallow(p, 70.0, DIVE_MOUTH if anims.has("dive") else MOUTH_X)
		if anims.has("dive"):
			# 頭からドボンと沈むアニメを見せてから地中へ
			state = "splash"
			t = 0.0
		else:
			_sink_after_attack()


# ---------- 呑み込み判定 ----------
func _try_swallow(p, r: float, mouth_off: float) -> void:
	var mouth: float = position.x + facing * mouth_off
	var near: bool = absf(p.position.x - mouth) < r and absf(p.position.y - position.y) < 30.0 and p.z < 60.0
	if not near:
		return
	if main.zoom_t <= 0.0 and near:
		main.zoom_moment(Vector2(mouth, p.position.y - 60.0))
	if p.state == "grabbed" and is_instance_valid(p.grabbed_by):
		# ワニごと丸呑み（地中で2対1が始まる）
		caught_wani = p.grabbed_by
		caught_wani.get_swallowed(self)
		caught_player = p.get_swallowed(self, true)
	elif p.state in ["normal", "slipped"] and p.invuln <= 0.0:
		caught_player = p.get_swallowed(self, false)


func _sink_after_attack() -> void:
	if caught_player:
		state = "drag"
		t = 0.0
		# 2対1・3対1は必ず小窓で見せる。1人のときはたまに「見せずに噴き出すだけ」
		view_mode = "inside" if (caught_wani != null or randf() < 0.6) else "splat"
	else:
		state = "swim"
		cd = randf_range(2.5, 4.0) + lerpf(2.5, 0.0, main.ramp())


# ---------- 床の下で引き回す ----------
func _drag(delta: float, p) -> void:
	# ゆっくり蛇行しながら床の下を引き回す
	var dir := Vector2(cos(wander * 0.7), sin(wander * 1.3) * 0.5)
	position += dir * 55.0 * delta
	if position.x < main.ARENA_L + 40.0 or position.x > main.ARENA_R - 40.0:
		wander += PI * 0.5
	_clamp()
	facing = 1 if dir.x > 0 else -1
	main.add_goop(position, 50.0, 0.05)
	# グチュグチュ音
	gurgle_t -= delta
	if gurgle_t <= 0.0:
		gurgle_t = randf_range(0.18, 0.42)
		main.sfx.play_any(["gurgle", "grab_loop"] if randf() < 0.6 else ["grab_loop", "gurgle"], randf_range(-3.0, 1.0))
	if view_mode == "splat":
		# 中で何をされているかは見せず、床を突き破ってペンキが何度も噴き出す
		erupt_t -= delta
		if erupt_t <= 0.0:
			erupt_t = randf_range(0.25, 0.6) * (0.7 if caught_wani != null else 1.0)
			var at := position + Vector2(randf_range(-70.0, 70.0), randf_range(-12.0, 12.0))
			main.add_goop(at, randf_range(60.0, 120.0), 0.5)
			main.splat_wall(Vector2(at.x + randf_range(-80.0, 80.0), main.FLOOR_TOP - randf_range(10.0, 170.0)), randf_range(30.0, 60.0))
			main.sfx.play("hit", -6.0)
			eruptions.append({"pos": at, "t": 0.0})
			heave.limbs.append({"off": at - position, "t": 0.0, "dur": 0.5, "amp": 34.0, "r": 22.0})


## 主人公が自力で脱出したとき
func on_escaped() -> void:
	caught_player = false
	var trio := is_trio()
	if caught_wani != null and is_instance_valid(caught_wani):
		if trio:
			caught_wani.pin_under(main.player)    # 3対1から抜けても、地面で下から挟まれる
		else:
			caught_wani.spit_out(position + Vector2(-facing * 60.0, 0.0))
	if caught_dobe != null and is_instance_valid(caught_dobe):
		if trio:
			caught_dobe.pin_on(main.player)       # …上からはドーベルマンがのしかかる
		else:
			caught_dobe.spit_out(position + Vector2(facing * 60.0, 0.0))
	caught_dobe = null
	caught_wani = null
	state = "stunned"
	t = 0.0
	cd = 4.0


func _clamp() -> void:
	position.x = clampf(position.x, main.ARENA_L, main.ARENA_R)
	position.y = clampf(position.y, main.DEPTH_MIN, main.DEPTH_MAX)


# ---------- 見た目 ----------
func _update_sprite() -> void:
	if (state == "maw" or state == "maw_gulp") and maw_frames.size() > 0:
		# 頭だけ浮上：テクスチャは _maw で選んでいる。下端を床に合わせ、浮上分だけせり上げる（呑み込んだら沈んでいく）
		sprite.visible = true
		sprite.flip_h = maw_flip
		sprite.rotation = 0.0
		var th := float(sprite.texture.get_height())
		var up := clampf(t / 0.8, 0.0, 1.0)
		if state == "maw_gulp":
			# 口を閉じた瞬間に少し跳ね、ゴクンと溜めてから、ずるずる沈む
			up = 1.0 if t < GULP_HOLD else 1.0 - ease(clampf((t - GULP_HOLD) / (GULP_SINK - GULP_HOLD), 0.0, 1.0), 1.6)
		sprite.region_enabled = true
		sprite.region_rect = Rect2(0, 0, sprite.texture.get_width(), th * up)
		sprite.offset = Vector2(-sprite.texture.get_width() * 0.5, -th * up)
		sprite.position = Vector2.ZERO
		if state == "maw_gulp" and t < GULP_CLOSE + 0.1:
			sprite.position = Vector2(randf_range(-3, 3), randf_range(-2, 2)).round()
		return
	if tex_base == null:
		sprite.visible = false
		return
	# 生成したアニメがある場面は、コマをそのまま再生する（接地面のベトベトも絵に描いてある）
	var frame: Texture2D = null
	var feet := 0.0
	if state == "gulp" and hugeat and hugeat_frames.size() > 0:
		if t < HUGEAT_T:
			var hf2 := clampi(int(t / HUGEAT_T * float(hugeat_frames.size())), 0, hugeat_frames.size() - 1)
			sprite.visible = true
			sprite.texture = hugeat_frames[hf2]
			# 中の主人公にも、今の汚れ具合をのせる
			if hugeat_mat == null:
				hugeat_mat = ShaderMaterial.new()
				hugeat_mat.shader = load("res://hug_dirt.gdshader")
				hugeat_mat.set_shader_parameter("absorb_y", 1.0)
			hugeat_mat.set_shader_parameter("cat_mask", hugeat_masks[hf2])
			hugeat_mat.set_shader_parameter("contamination", main.player.contamination())
			# 主人公が口の中に消えたコマ（マスクなし）は、汚れを描かない
			sprite.material = hugeat_mat if hugeat_masks[hf2] != null else null
			sprite.region_enabled = false
			sprite.flip_h = hug_flip
			sprite.offset = Vector2(-128, -233)
			sprite.position = Vector2(sin(t * 40.0) * (1.5 if hf2 > 9 else 0.0), 0).round()
		else:
			# 呑み込んで膨れた腹のまま、沈む
			sprite.material = null
			var s2: Array = anims.get("sink2", [])
			if s2.size() == 9:
				sprite.texture = s2[clampi(2 + int((t - HUGEAT_T) / 0.6 * 7.0), 2, 8)]
				sprite.flip_h = hug_flip
				sprite.offset = Vector2(-128, -B2_FEET)
				sprite.position = Vector2.ZERO
		cut_on = false
		collar.queue_redraw()
		return
	if state == "gulp" and anims.has("breach2"):
		var off := _gulp_pose()
		frame = off[0]
		sprite.visible = true
		sprite.texture = frame
		sprite.region_enabled = false
		sprite.flip_h = facing < 0
		sprite.offset = Vector2(-frame.get_width() / 2.0, -B2_FEET)
		sprite.position = Vector2(off[1].x * facing, off[1].y).round()
		cut_on = false
		collar.queue_redraw()
		return
	if state == "gulp" and anims.has("breach"):
		if t < 0.45:
			frame = anims["breach"][clampi(int(t / 0.45 * 9.0), 0, 8)]
		else:
			frame = anims["sink"][clampi(int((t - 0.45) / 0.5 * 9.0), 0, 8)]
		feet = BREACH_FEET
	elif state == "splash" and anims.has("dive"):
		frame = anims["dive"][clampi(int(t / 0.6 * 9.0), 0, 8)]
		feet = DIVE_FEET
	elif state == "leap" and tex_leap != null:
		frame = tex_leap
		feet = 128.0 + 60.0   # 空中：絵の中心より少し下が影の真上
	if frame != null:
		sprite.visible = true
		sprite.texture = frame
		sprite.region_enabled = false
		sprite.flip_h = facing > 0
		sprite.offset = Vector2(-frame.get_width() / 2.0, -feet)
		sprite.position = Vector2(0, -z)
		cut_on = false
		collar.queue_redraw()
		return
	var tex: Texture2D = tex_base
	var vis_h := 0.0         # 床から上に見えている高さ
	var full_h: float = tex.get_height()
	match state:
		"swim", "drag", "stunned":
			vis_h = FIN_H
		"gulp":
			tex = tex_open
			# 飛び出して、沈む
			var k: float = t / 0.3 if t < 0.3 else 1.0 - (t - 0.3) / 0.4
			vis_h = lerpf(FIN_H, FEET_Y, clampf(k, 0.0, 1.0))
		"leap":
			tex = tex_open
			vis_h = FEET_Y
	sprite.visible = true
	sprite.texture = tex
	sprite.flip_h = facing > 0
	# 絵の上から vis_h 行だけを切り出して床の上に置く＝床から生えて（潜って）見える
	var h := clampf(vis_h, 1.0, FEET_Y)
	sprite.region_enabled = true
	sprite.region_rect = Rect2(0, 0, tex.get_width(), h)
	sprite.offset = Vector2(-tex.get_width() / 2.0, -h)
	sprite.position = Vector2(0, -z + (4.0 if underground() else 0.0))
	# 床に埋まっている部分の切れ目の幅（その行の不透明な範囲）
	cut_on = state != "leap" and h < FEET_Y - 2
	if cut_on:
		var img: Image = _img(tex)
		var row := int(h) - 1
		var l := -1
		var r := -1
		for x in img.get_width():
			if img.get_pixel(x, row).a > 0.0:
				if l < 0:
					l = x
				r = x
		if l < 0:
			cut_on = false
		else:
			var w2: float = tex.get_width() / 2.0
			if sprite.flip_h:
				var l2 := tex.get_width() - 1 - r
				r = tex.get_width() - 1 - l
				l = l2
			cut_l = l - w2
			cut_r = r - w2
	collar.queue_redraw()
	# 泳いでいるときはゆらゆら
	if underground():
		sprite.position.y += sin(t * 6.0) * 2.0


## 丸呑みの振り付け：どのコマを出して、どれだけずらすか [Texture2D, Vector2]
## 突き上げ（勢いあまって少し浮く）→ 口に入れたまま暴れる獲物を噛みしめる → 頭を振って2回で呑み込む
## → 頬を膨らませてニヤける → 沈む。外したときは空中で口をパクッと閉じて沈む。
func _gulp_pose() -> Array:
	var b: Array = anims["breach2"]
	var g: Array = anims["gulp"]
	var s: Array = anims["sink2"]
	if gulp_fast and t < 0.28:
		# 一気に飛び出す（ためなし）
		return [b[clampi(int(t / 0.28 * 9.0), 0, 8)], Vector2(0, -10.0 * t / 0.28)]
	if gulp_fast and gulped_combo and anims.has("combo"):
		return _combo_pose()
	if t < 0.5 and not gulp_fast:
		var k := t / 0.5
		var lift := -16.0 * sin(clampf((k - 0.6) / 0.4, 0.0, 1.0) * PI)   # 出きる直前にぐっと伸び上がる
		return [b[clampi(int(k * 9.0), 0, 8)], Vector2(0, lift)]
	if gulped_combo and anims.has("combo"):
		# ワニごと：ワニと主人公をまとめて口に収め、何度も呑み下して腹がパンパンに膨れる → 沈む
		if t < 1.6:
			var kc := (t - 0.5) / 1.1
			return [anims["combo"][clampi(int(kc * 9.0), 0, 8)], Vector2(sin(t * 50.0) * (3.0 if kc < 0.5 else 1.0), 0).round()]
		return [s[clampi(2 + int((t - 1.6) / 0.3 * 7.0), 2, 8)], Vector2.ZERO]
	if gulped_combo:
		# ワニごと：大口を開けたまま覆いかぶさり、2体を押し込むようにガクガク揺れてから、口を閉じて沈む
		if t < 1.3:
			var k5 := (t - 0.5) / 0.8
			return [b[8], Vector2(sin(t * 60.0) * 4.0, -8.0 + k5 * 14.0)]
		return [s[clampi(int((t - 1.3) / 0.6 * 9.0), 0, 8)], Vector2(0, 6.0)]
	if not gulped_solo:
		# 空振り：口を閉じて、悔しそうにブルッと震えてから沈む
		if t < 0.78:
			return [s[1], Vector2(sin(t * 70.0) * 2.0, -6.0)]
		return [s[clampi(1 + int((t - 0.78) / 0.47 * 8.0), 1, 8)], Vector2.ZERO]
	if t < 0.72:
		# 口に入った瞬間：噛みついてガクガク揺れる
		return [g[1 if t < 0.6 else 2], Vector2(sin(t * 90.0) * 3.0, -4.0)]
	if t < 1.52:
		# 暴れる獲物を、頭を振りながら呑み下していく
		var k2 := (t - 0.72) / 0.8
		var sway := Vector2(sin(k2 * TAU * 2.0) * 5.0, -absf(sin(k2 * TAU * 2.0)) * 6.0)
		if anims.has("struggle"):
			return [anims["struggle"][clampi(int(k2 * 9.0), 0, 8)], sway]
		return [g[clampi(2 + int(k2 * 3.0), 2, 4)], sway]
	if t < 2.0:
		# 頬を膨らませて、もぐもぐ、ニヤァ…（小さく弾む）
		var k3 := (t - 1.52) / 0.48
		return [g[clampi(4 + int(k3 * 5.0), 4, 8)], Vector2(0, -absf(sin(k3 * TAU * 1.5)) * 4.0)]
	# 満足げに、前のめりに沈んでいく
	var k4 := (t - 2.0) / 0.45
	return [s[clampi(2 + int(k4 * 7.0), 2, 8)], Vector2(k4 * 10.0, 0)]


## ワニごと：飛び出しざまに大口で2体まとめてくわえ込み、そのまま弧を描いて頭から「ドプン」と沈む
func _combo_pose() -> Array:
	var c: Array = anims["combo"]
	var s: Array = anims["sink2"]
	if t < 0.62:
		# くわえ込みながら、勢いで少し跳び上がって前へ
		var k := (t - 0.28) / 0.34
		var arc := -sin(k * PI) * 34.0
		return [c[clampi(int(k * 5.0), 0, 4)], Vector2(k * 18.0, arc)]
	# ドプン：口を閉じたまま一気に沈む
	if not has_meta("plunged"):
		set_meta("plunged", true)
		main.add_goop(position, 260.0, 0.8)
		for i in 6:
			main.splat_wall(Vector2(position.x + randf_range(-240.0, 240.0), main.FLOOR_TOP - randf_range(10.0, 230.0)), randf_range(40.0, 75.0))
		main.sfx.play("defeat", -1.0)
	var k2 := (t - 0.62) / 0.5
	return [s[clampi(3 + int(k2 * 6.0), 3, 8)], Vector2(18.0 + k2 * 10.0, k2 * 26.0)]


func _img(tex: Texture2D) -> Image:
	if not img_cache.has(tex):
		img_cache[tex] = tex.get_image()
	return img_cache[tex]


## 床との境目に、盛り上がったドロドロの縁を描いて切れ目を隠す
func _draw_collar() -> void:
	if not cut_on or not sprite.visible:
		return
	var y := sprite.position.y
	var w := cut_r - cut_l + 24.0
	var cx := (cut_l + cut_r) * 0.5
	var tt := t
	var dark := Color("5a1240")
	var pink := Color("ec5a9e")
	var light := Color("f489bd")
	var yel := Color("f9d84d")
	# 外側の暗い縁 → ピンク → 上のてかり、の順に横長の塊を重ねる
	var n := int(w / 14.0) + 2
	for pass_i in 3:
		var col: Color = [dark, pink, light][pass_i]
		var shrink: float = [0.0, 3.0, 7.0][pass_i]
		for k in n:
			var fx := cx - w * 0.5 + (k + 0.5) * w / n
			var bump := 5.0 + 3.0 * sin(k * 1.7 + tt * 3.0)
			var r: float = 9.0 + bump - shrink
			if r <= 0.0:
				continue
			collar.draw_set_transform(Vector2(roundf(fx), roundf(y - 2.0 - shrink * 0.9)), 0.0, Vector2(1.0, 0.55))
			collar.draw_circle(Vector2.ZERO, r, col)
	collar.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 黄色のマーブルの筋と、縁から垂れて引っ張られる糸
	for k in n:
		if k % 3 == 1:
			var fx2 := cx - w * 0.5 + (k + 0.5) * w / n
			collar.draw_line(Vector2(fx2 - 5, y - 6), Vector2(fx2 + 4, y - 3), yel, 2.0)
	for k in 3:
		var dx := cx + (k - 1) * w * 0.3 + sin(tt * 2.0 + k) * 4.0
		var ln := 6.0 + 10.0 * absf(sin(tt * 1.3 + k * 2.0))
		collar.draw_line(Vector2(dx, y - 6), Vector2(dx, y - 6 - ln), pink, 3.0)


func _draw() -> void:
	# 着地点の影（大ジャンプ中）
	if state == "leap":
		draw_set_transform(leap_to - position, 0.0, Vector2(1.0, 0.28))
		draw_circle(Vector2.ZERO, 70.0, Color(0, 0, 0, 0.35))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	# 床のペンキを突き破って飛び散る塊（地中で何かされている）：放物線を描いて落ちる
	for er in eruptions:
		var k: float = er.t / 0.6
		var base: Vector2 = er.pos - position
		for j in 7:
			var a := -PI * 0.5 + (j - 3) * 0.32 + sin(j * 7.3) * 0.15
			var sp := 150.0 + 60.0 * fmod(j * 0.37, 1.0)
			var tt2: float = er.t
			var pos := base + Vector2(cos(a) * sp * tt2, sin(a) * sp * tt2 + 420.0 * tt2 * tt2)
			var r := (6.0 if j % 3 == 0 else 3.5) * (1.0 - k * 0.4)
			var vel := Vector2(cos(a) * sp, sin(a) * sp + 840.0 * tt2)
			GooMound.draw_glob(self, pos, vel, r, Color("ec5a9e") if j % 2 else Color("f9d84d"), j)
	if not underground():
		return
	if state == "drag":
		heave.draw_bubbles(self, position)
		return
	# 泳いだ跡の波と泡
	var tt := t
	draw_set_transform(Vector2(0, 2), 0.0, Vector2(1.6, 0.28))
	draw_circle(Vector2.ZERO, 46.0 if state != "drag" else 70.0, Color(0.45, 0.08, 0.30, 0.6))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var n := 4 if state != "drag" else 9
	for k in n:
		var ph := fmod(tt * 1.8 + k * 0.29, 1.0)
		var bx := sin(k * 2.1 + tt * 1.5) * (30.0 if state != "drag" else 56.0)
		var r := 3.0 + 6.0 * ph
		var c := Color("ec5a9e") if k % 2 == 0 else Color("f9d84d")
		c.a = 1.0 - ph * 0.7
		draw_circle(Vector2(bx, -ph * 12.0), r + 1.0, Color(0.35, 0.05, 0.2, c.a))
		draw_circle(Vector2(bx, -ph * 12.0), r, c)
	# 絵がまだ無いときの仮のヒレ
	if tex_base == null:
		var f := float(facing)
		draw_colored_polygon(PackedVector2Array([Vector2(-14 * f, 0), Vector2(18 * f, 0), Vector2(-6 * f, -FIN_H)]), Color("ec5a9e"))
		draw_polyline(PackedVector2Array([Vector2(-14 * f, 0), Vector2(-6 * f, -FIN_H), Vector2(18 * f, 0)]), Color("5a1240"), 2.0)
