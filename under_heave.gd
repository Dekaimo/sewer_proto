extends RefCounted
## 地中で暴れているものを、床のペンキの盛り上がりで見せる。
## 別の生き物（盛り上がりの絵）を上に乗せるのではなく、床のドロドロそのものが
## 下から押し上げられて、うねり、波紋が広がり、通った跡が残る。
## 毎フレーム step() を呼ぶ。描くのは床のシェーダー（main.add_heave / add_ring）。

var t := 0.0
var mode_t := 0.0
var violent := false
var breath := 0.0
var limbs: Array = []        # 中から突き上げる手足／頭 {off, t, dur, amp, r}
var last_pos := Vector2.ZERO
var trail_acc := 0.0
var bubble_t := 0.0
var bubbles: Array = []      # 弾ける泡（呼び出し元が描く）{pos, t, r}
var globs: Array = []        # 跳ねて糸を引きながら落ちる重い塊 {pos, vel, r, from, t}
var snaps: Array = []        # ちぎれた糸の名残 {a, b, t}


## carrier: 地中で引き回している本体の位置（床の座標）。intensity: 0〜1（2対1・3対1ほど激しい）
func step(main, delta: float, carrier: Vector2, intensity: float) -> void:
	t += delta
	mode_t -= delta
	if mode_t <= 0.0:
		violent = randf() < 0.45 + 0.35 * intensity
		mode_t = randf_range(0.3, 0.8) if violent else randf_range(0.5, 1.3)
		if violent:
			# 暴れ始め：重い波紋が床に広がる
			main.add_ring(carrier + Vector2(randf_range(-20, 20), 0), 2.5 + 2.0 * intensity)
	# 本体のうねり：ゆっくり大きく呼吸するように膨らみ、暴れると不規則に脈打つ
	breath += delta * (5.5 if violent else 1.6)
	var swell := 5.0 + 2.5 * sin(breath) + (4.0 * absf(sin(breath * 2.3)) if violent else 0.0)
	main.add_heave(carrier, 62.0 + 10.0 * intensity, swell * (1.0 + 0.4 * intensity))
	# 後ろに引きずられる小さなうねり（重い粘液の中を進んでいる感じ）
	var mv := carrier - last_pos
	if mv.length() > 0.01:
		var back := -mv.normalized()
		main.add_heave(carrier + back * 42.0, 40.0, swell * 0.45)
		main.add_heave(carrier + back * 80.0, 30.0, swell * 0.2)
	# 中から手足や頭が突き上げる：ぐっと鋭く盛り上がって、ゆっくりペンキに沈み戻る
	var rate := (4.5 if violent else 0.8) * (0.7 + intensity * 0.6)
	if randf() < rate * delta and limbs.size() < 4:
		limbs.append({"off": Vector2(randf_range(-46, 46), randf_range(-14, 14)), "t": 0.0,
			"dur": randf_range(0.35, 0.8), "amp": randf_range(10.0, 20.0) * (1.0 + 0.4 * intensity),
			"r": randf_range(14.0, 24.0)})
		main.sfx.play_any(["grab_loop", "gurgle"], -4.0 + 3.0 * intensity, 0.12)
	for l in limbs:
		l.t += delta
		var k: float = l.t / l.dur
		# 立ち上がりは速く（0.2）、沈むのはゆっくり
		var hk := (k / 0.2) if k < 0.2 else pow(maxf(1.0 - (k - 0.2) / 0.8, 0.0), 1.6)
		main.add_heave(carrier + l.off, l.r, l.amp * clampf(hk, 0.0, 1.0))
		if k >= 0.2 and k - delta / l.dur < 0.2:
			# 突き上げた瞬間、まわりのペンキが押しのけられて波紋と飛沫
			main.add_ring(carrier + l.off, 1.6)
			main.add_goop(carrier + l.off, randf_range(30, 50), 0.25)
			var top: Vector2 = carrier + l.off - Vector2(0, l.amp * 0.9)
			for g in randi_range(2, 4):
				globs.append({"pos": top, "vel": Vector2(randf_range(-80, 80), -randf_range(150, 260)), "r": randf_range(3.0, 6.0), "from": top, "t": 0.0, "floor": carrier.y + l.off.y + randf_range(-6, 10)})
		l["peak"] = carrier + l.off - Vector2(0, l.amp * clampf(hk, 0.0, 1.0) * 0.9)
		l["base"] = carrier + l.off
		l["hk"] = clampf(hk, 0.0, 1.0)
		if k > 0.85 and not l.has("snapped"):
			# 伸びきった糸がちぎれる
			l["snapped"] = true
			snaps.append({"a": l.base + Vector2(-l.r * 0.5, 0), "b": l.base + Vector2(-l.r * 0.3, -l.amp * 0.5), "t": 0.0})
			snaps.append({"a": l.base + Vector2(l.r * 0.5, 0), "b": l.base + Vector2(l.r * 0.3, -l.amp * 0.5), "t": 0.0})
			main.sfx.play("step_paint", -8.0, 0.15)
	limbs = limbs.filter(func(l): return l.t < l.dur)
	# 通った跡：ペンキがかき分けられて、厚い筋が残る
	trail_acc += mv.length()
	if trail_acc > 10.0:
		trail_acc = 0.0
		main.add_goop(carrier + Vector2(randf_range(-30, 30), randf_range(-8, 8)), randf_range(55, 90), 0.22 + 0.1 * intensity)
	last_pos = carrier
	# 跳ねた塊：重く落ちて、床にベチャッ
	for g in globs:
		g.t += delta
		g.vel.y += 760.0 * delta
		g.pos += g.vel * delta
		if g.vel.y > 0.0 and g.pos.y >= g.floor:
			g.t = 99.0
			main.add_goop(g.pos, randf_range(16, 28), 0.2)
			main.sfx.play("step_paint", -10.0, 0.08)
	globs = globs.filter(func(g): return g.t < 5.0)
	for sn in snaps:
		sn.t += delta
	snaps = snaps.filter(func(sn): return sn.t < 0.45)
	# 泡：中の空気が押し出されて、ぷくっと膨らんで弾ける
	bubble_t -= delta
	if bubble_t <= 0.0:
		bubble_t = randf_range(0.08, 0.3) if violent else randf_range(0.3, 0.8)
		bubbles.append({"pos": carrier + Vector2(randf_range(-60, 60), randf_range(-14, 10)), "t": 0.0, "r": randf_range(3.0, 7.0)})
	for b in bubbles:
		b.t += delta
	bubbles = bubbles.filter(func(b): return b.t < 0.55)


## 粘っこい糸（たるんで垂れる）。太さ w、輪郭つき
static func _strand(ci: CanvasItem, a: Vector2, b: Vector2, sag: float, w: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 9:
		var k := i / 8.0
		var p := a.lerp(b, k) + Vector2(0, sin(k * PI) * sag)
		pts.append(p.round())
	ci.draw_polyline(pts, Color("8a1f5c"), w + 2.0)
	ci.draw_polyline(pts, col, w)
	# 上側のてかり
	ci.draw_polyline(PackedVector2Array([pts[2] + Vector2(0, -w * 0.3), pts[4] + Vector2(0, -w * 0.3)]), Color("f489bd"), maxf(w * 0.3, 1.0))
	# 真ん中に溜まったしずく
	var mid := a.lerp(b, 0.5) + Vector2(0, sag)
	ci.draw_circle(mid.round() + Vector2(0, 1), w * 0.9 + 1.0, Color("8a1f5c"))
	ci.draw_circle(mid.round() + Vector2(0, 1), w * 0.9, col)


## 泡・糸・跳ねた塊を描く（呼び出し元の _draw から。origin は呼び出し元の位置）
func draw_bubbles(ci: CanvasItem, origin: Vector2) -> void:
	var dark := Color("5a1240")
	var pink := Color("ec5a9e")
	var shine := Color("ffd6ea")
	# 沈んでいく手足と床のあいだに引かれる、太い膜のような糸（上から下へ、だらっと伸びる）
	for l in limbs:
		if not l.has("peak") or l.has("snapped"):
			continue
		var k: float = l.t / l.dur
		if k < 0.25:
			continue
		var w: float = lerpf(6.0, 2.5, (k - 0.25) / 0.6)
		var pk: Vector2 = l.peak - origin
		var bs: Vector2 = l.base - origin
		_strand(ci, pk + Vector2(-l.r * 0.2, 2), bs + Vector2(-l.r * 0.55, -l.amp * 0.15), 2.0 + 3.0 * k, w, Color("d84a8c"))
		if int(l.r) % 2 == 0:
			_strand(ci, pk + Vector2(l.r * 0.2, 2), bs + Vector2(l.r * 0.5, -l.amp * 0.12), 2.0 + 2.0 * k, w * 0.75, Color("d84a8c"))
	# ちぎれた糸：根元へ縮んで垂れ落ちる
	for sn in snaps:
		var kk: float = sn.t / 0.45
		var a: Vector2 = sn.a - origin
		var b: Vector2 = (sn.b - origin).lerp(a, kk) + Vector2(0, kk * 6.0)
		_strand(ci, a, b, 2.0, 1.5, pink)
	# 跳ねた塊：速さの向きに伸びて、出てきたところへ細い糸を引く（最初だけ）
	for g in globs:
		var c: Vector2 = (g.pos - origin).round()
		if g.t < 0.22:
			var w2 := lerpf(2.0, 0.8, g.t / 0.22)
			ci.draw_line((g.from - origin).round(), c, dark, w2 + 2.0)
			ci.draw_line((g.from - origin).round(), c, pink, w2)
		var st: float = clampf(g.vel.length() / 300.0, 0.0, 0.8)
		var dir: Vector2 = g.vel.normalized() if g.vel.length() > 1.0 else Vector2.DOWN
		ci.draw_circle(c, g.r + 1.5, dark)
		ci.draw_circle(c - dir * g.r * st, g.r * 0.8 + 1.5, dark)
		ci.draw_circle(c, g.r, pink)
		ci.draw_circle((c - dir * g.r * st).round(), g.r * 0.8, pink)
		ci.draw_rect(Rect2(c + Vector2(-g.r * 0.4, -g.r * 0.6), Vector2(2, 1)), shine)
	for b in bubbles:
		var k: float = b.t / 0.55
		var c: Vector2 = (b.pos - origin).round()
		if k < 0.7:
			# ぷくっと膨らむ
			var r: float = b.r * (k / 0.7)
			ci.draw_circle(c + Vector2(0, -r * 0.6), r + 1.0, dark)
			ci.draw_circle(c + Vector2(0, -r * 0.6), r, pink)
			ci.draw_rect(Rect2(c + Vector2(-r * 0.4, -r * 1.2), Vector2(2, 2)), shine)
		else:
			# 弾けて、しずくが飛ぶ
			var kk: float = (k - 0.7) / 0.3
			for i in 4:
				var a := i * 1.57 + 0.6
				var d: Vector2 = Vector2(cos(a), sin(a) * 0.5 - 0.6) * (b.r + 6.0 * kk)
				ci.draw_rect(Rect2(c + d.round() + Vector2(0, -2), Vector2(2, 2)), pink)
