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
	var swell := 9.0 + 4.0 * sin(breath) + (6.0 * absf(sin(breath * 2.3)) if violent else 0.0)
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
			"dur": randf_range(0.35, 0.8), "amp": randf_range(16.0, 30.0) * (1.0 + 0.4 * intensity),
			"r": randf_range(14.0, 24.0)})
	for l in limbs:
		l.t += delta
		var k: float = l.t / l.dur
		# 立ち上がりは速く（0.2）、沈むのはゆっくり
		var hk := (k / 0.2) if k < 0.2 else pow(1.0 - (k - 0.2) / 0.8, 1.6)
		main.add_heave(carrier + l.off, l.r, l.amp * clampf(hk, 0.0, 1.0))
		if k >= 0.2 and k - delta / l.dur < 0.2:
			# 突き上げた瞬間、まわりのペンキが押しのけられて波紋と飛沫
			main.add_ring(carrier + l.off, 1.6)
			main.add_goop(carrier + l.off, randf_range(30, 50), 0.25)
	limbs = limbs.filter(func(l): return l.t < l.dur)
	# 通った跡：ペンキがかき分けられて、厚い筋が残る
	trail_acc += mv.length()
	if trail_acc > 10.0:
		trail_acc = 0.0
		main.add_goop(carrier + Vector2(randf_range(-30, 30), randf_range(-8, 8)), randf_range(55, 90), 0.22 + 0.1 * intensity)
	last_pos = carrier
	# 泡：中の空気が押し出されて、ぷくっと膨らんで弾ける
	bubble_t -= delta
	if bubble_t <= 0.0:
		bubble_t = randf_range(0.08, 0.3) if violent else randf_range(0.3, 0.8)
		bubbles.append({"pos": carrier + Vector2(randf_range(-60, 60), randf_range(-14, 10)), "t": 0.0, "r": randf_range(3.0, 7.0)})
	for b in bubbles:
		b.t += delta
	bubbles = bubbles.filter(func(b): return b.t < 0.55)


## 泡を描く（呼び出し元の _draw から。origin は呼び出し元の位置）
func draw_bubbles(ci: CanvasItem, origin: Vector2) -> void:
	var dark := Color("5a1240")
	var pink := Color("ec5a9e")
	var shine := Color("ffd6ea")
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
