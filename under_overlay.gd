extends Node2D
## 地中で暴れている獲物を「平べったいネバネバの山」のアニメで見せる。
## 生成した動きのパターン（assets/mnd_<名前>_0..15、どれも平らな水たまりで始まって終わる）を
## ランダムにつないで再生する：
##   writhe  うねうね（下で何かがもがく）
##   thrash  下から激しく突き上げて、塊が跳ねる（2種）
##   ooze    じわっと膨らんで、しわが寄って、しぼむ（2種）
##   surge   片側へずるっと押し寄せる（引きずられている）（2種）
## 速さ・向き・位置のずれもその都度変え、途中で引き返すこともある。
## 線は床のペンキの暗いピンクに寄せ、下は床に溶け込ませる（under_blend.gdshader）。

const BLEND = preload("res://under_blend.gdshader")
const FEET := 232.0

var patterns := {}
var sp: Sprite2D
var mat: ShaderMaterial
var cur := ""
var f := 0.0
var speed := 12.0
var dir := 1.0
var turn_at := 99.0
var off := Vector2.ZERO
var t := 0.0
var allow_drag := false   # （互換のため残している）


func _ready() -> void:
	for n in ["writhe", "thrash", "thrash2", "ooze", "ooze2", "surge", "surge2"]:
		var arr: Array[Texture2D] = []
		var i := 0
		while ResourceLoader.exists("res://assets/mnd_%s_%d.png" % [n, i]):
			arr.append(load("res://assets/mnd_%s_%d.png" % [n, i]))
			i += 1
		if arr.size() > 0:
			patterns[n] = arr
	sp = Sprite2D.new()
	sp.centered = false
	sp.offset = Vector2(-128, -FEET)
	mat = ShaderMaterial.new()
	mat.shader = BLEND
	mat.set_shader_parameter("fade_top", 0.93)
	mat.set_shader_parameter("fade_bot", 0.97)
	sp.material = mat
	add_child(sp)
	visible = false


func has_art() -> bool:
	return patterns.size() > 0


func stop() -> void:
	visible = false
	cur = ""


func _next(intensity: float) -> void:
	# 激しいほど thrash / surge が多く、1人でぐったりしてくると ooze が多い
	var w := {"writhe": 3.0, "thrash": 1.0 + 2.5 * intensity, "thrash2": 1.0 + 2.5 * intensity,
		"ooze": 2.5 - intensity, "ooze2": 2.5 - intensity, "surge": 1.5 + intensity, "surge2": 1.5 + intensity}
	var total := 0.0
	for k in patterns.keys():
		if k != cur:
			total += w.get(k, 1.0)
	var r := randf() * total
	for k in patterns.keys():
		if k == cur:
			continue
		r -= w.get(k, 1.0)
		if r <= 0.0:
			cur = k
			break
	f = 0.0
	dir = 1.0
	speed = randf_range(9.0, 16.0) * (0.8 + 0.4 * intensity)
	# 3回に1回くらい、出きる前に引き返す（引きずり込まれる・力尽きる）
	var n: int = patterns[cur].size()
	turn_at = randf_range(n * 0.45, n * 0.7) if randf() < 0.33 else 99.0
	sp.flip_h = randf() < 0.5
	off = Vector2(randf_range(-16.0, 16.0), randf_range(-4.0, 4.0)).round()


## intensity: 0〜1（1人／2対1／3対1）
func step(delta: float, intensity: float) -> void:
	if patterns.is_empty():
		return
	visible = true
	t += delta
	if cur == "":
		_next(intensity)
	var arr: Array = patterns[cur]
	f += delta * speed * dir
	if dir > 0.0 and f >= turn_at:
		dir = -1.0
	if (dir > 0.0 and f >= float(arr.size())) or (dir < 0.0 and f <= 0.0):
		_next(intensity)
		arr = patterns[cur]
	sp.texture = arr[clampi(int(f), 0, arr.size() - 1)]
	var shake := 1.5 if cur.begins_with("thrash") else 0.0
	sp.position = off + Vector2(sin(t * 41.0) * shake, 0).round()
