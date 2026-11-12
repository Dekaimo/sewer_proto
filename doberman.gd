extends Node2D
## ペンキドーベルマン（ピンクのマーブル、幅広マッチョ、いたずら好き）
## 素材（assets/dobe_idle.png）がそろうまではゲームに出さない。
## DEBUG_SHOW を true にすると、仮の絵（ワニの待機を色替え）で動きだけ確認できる。
##
## いまの動き（素材がそろうまでは中身だけ）：
##   hold     背後から羽交い締め → 正面にサメが浮上して汚い口をゆっくり開ける（振りほどけなければ2匹まとめて丸呑み）
##   dive     地中で2対1にされていると、自分からサメの口に飛び込んで3対1（腹の中で下から抱きつく）
##   pin      3対1から抜けた主人公に、地面で上からのしかかる（下にはワニ）
##   enter    水たまりから形成（登場）
##   show     地上に姿を見せてニヤついている（しばらくしたら潜る）
##   sink     床に溶けて潜る（登場の逆再生）
##   lurk     床の下を移動。逃げ道を先回りして塞ぎ、ふだんは主人公の背中側にこっそり回り込む。
##            移動中だけ床がかすかに盛り上がる。遠いときはワープ。ときどき顔を見せる。
##   burst    他の敵から逃げようとした主人公の背後で飛び出し、羽交い締め（→ hold）
##   sandwich 主人公がワニに磔にされていると駆け寄り、正面から抱きついて胸をこすりつける（挟み撃ち）
##   pushed   押し返されたフリ：大げさによろけて離れる…が、すぐニヤニヤ戻ってきてさらに強く押しつける
##   recover  本当に押し返された：しばらく離れて様子をうかがう
## あとで：サメの腹の中の3対1（下から抱きつく）、地面での挟み撃ち、サメのゆっくり丸呑み、棺桶

const DEBUG_SHOW := false
const FEET_Y := 240

var main
var sprite: Sprite2D
var state := "enter"
var t := 0.0
var facing := -1
var vel_x := 0.0
var stun := 0.0
var peek_t := 7.0          # 次に顔を見せるまで
var lurk_t := 0.0
var rise := 1.0             # 1=地上に全身 0=床の中（登場・潜るの進み具合）
var target := Vector2.ZERO  # 潜伏中に向かう場所
var show_dur := 2.0
var base_tex: Texture2D
var maw_started := false
var sub := ""              # 磔便乗の段階：form / tease / hug
var combo := ""            # 羽交い締め中の連携："relax"（サメ）/ "throw"（ワニ）
var combo_t := 0.0
var thrown := false
var throw_wani = null
var quick_enter := false
var last_struggle := 0.0
var wobble := 0.0
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
	for k in ["idle", "walk", "rub", "reel", "emerge", "rise", "rise_back", "turn", "form", "settle", "hold", "burst", "relax", "throw", "dive", "belly"]:
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
	base_tex = sprite.texture
	rise = 0.0
	_apply_rise()
	t = 0.0


func active() -> bool:
	return state == "show" or state == "recover"


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
			_update_enter(delta)
		"show":
			_update_show(delta, p)
		"sink":
			_update_sink(delta)
		"lurk":
			_update_lurk(delta, p)
		"burst":
			_update_burst(delta, p)
		"sandwich":
			_update_sandwich(delta, p)
		"pushed":
			_update_pushed(delta, p)
		"hold":
			_update_hold(delta, p)
		"dive":
			_update_dive(delta, p)
		"in_shark", "pin":
			visible = false
			if state == "pin":
				position = p.position
				if p.state != "pinned" and not main.game_over:
					spit_out(position + Vector2(60.0, 0.0))
		"recover":
			vel_x = move_toward(vel_x, 0.0, 300.0 * delta)
			position.x += vel_x * delta
			_show_idle()
			if t > 1.2:
				_start_sink()
	position.x = clampf(position.x, main.ARENA_L, main.ARENA_R)
	position.y = clampf(position.y, main.DEPTH_MIN, main.DEPTH_MAX)


# ---------- 登場・潜る・潜伏 ----------
## 体の出具合（rise）を絵に反映する。
## rise（水たまり→顔のない人型）のコマがあればそれ、古い emerge があればそれ、無ければ立ち絵を縦に縮めて代用
func _apply_rise() -> void:
	sprite.visible = rise > 0.01
	sprite.scale = Vector2.ONE
	var key := "rise" if frames.has("rise") else ("emerge" if frames.has("emerge") else "")
	if key != "":
		var arr: Array = frames[key]
		sprite.texture = arr[clampi(int(rise * float(arr.size() - 1) + 0.5), 0, arr.size() - 1)]
	else:
		sprite.texture = base_tex
		sprite.scale = Vector2(1.0 + (1.0 - rise) * 0.25, maxf(rise, 0.02))


func _show_idle() -> void:
	sprite.scale = Vector2.ONE
	sprite.visible = true
	if frames.has("idle"):
		_frame("idle", int(t * 8.0))
	else:
		sprite.texture = base_tex


## 登場。
## ゆっくり版（ふつうの登場）：水たまりから背中を向けてねっとり起き上がる（rise_back）→ 振り向く（turn）
##   → 頭ができて最後に目、決めポーズ（form）→ 待機へ（settle）
## 速い版（顔見せ）：水たまり → 顔のない人型（rise）→ form → settle を速めに
const SLOW_PHASES := [["rise_back", 2.6], ["turn", 1.0], ["form", 1.8], ["settle", 1.0]]
const QUICK_PHASES := [["rise", 0.6], ["form", 0.9], ["settle", 0.5]]
func _update_enter(_delta: float) -> void:
	var phases: Array = QUICK_PHASES if (quick_enter or not frames.has("rise_back")) else SLOW_PHASES
	var tt := t
	for ph in phases:
		var k: String = ph[0]
		var dur: float = ph[1]
		if not frames.has(k):
			continue
		if tt < dur:
			if k == "rise":
				rise = clampf(tt / dur, 0.0, 1.0)
				_apply_rise()
			else:
				_play_once(k, tt / dur)
			return
		tt -= dur
	if not frames.has("form"):
		# 絵がそろっていないとき：立ち絵を伸ばして代用
		rise = clampf(t / 1.2, 0.0, 1.0)
		_apply_rise()
		if rise < 1.0:
			return
	rise = 1.0
	state = "show"
	t = 0.0
	show_dur = randf_range(1.5, 2.6)


## 連番を 0〜1 の進み具合で1回だけ再生
func _play_once(k: String, f: float) -> void:
	var arr: Array = frames[k]
	sprite.visible = true
	sprite.scale = Vector2.ONE
	sprite.texture = arr[clampi(int(f * float(arr.size())), 0, arr.size() - 1)]


func _update_show(_delta: float, p) -> void:
	facing = 1 if p.position.x > position.x else -1
	_show_idle()
	# 他の敵が動き出した・時間が来た → 潜る
	if t > show_dur or _threat(p) != null or p.state == "crucified" or p.state == "swallowed":
		_start_sink()


func _start_sink() -> void:
	state = "sink"
	t = 0.0
	main.sfx.play("gurgle", -8.0, 0.2)


func _update_sink(_delta: float) -> void:
	rise = 1.0 - clampf(t / 0.7, 0.0, 1.0)
	_apply_rise()
	if rise <= 0.0:
		state = "lurk"
		t = 0.0
		lurk_t = 0.0
		peek_t = randf_range(6.0, 11.0)
		sprite.visible = false
		main.add_goop(position, 60.0, 0.15)


## 主人公を追っている敵（逃げる理由になる相手）
func _threat(p):
	for e in main.enemies:
		if is_instance_valid(e) and e.state in ["approach", "windup", "lunge"] and absf(e.position.x - p.position.x) < 320.0:
			return e
	for c in main.get_children():
		if c.has_method("can_maw") and c.state == "swim" and c.position.distance_to(p.position) < 220.0:
			return c
	return null


func _update_lurk(delta: float, p) -> void:
	lurk_t += delta
	sprite.visible = false
	var th = _threat(p)
	var esc := 0
	# 行き先：磔なら真下、2対1ならその場、追われていれば逃げ道の先、ふだんは背中側
	if p.state == "crucified" and p.crucifier != null and is_instance_valid(p.crucifier) and p.crucifier.state == "crucify":
		target = p.position + Vector2(34.0 * (1 if position.x > p.position.x else -1), 6.0)
	elif th != null:
		esc = 1 if p.position.x >= th.position.x else -1
		target = p.position + Vector2(esc * 70.0, 0.0)
	else:
		target = p.position + Vector2(-p.facing * 80.0, 0.0)
	target.x = clampf(target.x, main.ARENA_L, main.ARENA_R)
	target.y = clampf(target.y, main.DEPTH_MIN, main.DEPTH_MAX)
	var to_t: Vector2 = target - position
	# 遠すぎる（反対側にいる）→ いつの間にかワープ（追われていないときだけ）
	if to_t.length() > 300.0 and lurk_t > 1.0 and th == null:
		position = target
		lurk_t = 0.0
		return
	var before := position
	if to_t.length() > 3.0:
		position += to_t.normalized() * Vector2(1.0, 0.6) * minf(170.0 * delta, to_t.length())
	# 動いているときだけ床がかすかに盛り上がる（止まるとほぼ見えない）
	if before.distance_to(position) > 0.3:
		main.add_heave(position, 30.0, 5.0)
	# 磔：真下に着いたら挟みに出る
	if p.state == "crucified" and to_t.length() < 8.0:
		facing = 1 if p.position.x > position.x else -1
		_start_sandwich(p)
		return
	# 地中で2対1：自分からサメの口に飛び込んで3対1
	if p.state == "swallowed" and p.swallower != null and is_instance_valid(p.swallower) and p.swallower.has_method("take_dobe"):
		var sh = p.swallower
		if sh.caught_wani != null and sh.caught_dobe == null and sh.state == "drag" and sh.t > 2.0:
			state = "dive"
			t = 0.0
			dive_from = position
			sprite.visible = true
			main.sfx.play("assist", -2.0)
			return
	# 逃げている主人公が真上を通り過ぎた → 背後で飛び出して羽交い締め
	if th != null and p.can_be_grabbed() and p.z < 20.0 and p.vel.x * esc > 20.0:
		var behind: float = (position.x - p.position.x) * esc
		if behind <= 4.0 and behind > -50.0 and absf(position.y - p.position.y) < 26.0:
			state = "burst"
			t = 0.0
			position = Vector2(p.position.x - esc * 22.0, p.position.y - 2.0)
			facing = esc
			main.sfx.play("grab", -2.0)
			main.add_goop(position, 90.0, 0.3)
			return
	# ときどき顔を見せる（追われていないとき）
	if th == null and lurk_t > peek_t and p.state == "normal":
		state = "enter"
		t = 0.0
		quick_enter = true   # 顔見せは少し速く
		facing = 1 if p.position.x > position.x else -1


func _update_burst(delta: float, p) -> void:
	# 床から一気に飛び出して、脇の下から腕を回す。絵（猫入り）がある間は主人公の絵を隠す
	if t <= delta * 1.5:
		if not p.can_be_grabbed():
			_start_sink()
			return
		p.get_held(self)
		p.position = Vector2(position.x + facing * 22.0, position.y + 2.0)
		maw_started = false
		combo = ""
		last_struggle = p.struggle
	if p.state != "held" or p.held_by != self:
		_leave(true)
		return
	if frames.has("burst"):
		_play_once("burst", t / 0.7)
		if t < 0.7:
			return
	else:
		rise = clampf(0.3 + t / 0.25, 0.0, 1.0)
		_apply_rise()
		if rise < 1.0:
			return
	state = "hold"
	t = 0.0
	main.zoom_moment(p.position + Vector2(0, -120), 0.7)


# ---------- 磔の挟み撃ち ----------
## 磔に便乗：ワニの股座あたりから背中を向けて形成（form）→ 抱きつこうとして押し問答（tease：わざとらしく前後に揺れる）
## → 押し返されるとわざとらしくのけぞって嗤う（pushed）→ 押されたフリを使い切ると、がっちり抱きしめる（hug：背中しか見えない）
const SW_LIFT := 60.0      # 磔の高さに合わせて持ち上げる量（絵の下端＝ワニの粘液の幹に溶け込む）
const SW_STRETCH := 1.3    # 縦に伸ばして胸を主人公の高さまで届かせる
func _start_sandwich(p) -> void:
	state = "sandwich"
	sub = "form"
	rise = 1.0
	sprite.visible = true
	sprite.scale = Vector2(1.0, SW_STRETCH)
	sprite.texture = base_tex
	t = 0.0
	rub_t = 0.0
	push_off = 0.0
	fake_left = randi_range(1, 3)
	position.x = p.position.x
	p.sandwicher = self
	p.push = 0.0
	main.sfx.play("gurgle", 0.0)
	main.zoom_moment(p.position + Vector2(0, -150), 1.4)


func _sw_place(r: float) -> void:
	sprite.scale = Vector2(1.0, SW_STRETCH)
	sprite.position = Vector2(-facing * push_off, -SW_LIFT + r).round()


func _update_sandwich(delta: float, p) -> void:
	if p.sandwicher != self or (p.state != "crucified" and p.state != "defeated"):
		_leave(false)
		return
	push_off = move_toward(push_off, 0.0, 90.0 * delta)
	match sub:
		"form":
			# 背中を向けて、グチュヌルと巨体が形成される（主人公が怯える）
			p.push = 0.0
			if frames.has("rise_back"):
				_play_once("rise_back", t / 1.8)
			else:
				sprite.texture = base_tex
			_sw_place(0.0)
			if t > 1.8:
				sub = "tease"
				t = 0.0
				main.sfx.play("grab")
				for i in 3:
					p.add_dirt(p.random_body_point(), 2)
		"tease":
			# 抱きしめようとして、嗤いながら上体を前後にグッチャグッチャ揺らす（押し返しゲージは有効）
			rub_t += delta * 1.6
			var r := sin(rub_t * TAU * 0.5)
			if frames.has("reel"):
				var arr: Array = frames["reel"]
				var n := mini(2, arr.size())
				sprite.texture = arr[clampi(int((r * 0.5 + 0.5) * float(n - 1) + 0.5), 0, n - 1)]
			elif frames.has("rub"):
				_frame("rub", int(rub_t * 4.0))
			_sw_place(r * 4.0)
			if absf(r) > 0.97 and fmod(rub_t, 1.0) < delta * 1.6:
				main.sfx.play_any(["grab_loop", "gurgle"], -6.0, 0.2)
				p.add_dirt(p.random_body_point(), 2)
				p.damage(0.5)
		"hug":
			# がっちり抱きしめた：背中しか見えない。裏で体を上下にこすりつけて汚す（背中の揺れと音とペンキで見せる）
			p.push = 0.0
			rub_t += delta * (2.4 if not main.game_over else 1.6)
			var r2 := sin(rub_t * TAU * 0.5)
			if frames.has("rub"):
				_frame("rub", int(rub_t * 4.0))
			_sw_place(r2 * 8.0)
			if absf(r2) > 0.97 and fmod(rub_t, 1.0) < delta * 2.4:
				main.sfx.play_any(["grab_loop", "gurgle"], -3.0, 0.2)
				for i in 2:
					p.add_dirt(p.random_body_point(), 2)
				p.damage(1.2)
				main.add_goop(p.position + Vector2(randf_range(-30, 30), 0), 50.0, 0.2)
				main.splat_wall(Vector2(position.x + randf_range(-90, 90), main.FLOOR_TOP - randf_range(40, 200)), 28.0, 0.6)


## 主人公が押し返しゲージを満タンにした
func on_pushed(p) -> void:
	if state != "sandwich" or sub != "tease":
		p.push = 0.0
		return
	if fake_left > 0:
		# 押されたフリ：わざとらしくのけぞって嗤う…がすぐ戻ってくる
		fake_left -= 1
		state = "pushed"
		t = 0.0
		main.sfx.play("hit", -4.0)
		return
	# 押されたフリを使い切った：遊びは終わり。がっちり抱きしめる
	state = "sandwich"
	sub = "hug"
	t = 0.0
	main.sfx.play("grab", 2.0)
	main.zoom_moment(p.position + Vector2(0, -150), 1.0)
	for i in 5:
		p.add_dirt(p.random_body_point(), 3)
	p.damage(3.0)


func _update_pushed(delta: float, p) -> void:
	if p.sandwicher != self or (p.state != "crucified" and p.state != "defeated"):
		_leave(false)
		return
	# 0〜0.5秒：大げさにのけぞる → 〜1.1秒：のけぞったまま嗤う → 戻ってきて、さっきより強く押しつける
	if frames.has("reel"):
		var arr: Array = frames["reel"]
		var f := t / 0.5 if t < 0.5 else (1.0 if t < 1.1 else maxf(1.0 - (t - 1.1) / 0.35, 0.0))
		sprite.texture = arr[clampi(int(f * float(arr.size() - 1) + 0.5), 0, arr.size() - 1)]
	if t < 0.5:
		push_off = lerpf(push_off, 40.0, 1.0 - exp(-delta * 10.0))
	elif t > 1.1:
		push_off = move_toward(push_off, 0.0, 200.0 * delta)
		if t > 1.45:
			state = "sandwich"
			sub = "tease"
			t = 0.0
			p.push = 0.0
			main.sfx.play("grab", 0.0)
			for i in 4:
				p.add_dirt(p.random_body_point(), 3)
			p.damage(2.0)
	_sw_place(0.0)


func _leave(real: bool) -> void:
	var p = main.player
	sprite.scale = Vector2.ONE
	sprite.rotation = 0.0
	maw_started = false
	combo = ""
	if p.sandwicher == self:
		p.sandwicher = null
	sprite.position = Vector2.ZERO
	state = "recover"
	t = 0.0
	vel_x = -facing * (260.0 if real else 120.0)
	if real:
		main.sfx.play("escape", -4.0)


var dive_from := Vector2.ZERO


func _maw_shark():
	for c in main.get_children():
		if c.has_method("can_maw") and c.can_maw():
			return c
	return null


func _update_hold(delta: float, p) -> void:
	# 羽交い締め：その場に根を張り、主人公は腕の中で一緒に揺らされる
	if p.state != "held" or p.held_by != self:
		_leave(true)
		return
	p.facing = facing
	sprite.scale = Vector2.ONE
	sprite.visible = true
	# ねっとり揺らす。もがく（左右連打）とグラグラ大きく揺らし返す
	if p.struggle > last_struggle + 0.01:
		wobble = minf(wobble + 1.0, 3.0)
	last_struggle = p.struggle
	wobble = move_toward(wobble, 0.0, 1.5 * delta)
	var amp := (1.0 if frames.has("hold") else 3.0) + wobble * 4.0
	var sway := sin(t * 2.2) * amp
	sprite.position = Vector2(sway, absf(sin(t * 2.2)) * 1.5).round()
	sprite.rotation = deg_to_rad(sway * 0.35)
	p.position = Vector2(position.x + facing * 22.0 + sway * 0.8, position.y + 2.0)
	match combo:
		"relax":
			# サメが来た：羽交い締めのまま寛ぐように低くなって、焦らし丸呑みを待つ
			combo_t += delta
			if frames.has("relax"):
				var arr: Array = frames["relax"]
				var i := clampi(int(combo_t / 0.9 * float(arr.size())), 0, arr.size() - 1)
				sprite.texture = arr[i]
			else:
				sprite.texture = base_tex
			return
		"throw":
			_update_throw(delta, p)
			return
	if frames.has("hold"):
		_frame("hold", int(t * 8.0))
	else:
		sprite.texture = base_tex
	# 他の敵が来るのを待つ（誰も来なければ放さない）
	if not maw_started:
		var sh = _maw_shark()
		if sh != null:
			maw_started = true
			combo = "relax"
			combo_t = 0.0
			sh.start_maw(p, self)
			return
	var w = _near_wani(p)
	if w != null:
		# ワニが来た：ワニは床に潜り、こちらは主人公を真上に放り投げる → 落ちてきたところを磔
		combo = "throw"
		combo_t = 0.0
		thrown = false
		throw_wani = w
		w.state = "sink"
		w.anim_t = 0.0
		main.request_token(w)


## 羽交い締めの近くにいて、手が空いているワニ
func _near_wani(p):
	if t < 1.2:
		return null
	for e in main.enemies:
		if is_instance_valid(e) and e.state in ["approach", "assist", "recover"] and absf(e.position.x - p.position.x) < 280.0:
			return e
	return null


func _update_throw(delta: float, p) -> void:
	combo_t += delta
	var dur := 0.9
	if frames.has("throw"):
		_play_once("throw", combo_t / dur)
	else:
		sprite.texture = base_tex
	# ワニは主人公の真下で待ち構える
	if is_instance_valid(throw_wani) and throw_wani.state == "lurk":
		throw_wani.position = Vector2(p.position.x, p.position.y)
	if not thrown and combo_t > dur * 0.55:
		thrown = true
		# 放り投げ：主人公を空中へ。真下のワニが粘液の柱で突き上げて磔にする
		p.held_by = null
		p.state = "normal"
		p.on_floor = false
		p.z = 30.0
		p.vz = 560.0
		p.invuln = 0.0
		p.hidden_in_hug = false
		main.sfx.play("escape", -2.0)
		main.add_goop(p.position, 80.0, 0.3)
	if combo_t > dur + 0.3:
		combo = ""
		sprite.position = Vector2.ZERO
		sprite.rotation = 0.0
		_start_sink()


func _update_dive(delta: float, p) -> void:
	# やたら綺麗なフォームで、引き回されている所へ頭からドップン
	var sh = p.swallower
	if sh == null or not is_instance_valid(sh) or p.state != "swallowed":
		sprite.position = Vector2.ZERO
		_start_sink()
		return
	facing = 1 if sh.position.x > dive_from.x else -1
	sprite.visible = true
	sprite.scale = Vector2.ONE
	const SPRING := 0.45
	const FLY := 0.75
	if t < SPRING:
		if frames.has("dive"):
			_play_once("dive", t / SPRING)
		else:
			_show_idle()
		return
	var k := clampf((t - SPRING) / FLY, 0.0, 1.0)
	if frames.has("dive"):
		var arr: Array = frames["dive"]
		sprite.texture = arr[arr.size() - 1]
	position = dive_from.lerp(sh.position, k)
	sprite.position = Vector2(0, -sin(k * PI) * 170.0 - 40.0 * (1.0 - k)).round()
	if k >= 1.0:
		sprite.position = Vector2.ZERO
		main.add_goop(position, 160.0, 0.6)
		main.add_ring(position, 4.0)
		main.sfx.play("gurgle", 2.0)
		get_swallowed(sh)
		sh.take_dobe(self)


func get_swallowed(_sh) -> void:
	state = "in_shark"
	visible = false


func spit_out(pos: Vector2) -> void:
	visible = true
	quick_enter = false
	position = pos
	state = "enter"
	t = 0.0


## 3対1から主人公が抜けた：地面に吐き出されたところへ、上からのしかかる
func pin_on(p) -> void:
	state = "pin"
	position = p.position
	visible = false


func on_hit(dir: int) -> void:
	if not active():
		return
	stun = 0.4
	vel_x = dir * 200.0


func on_escaped() -> void:
	_leave(true)
