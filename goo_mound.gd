extends RefCounted
## 地中で何かが暴れているときの、床の盛り上がり（ドロドロがグチュグチュ蠢く）。
## サメの引き回しとワニの引きずり込みの両方から呼ぶ。描くのは呼び出し元の CanvasItem。

const DARK := Color("5a1240")
const PINK := Color("ec5a9e")
const LIGHT := Color("f489bd")
const SHINE := Color("ffd6ea")
const YEL := Color("f9d84d")


static func draw(ci: CanvasItem, t: float, size: float, violent: float) -> void:
	# 盛り上がりの本体：いくつもの塊がばらばらに膨らんだり縮んだりする
	var n := 7
	for pass_i in 3:
		var col: Color = [DARK, PINK, LIGHT][pass_i]
		var shrink: float = [0.0, 4.0, 10.0][pass_i]
		for k in n:
			var ph := t * (2.2 + violent * 2.0) + k * 1.37
			var x := (k - (n - 1) * 0.5) * size * 0.26 + sin(ph * 0.7) * 6.0
			var bulge := 0.55 + 0.45 * sin(ph) * sin(ph * 0.53 + k)
			var h := size * (0.35 + 0.35 * bulge) * (0.8 + violent * 0.5)
			var r := size * 0.22 * (0.8 + 0.4 * bulge) - shrink
			if r <= 1.0:
				continue
			ci.draw_set_transform(Vector2(roundf(x), roundf(-h * 0.35 - shrink * 0.5)), 0.0, Vector2(1.0, 0.62))
			ci.draw_circle(Vector2.ZERO, r, col)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# てかりと黄色のマーブル
	for k in 4:
		var ph2 := t * 1.6 + k * 2.1
		var x2 := sin(ph2) * size * 0.45
		ci.draw_line(Vector2(x2 - 6, -size * 0.32), Vector2(x2 + 5, -size * 0.28), YEL, 2.0)
		ci.draw_rect(Rect2(roundf(x2 + 8), roundf(-size * 0.40), 4, 2), SHINE)
	# 中から押し上げられる「何か」の形（手足や体がもがいているように見える突起）
	for k in 3:
		var ph3 := fmod(t * (1.1 + violent) + k * 0.41, 1.0)
		if ph3 < 0.5:
			var bx := (k - 1) * size * 0.35 + sin(t * 3.0 + k) * 8.0
			var hh := sin(ph3 * TAU) * size * (0.25 + violent * 0.25)
			ci.draw_rect(Rect2(roundf(bx - 7), roundf(-size * 0.3 - hh), 14, hh), DARK)
			ci.draw_rect(Rect2(roundf(bx - 4), roundf(-size * 0.3 - hh + 2), 8, hh), PINK)
			ci.draw_circle(Vector2(roundf(bx), roundf(-size * 0.3 - hh)), 8.0, PINK)
	# 弾ける泡と、飛び散るしずく
	for k in 8:
		var ph4 := fmod(t * (1.8 + violent * 1.5) + k * 0.29, 1.0)
		var bx2 := sin(k * 2.7 + t * 0.9) * size * 0.55
		var by := -size * 0.35 - ph4 * size * 0.5
		var rr := 2.0 + 7.0 * ph4
		var c := PINK if k % 3 else YEL
		c.a = 1.0 - ph4 * 0.6
		ci.draw_circle(Vector2(bx2, by), rr + 1.5, Color(DARK, c.a))
		ci.draw_circle(Vector2(bx2, by), rr, c)
		ci.draw_arc(Vector2(bx2, by), rr, PI * 1.1, PI * 1.6, 6, Color(1, 0.9, 0.95, c.a), 1.0)
