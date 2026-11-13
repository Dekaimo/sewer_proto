extends Node2D
## 擦りつけたときにグチュッと飛び散る粘液の粒。ドット絵の粒（ピンク・黄色＋暗い縁）を放物線で飛ばし、
## 飛んでいる間は進む向きに少し伸ばす。床（出た場所の高さ）に落ちたら床のペンキにする。

var main
var drops: Array = []   # {p, v, floor_y, r, col, life}

const COLS := [Color("ff5fb0"), Color("ff7cc4"), Color("ffd84a"), Color("e8489a")]
const EDGE := Color("5a1240")
const GRAV := 900.0


## 粒をまとめて飛ばす。at=飛び散る中心（世界座標）、floor_y=落ちる床の高さ、dir=主に飛ぶ横向き（0なら左右両方）
func burst(at: Vector2, floor_y: float, n: int = 8, power: float = 1.0, dir: int = 0) -> void:
	for i in n:
		var sx := float(dir) if dir != 0 else (-1.0 if randf() < 0.5 else 1.0)
		var v := Vector2(sx * randf_range(40.0, 170.0), -randf_range(120.0, 300.0)) * power
		drops.append({
			"p": at + Vector2(randf_range(-14, 14), randf_range(-8, 8)),
			"v": v,
			"floor_y": floor_y + randf_range(-6, 6),
			"r": randf_range(1.5, 3.5) if randf() < 0.8 else randf_range(3.5, 5.0),
			"col": COLS[randi() % COLS.size()],
			"life": 2.0,
		})


func _process(delta: float) -> void:
	if drops.is_empty():
		return
	var keep: Array = []
	for d in drops:
		d.v.y += GRAV * delta
		d.p += d.v * delta
		d.life -= delta
		if d.p.y >= d.floor_y and d.v.y > 0.0:
			if main != null:
				main.add_goop(Vector2(d.p.x, d.floor_y), 10.0 + d.r * 4.0, 0.12)
			continue
		if d.life > 0.0:
			keep.append(d)
	drops = keep
	queue_redraw()


func _draw() -> void:
	for d in drops:
		var r: float = d.r
		var sp: float = d.v.length()
		# 速いほど進行方向に伸びる（2〜3つの丸をつないだ、しずく形）
		var stretch := clampf(sp / 300.0, 0.0, 1.0) * r * 1.6
		var back: Vector2 = -d.v.normalized() * stretch if sp > 1.0 else Vector2.ZERO
		var p: Vector2 = d.p.round()
		for k in 3:
			var q: Vector2 = (p + back * (float(k) / 2.0)).round()
			draw_circle(q, r + 1.0 - float(k) * 0.4, EDGE)
		for k in 3:
			var q: Vector2 = (p + back * (float(k) / 2.0)).round()
			draw_circle(q, r - float(k) * 0.4, d.col)
		# ツヤ
		draw_rect(Rect2((p + Vector2(-r * 0.4, -r * 0.5)).round(), Vector2(1, 1)), Color(1, 1, 1, 0.85))
