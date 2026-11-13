extends Node2D
## 擦りつけたときにグチュッと飛び散る粘液の粒（ネバネバ版）。
## - 粒は出どころと細い糸でつながったまま伸び、伸びきるとプツッと切れる（切れた糸は縮んで消える）
## - 一部の粒は切れずに引き戻されて、垂れ下がりながら戻っていく（ビヨン）
## - 空気抵抗が強く、重たくボトッと落ちる。床に落ちると一瞬べちゃっと潰れてから床のペンキになる

var main
var drops: Array = []    # 飛んでいる粒
var snaps: Array = []    # 切れた直後の糸（縮んで消える）
var flats: Array = []    # 床でべちゃっと潰れた粒

const COLS := [Color("ff5fb0"), Color("ff7cc4"), Color("ffd84a"), Color("e8489a")]
const EDGE := Color("5a1240")
const STRAND := Color("ff6fbd")
const GRAV := 780.0
const DRAG := 2.2            # 粘り（大きいほどすぐ減速する）


## at=飛び散る中心、floor_y=落ちる床の高さ、sticky=切れずに戻ってくる粒の割合（0〜1）
func burst(at: Vector2, floor_y: float, n: int = 8, power: float = 1.0, dir: int = 0, sticky: float = 0.3) -> void:
	for i in n:
		var sx := float(dir) if dir != 0 else (-1.0 if randf() < 0.5 else 1.0)
		var v := Vector2(sx * randf_range(50.0, 190.0), -randf_range(140.0, 320.0)) * power
		var a := at + Vector2(randf_range(-14, 14), randf_range(-8, 8))
		var stay := randf() < sticky
		drops.append({
			"p": a, "v": v, "a": a,
			"floor_y": floor_y + randf_range(-6, 6),
			"r": randf_range(1.5, 3.0) if randf() < 0.75 else randf_range(3.0, 4.5),
			"col": COLS[randi() % COLS.size()],
			"tether": true,
			"stay": stay,                                   # 切れずに戻る粒
			"maxlen": randf_range(22.0, 48.0) * (1.4 if stay else 1.0),
			"t": 0.0,
		})


func _process(delta: float) -> void:
	if drops.is_empty() and snaps.is_empty() and flats.is_empty():
		return
	var keep: Array = []
	for d in drops:
		d.t += delta
		d.v.y += GRAV * delta
		d.v *= exp(-DRAG * delta)
		if d.tether:
			var to_a: Vector2 = d.a - d.p
			var len := to_a.length()
			if d.stay:
				# 糸に引かれてビヨンと戻る（ゴムのような引き戻し）
				d.v += to_a * 9.0 * delta
				if d.t > 0.9 or (d.t > 0.35 and len < 4.0):
					continue   # 元の塊に戻って消える
			elif len > d.maxlen:
				# 伸びきってプツッと切れる
				d.tether = false
				snaps.append({"a": d.a, "b": d.p, "life": 0.18, "w": d.r * 0.7})
		d.p += d.v * delta
		if d.p.y >= d.floor_y and d.v.y > 0.0:
			flats.append({"p": Vector2(d.p.x, d.floor_y), "r": d.r, "col": d.col, "life": 0.35})
			if main != null:
				main.add_goop(Vector2(d.p.x, d.floor_y), 10.0 + d.r * 4.0, 0.12)
			continue
		if d.t < 3.0:
			keep.append(d)
	drops = keep
	var ks: Array = []
	for s in snaps:
		s.life -= delta
		# 切れた糸は両端から縮む
		s.b = s.b.lerp(s.a, 1.0 - exp(-18.0 * delta))
		if s.life > 0.0:
			ks.append(s)
	snaps = ks
	var kf: Array = []
	for f in flats:
		f.life -= delta
		if f.life > 0.0:
			kf.append(f)
	flats = kf
	queue_redraw()


## 細い糸：根元が少し太く、先へ行くほど細い（太すぎない）
func _strand(a: Vector2, b: Vector2, w: float) -> void:
	var n := 5
	var prev := a
	for i in range(1, n + 1):
		var k := float(i) / float(n)
		var q := a.lerp(b, k) + Vector2(0, sin(k * PI) * 3.0)   # 少したるむ
		var ww := maxf(lerpf(w, 1.0, k), 1.0)
		draw_line(prev.round(), q.round(), STRAND, ww)
		prev = q


func _draw() -> void:
	for s in snaps:
		_strand(s.a, s.b, s.w * clampf(s.life / 0.18, 0.3, 1.0))
	for d in drops:
		if d.tether:
			_strand(d.a, d.p, minf(d.r * 0.8, 2.5))
	for f in flats:
		# べちゃっと潰れた粒：横に広い楕円
		var k: float = 1.0 - f.life / 0.35
		var rx: float = f.r * (1.4 + k * 1.2)
		var ry: float = maxf(f.r * (0.6 - k * 0.3), 1.0)
		var c: Vector2 = f.p.round()
		draw_rect(Rect2(c - Vector2(rx + 1, ry + 1), Vector2(rx * 2 + 2, ry * 2 + 2)), EDGE)
		draw_rect(Rect2(c - Vector2(rx, ry), Vector2(rx * 2, ry * 2)), f.col)
	for d in drops:
		var r: float = d.r
		var sp: float = d.v.length()
		var stretch := clampf(sp / 300.0, 0.0, 1.0) * r * 1.8
		var back: Vector2 = -d.v.normalized() * stretch if sp > 1.0 else Vector2.ZERO
		var p: Vector2 = d.p.round()
		for k in 3:
			draw_circle((p + back * (float(k) / 2.0)).round(), r + 1.0 - float(k) * 0.4, EDGE)
		for k in 3:
			draw_circle((p + back * (float(k) / 2.0)).round(), r - float(k) * 0.4, d.col)
		draw_rect(Rect2((p + Vector2(-r * 0.4, -r * 0.5)).round(), Vector2(1, 1)), Color(1, 1, 1, 0.85))
