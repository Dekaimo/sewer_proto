extends Node2D
## 地中で暴れている獲物を「ネバネバの山」で見せる（平たく潰した山のドット絵 goo_flat_0..7）。
## 毎回同じ動きにならないように、動き方のパターンをランダムに切り替える：
##   pulse   じわじわ脈打つ（ぐったり／力をためる）
##   thrash  激しく暴れる（速く、揺れる）
##   writhe  逆回しでうねる
##   lean    片側に寄って、ぐーっと膨らむ
##   twin    横にもう一つ小さな山が盛り上がる（手足が別のところを押し上げる）
## 線は床のペンキの暗いピンクに寄せ、下は床に溶け込ませる（under_blend.gdshader）。

const BLEND = preload("res://under_blend.gdshader")
const FEET := 232.0

var frames: Array[Texture2D] = []
var main_sp: Sprite2D
var twin_sp: Sprite2D
var mats: Array = []
var mode := "pulse"
var mode_t := 0.0
var acc := 0.0
var speed := 4.0
var dir := 1.0
var shake := 0.0
var lean := 0.0
var lean_to := 0.0
var swell := 1.0
var swell_to := 1.0
var twin_t := 0.0
var twin_acc := 0.0
var twin_off := Vector2.ZERO
var t := 0.0
var allow_drag := false   # （互換のため残している）


func _ready() -> void:
	for i in 8:
		var p := "res://assets/goo_flat_%d.png" % i
		if ResourceLoader.exists(p):
			frames.append(load(p))
	main_sp = _make()
	twin_sp = _make()
	twin_sp.visible = false
	visible = false


func _make() -> Sprite2D:
	var sp := Sprite2D.new()
	sp.centered = false
	sp.offset = Vector2(-128, -FEET)
	var m := ShaderMaterial.new()
	m.shader = BLEND
	m.set_shader_parameter("fade_top", 0.92)
	m.set_shader_parameter("fade_bot", 0.96)
	sp.material = m
	mats.append(m)
	add_child(sp)
	return sp


func has_art() -> bool:
	return frames.size() == 8


func stop() -> void:
	visible = false
	twin_sp.visible = false


## intensity: 0〜1（1人／2対1／3対1）
func step(delta: float, intensity: float) -> void:
	if frames.size() < 8:
		return
	visible = true
	t += delta
	mode_t -= delta
	if mode_t <= 0.0:
		var r := randf()
		var calm := 0.35 - 0.2 * intensity
		if r < calm:
			mode = "pulse"
			mode_t = randf_range(0.6, 1.4)
			speed = randf_range(2.0, 5.0)
			shake = 0.0
			dir = 1.0
		elif r < calm + 0.3:
			mode = "thrash"
			mode_t = randf_range(0.3, 0.8)
			speed = randf_range(14.0, 24.0) * (0.8 + 0.4 * intensity)
			shake = randf_range(2.0, 4.0) * (0.6 + intensity)
			dir = 1.0
		elif r < calm + 0.5:
			mode = "writhe"
			mode_t = randf_range(0.4, 0.9)
			speed = randf_range(7.0, 12.0)
			shake = 1.0
			dir = -1.0
		elif r < calm + 0.75:
			mode = "lean"
			mode_t = randf_range(0.5, 1.0)
			speed = randf_range(5.0, 9.0)
			shake = 0.5
			lean_to = randf_range(18.0, 34.0) * (1.0 if randf() < 0.5 else -1.0)
			swell_to = randf_range(1.12, 1.28)
		else:
			mode = "twin"
			mode_t = randf_range(0.6, 1.1)
			speed = randf_range(8.0, 14.0)
			shake = 1.5
			twin_t = mode_t
			twin_off = Vector2(randf_range(46.0, 70.0) * (1.0 if randf() < 0.5 else -1.0), randf_range(-6.0, 6.0))
		if mode != "lean":
			lean_to = randf_range(-8.0, 8.0)
			swell_to = randf_range(0.95, 1.08)
		if randf() < 0.4:
			main_sp.flip_h = not main_sp.flip_h
	lean = move_toward(lean, lean_to, 60.0 * delta)
	swell = move_toward(swell, swell_to, 1.2 * delta)
	acc += speed * dir * delta
	main_sp.texture = frames[posmod(int(acc), 8)]
	main_sp.scale = Vector2(1.0 + (swell - 1.0) * 0.5, swell)
	main_sp.position = Vector2(lean + sin(t * 41.0) * shake, -absf(sin(t * 23.0)) * shake * 0.6).round()
	# 2つ目の小さな山：ぐっと盛り上がって、ぬるっと沈む
	twin_t -= delta
	twin_sp.visible = twin_t > 0.0
	if twin_sp.visible:
		twin_acc += 16.0 * delta
		var k := clampf(twin_t / 0.4, 0.0, 1.0)
		var s := 0.55 * minf(k * 2.0, 1.0)
		twin_sp.texture = frames[posmod(int(twin_acc) + 3, 8)]
		twin_sp.scale = Vector2(s, s)
		twin_sp.position = (twin_off + Vector2(sin(t * 33.0) * 1.5, 0)).round()
		mats[1].set_shader_parameter("appear", minf(k * 2.0, 1.0))
