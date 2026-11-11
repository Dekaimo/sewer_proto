extends Node2D
## ペンキサメ。床の下をヒレだけ出して泳ぎ、真下から丸呑み／遠くからは大ジャンプでドボン。
## 呑んだ相手を床の下で引き回してドロドロにする。
## ワニに捕まっている主人公を狙うと、ワニごと呑み込んで「地中の2対1」になる（連携の登竜門）。
## 絵は assets/same_base.png（閉じ口）と assets/same_open.png（大口）。無ければ仮の図形で描く。

const BASE_PATH := "res://assets/same_base.png"
const OPEN_PATH := "res://assets/same_open.png"
const FEET_Y := 182          # 絵の中で腹（水たまり）が床に着く行
const MOUTH_X := 92.0       # 絵の中心から口までの横の距離
const FIN_H := 52            # 泳いでいるとき床から出ている高さ（絵の上から何行ぶん＝背ビレ）

var main
var state := "swim"   # swim / gulp / leap / drag / spit / stunned
var facing := -1      # 元絵は左向き
var t := 0.0
var cd := 0.0          # 次の攻撃までの待ち
var leap_from := Vector2.ZERO
var leap_to := Vector2.ZERO
var z := 0.0
var caught_player := false
var caught_wani = null
var view_mode := "inside"   # 地中の見せ方：inside=体内の小窓 / splat=見せずにペンキが噴き出すだけ
var erupt_t := 0.0
var eruptions: Array = []   # 噴き出しの見た目 {pos, t}
var wander := 0.0
var sprite: Sprite2D
var tex_base: Texture2D
var tex_open: Texture2D
var img_cache := {}       # 切れ目の幅を調べるための画像
var collar: Node2D        # 床との境目に重ねるドロドロ（画像の切れ目を隠す）
var cut_l := 0.0
var cut_r := 0.0
var cut_on := false


func _ready() -> void:
	tex_base = load(BASE_PATH) if ResourceLoader.exists(BASE_PATH) else null
	tex_open = load(OPEN_PATH) if ResourceLoader.exists(OPEN_PATH) else tex_base
	sprite = Sprite2D.new()
	sprite.centered = false
	add_child(sprite)
	collar = Node2D.new()
	collar.draw.connect(_draw_collar)
	add_child(collar)
	cd = 2.0


func underground() -> bool:
	return state in ["swim", "drag", "stunned"]


func _process(delta: float) -> void:
	t += delta
	cd -= delta
	wander += delta
	# 飛びかかるときは主人公より手前、下から飛び出すときは主人公の後ろ（大口の中に主人公が見える）
	if state == "leap":
		z_index = int(position.y) + 3
	elif state == "gulp":
		z_index = main.player.z_index - 1
	else:
		z_index = int(position.y) - 2
	if main.game_over and state != "drag":
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
		"drag":
			_drag(delta, p)
	for er in eruptions:
		er.t += delta
	eruptions = eruptions.filter(func(er): return er.t < 0.6)
	_update_sprite()
	queue_redraw()


# ---------- 泳ぐ（ヒレだけ見えている） ----------
func _swim(delta: float, p) -> void:
	if main.game_over:
		return
	var raw: Vector2 = p.position - position
	if absf(raw.x) > MOUTH_X + 10.0:
		facing = 1 if raw.x > 0 else -1
	# 口が主人公の真下に来る位置を目指す
	var target: Vector2 = p.position - Vector2(facing * MOUTH_X, 0.0)
	var to_p: Vector2 = target - position
	# ドロドロの中は速い。乾いた床も潜って進む（通った跡がドロドロになる）
	var sp: float = 120.0 if main.goop_at(position) > 0.12 else 65.0
	if p.state == "grabbed":
		sp *= 1.3   # ワニに捕まっている獲物には一直線
	var can_hunt: bool = p.state in ["normal", "slipped", "grabbed"] and cd <= 0.0
	# 遠くにいれば大ジャンプ
	if can_hunt and to_p.length() > 320.0 and p.state != "grabbed":
		_start_leap(p)
		return
	position += to_p.normalized() * Vector2(1.0, 0.6) * sp * delta if to_p.length() > 4.0 else Vector2.ZERO
	_clamp()
	main.add_goop(position, 34.0, 0.03)
	# 真下に来たら丸呑み
	if can_hunt and absf(to_p.x) < 16.0 and absf(to_p.y) < 14.0:
		state = "gulp"
		t = 0.0
		main.sfx.play("grab", -4.0)
		# 飛び出す瞬間から寄って、呑まれるところを見せる
		main.zoom_moment(Vector2(position.x + facing * MOUTH_X, position.y - 70.0), 1.0)


# ---------- 真下から丸呑み ----------
func _gulp(delta: float, p) -> void:
	# 0〜0.3秒：大口を開けて床から飛び出す／0.3秒：呑む／〜0.7秒：沈む
	if t >= 0.3 and not has_meta("gulped"):
		set_meta("gulped", true)
		main.add_goop(position, 140.0, 0.5)
		main.splat_wall(Vector2(position.x, main.FLOOR_TOP - 60.0), 50.0)
		_try_swallow(p, 48.0)
	if t > 0.7:
		remove_meta("gulped")
		_sink_after_attack()


# ---------- 大ジャンプしてドボン ----------
func _start_leap(p) -> void:
	state = "leap"
	t = 0.0
	leap_from = position
	# 着地点は主人公の今いる場所（動けば外せる）
	facing = 1 if p.position.x > position.x else -1
	leap_to = p.position - Vector2(facing * MOUTH_X, 0.0)
	leap_to.x = clampf(leap_to.x, main.ARENA_L, main.ARENA_R)
	main.sfx.play("grab", -2.0)


func _leap(delta: float, p) -> void:
	var dur := 1.0
	var k := clampf(t / dur, 0.0, 1.0)
	position = leap_from.lerp(leap_to, k)
	z = sin(k * PI) * 240.0
	if k >= 1.0:
		z = 0.0
		main.add_goop(position, 220.0, 0.7)
		for i in 3:
			main.splat_wall(Vector2(position.x + randf_range(-160.0, 160.0), main.FLOOR_TOP - randf_range(20.0, 160.0)), randf_range(40.0, 70.0))
		main.sfx.play("assist")
		_try_swallow(p, 70.0)
		_sink_after_attack()


# ---------- 呑み込み判定 ----------
func _try_swallow(p, r: float) -> void:
	var mouth: float = position.x + facing * MOUTH_X
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
		view_mode = "inside" if randf() < 0.5 else "splat"
	else:
		state = "swim"
		cd = randf_range(2.5, 4.0)


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


## 主人公が自力で脱出したとき
func on_escaped() -> void:
	caught_player = false
	if caught_wani != null and is_instance_valid(caught_wani):
		caught_wani.spit_out(position + Vector2(-facing * 60.0, 0.0))
	caught_wani = null
	state = "stunned"
	t = 0.0
	cd = 4.0


func _clamp() -> void:
	position.x = clampf(position.x, main.ARENA_L, main.ARENA_R)
	position.y = clampf(position.y, main.DEPTH_MIN, main.DEPTH_MAX)


# ---------- 見た目 ----------
func _update_sprite() -> void:
	if tex_base == null:
		sprite.visible = false
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
	# 床を突き破るペンキの柱（地中で何かされている）
	for er in eruptions:
		var k: float = er.t / 0.6
		var base: Vector2 = er.pos - position
		var hgt: float = sin(k * PI) * 110.0
		var w: float = 18.0 * (1.0 - k * 0.5)
		draw_rect(Rect2(base.x - w * 0.5, base.y - hgt, w, hgt), Color("5a1240"))
		draw_rect(Rect2(base.x - w * 0.5 + 3, base.y - hgt + 2, w - 6, hgt - 2), Color("ec5a9e"))
		draw_rect(Rect2(base.x - 2, base.y - hgt + 4, 4, hgt * 0.6), Color("f9d84d"))
		for j in 6:
			var a := j * 1.05 + k * 2.0
			var d := Vector2(cos(a), -absf(sin(a))) * (20.0 + 90.0 * k)
			draw_circle(base + Vector2(0, -hgt) + d, 6.0 * (1.0 - k) + 1.0, Color("ec5a9e") if j % 2 else Color("f9d84d"))
	if not underground():
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
