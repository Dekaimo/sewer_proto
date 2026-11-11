extends RefCounted
## ※ 今は生成したドット絵（assets/goo_mound_*.png）を Sprite で出している。これは絵が無いときの予備。
## 地中で何かが暴れているときの、床の盛り上がり（ドロドロがグチュグチュ蠢く）。
## サメの引き回しとワニの引きずり込みの両方から呼ぶ。描くのは呼び出し元の CanvasItem。
## ドット絵になじむよう、輪郭（濃い色）→本体（ピンク）→影→小さなてかり の順に重ねる。

const DARK := Color("5a1240")
const SHADE := Color("b8357a")
const PINK := Color("ec5a9e")
const SHINE := Color("ffd6ea")
const YEL := Color("f9d84d")


static func _blobs(t: float, size: float, violent: float) -> Array:
	# 塊ごとの位置と半径（ばらばらに膨らんだり縮んだりする）
	var out := []
	var n := 6
	for k in n:
		var ph := t * (2.0 + violent * 2.5) + k * 1.37
		var bulge := 0.5 + 0.5 * sin(ph) * sin(ph * 0.61 + k * 0.9)
		var x := (k - (n - 1) * 0.5) * size * 0.2 + sin(ph * 0.5 + k) * 5.0
		var r := size * (0.13 + 0.10 * bulge) * (0.85 + violent * 0.35)
		var y := -r * (0.35 + 0.45 * bulge)
		out.append([Vector2(x, y), r])
	return out


static func draw(ci: CanvasItem, t: float, size: float, violent: float) -> void:
	var blobs := _blobs(t, size, violent)
	# 床に広がる裾
	ci.draw_set_transform(Vector2(0, 2), 0.0, Vector2(1.0, 0.25))
	ci.draw_circle(Vector2.ZERO, size * 0.62, DARK)
	ci.draw_circle(Vector2.ZERO, size * 0.58, SHADE)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 塊：輪郭 → 本体 → 下側の影 → 上の小さなてかり
	for b in blobs:
		ci.draw_circle(b[0].round(), b[1] + 2.0, DARK)
	for b in blobs:
		ci.draw_circle(b[0].round(), b[1], PINK)
	for b in blobs:
		ci.draw_circle((b[0] + Vector2(0, b[1] * 0.35)).round(), b[1] * 0.7, SHADE)
		ci.draw_circle((b[0] + Vector2(0, b[1] * 0.15)).round(), b[1] * 0.62, PINK)
	for i in blobs.size():
		var b = blobs[i]
		ci.draw_rect(Rect2((b[0] + Vector2(-b[1] * 0.35, -b[1] * 0.6)).round(), Vector2(maxf(b[1] * 0.3, 2.0), 2.0)), SHINE)
		if i % 2 == 0:
			ci.draw_line((b[0] + Vector2(-b[1] * 0.5, 0)).round(), (b[0] + Vector2(b[1] * 0.2, -b[1] * 0.3)).round(), YEL, 2.0)
	# 中から押し上げる「何か」：塊がぐっと突き出して、すぐ引っ込む
	for k in 2:
		var ph3 := fmod(t * (0.9 + violent) + k * 0.5, 1.0)
		if ph3 < 0.45:
			var bx := (k - 0.5) * size * 0.4 + sin(t * 2.0 + k) * 6.0
			var hh := sin(ph3 / 0.45 * PI) * size * (0.22 + violent * 0.2)
			var c := Vector2(bx, -size * 0.18 - hh).round()
			var rr := size * 0.08
			ci.draw_circle(c, rr + 2.0, DARK)
			ci.draw_circle(c, rr, PINK)
			ci.draw_rect(Rect2(c + Vector2(-rr * 0.3, -rr * 0.6), Vector2(3, 2)), SHINE)
	# 弾ける泡と、飛び散るしずく
	for k in 7:
		var ph4 := fmod(t * (1.6 + violent * 1.5) + k * 0.31, 1.0)
		var bx2 := sin(k * 2.7 + t * 0.9) * size * 0.5
		var by := -size * 0.3 - ph4 * size * 0.45
		var rr2 := 2.0 + 5.0 * ph4
		var c2 := PINK if k % 3 else YEL
		c2.a = 1.0 - ph4 * 0.6
		ci.draw_circle(Vector2(bx2, by).round(), rr2 + 1.5, Color(DARK, c2.a))
		ci.draw_circle(Vector2(bx2, by).round(), rr2, c2)


## 生成したドット絵の盛り上がり（8コマ）を読み込む
static func load_frames() -> Array[Texture2D]:
	var arr: Array[Texture2D] = []
	for i in 8:
		var path := "res://assets/goo_mound_%d.png" % i
		if ResourceLoader.exists(path):
			arr.append(load(path))
	return arr
