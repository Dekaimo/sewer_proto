extends Node2D
## ヒップドロップで取り込まれた主人公が、ドーベルマンからひり出された粘液のとぐろの中に閉じ込められている。
## 中でもがくと、とぐろがネチャネチャ蠢く。抵抗が溜まると破裂して脱出（転んだ状態で出てくる）。
## もがいている間にサメが来れば、とぐろごと丸呑みにされて地中へ。

const FEET_Y := 240
var main
var sprite: Sprite2D
var frames := {}
var state := "idle"     # idle / burst
var t := 0.0
var wiggle := 0.0       # 中でもがいた直後ほど大きく蠢く


func _ready() -> void:
	sprite = Sprite2D.new()
	sprite.centered = false
	sprite.offset = Vector2(-128, -FEET_Y)
	add_child(sprite)
	for k in ["idle", "wiggle", "burst"]:
		var arr: Array[Texture2D] = []
		var i := 0
		while ResourceLoader.exists("res://assets/mound_%s_%d.png" % [k, i]):
			arr.append(load("res://assets/mound_%s_%d.png" % [k, i]))
			i += 1
		frames[k] = arr
	sprite.texture = frames["idle"][0]


## 主人公が中でもがいた
func on_struggle() -> void:
	wiggle = 1.0
	main.sfx.play("grab_loop", -8.0, 0.2)


## 抵抗が溜まって中から破裂する
func on_engulf_escape() -> void:
	state = "burst"
	t = 0.0
	main.add_goop(position, 140.0, 0.6)
	for i in 3:
		main.splat_wall(Vector2(position.x + randf_range(-140.0, 140.0), main.FLOOR_TOP - randf_range(20.0, 140.0)), randf_range(30.0, 55.0))
	main.sfx.play("escape")


func _process(delta: float) -> void:
	t += delta
	z_index = int(position.y)
	var p = main.player
	if state == "burst":
		var b: Array = frames["burst"]
		var k := int(t / 0.11)
		if k >= b.size():
			queue_free()
			return
		sprite.texture = b[k]
		return
	# 主人公がもう中にいない（サメに呑まれた等）→ とぐろも一緒に消える
	if p.engulfer != self or not (p.state == "engulfed" or p.state == "defeated"):
		queue_free()
		return
	if p.state == "defeated":
		# 力尽きた：とぐろの中で、ときおりネチャッと蠢くだけになる（終わらない）
		var wl: Array = frames["wiggle"]
		sprite.texture = wl[int(t * 4.0) % wl.size()] if fmod(t, 3.5) < 1.0 else frames["idle"][0]
		return
	wiggle = maxf(wiggle - delta * 1.6, 0.0)
	var w: Array = frames["wiggle"]
	if wiggle > 0.05 and w.size() > 0:
		sprite.texture = w[int(t * 10.0) % w.size()]
	else:
		# 何もしなくても、ときどき中で蠢く
		sprite.texture = w[int(t * 5.0) % w.size()] if fmod(t, 2.6) < 0.8 and w.size() > 0 else frames["idle"][0]
