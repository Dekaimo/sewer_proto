extends Node2D
## 地中の様子を見せる小窓（サメの体内の断面）。
## 1人で呑まれたとき：主人公がドロドロの胃袋の中でもがく。
## ワニごと呑まれたとき：狭い胃袋の中で、ワニに抱え込まれたまま壁に押し潰される。
## 主人公の汚れは、本体と同じマテリアル（汚れマスク）を使うので、そのまま反映される。

const BELLY_SHADER = preload("res://belly.gdshader")
const W := 280.0
const H := 180.0
const BELLY_TEX := "res://assets/same_belly.png"   # 生成した背景があれば使う

var main
var bg: CanvasItem
var bg_mat: ShaderMaterial
var content: Sprite2D
var dobe_layer: Sprite2D   # 3対1：下から抱きつくドーベルマン（素材 dobe_belly_* があれば）
var goo_fg: Node2D     # 中身の手前にかぶさるネバネバ（糸・垂れ・底に溜まる粘液）
var sq_now := 0.0
var flash := 0.0
var limp := false
var sink := 0.0
var t := 0.0


func _ready() -> void:
	if ResourceLoader.exists(BELLY_TEX):
		var s := Sprite2D.new()
		s.texture = load(BELLY_TEX)
		s.centered = false
		s.scale = Vector2(W / s.texture.get_width(), H / s.texture.get_height())
		bg = s
	else:
		var r := ColorRect.new()
		r.size = Vector2(W, H)
		bg_mat = ShaderMaterial.new()
		bg_mat.shader = BELLY_SHADER
		bg_mat.set_shader_parameter("size", Vector2(W, H))
		r.material = bg_mat
		bg = r
	add_child(bg)
	# 中身は小窓の外にはみ出さないように切り抜く
	bg.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	dobe_layer = Sprite2D.new()
	dobe_layer.centered = true
	dobe_layer.visible = false
	bg.add_child(dobe_layer)
	content = Sprite2D.new()
	content.centered = false
	bg.add_child(content)
	goo_fg = Node2D.new()
	goo_fg.draw.connect(_draw_goo)
	bg.add_child(goo_fg)
	visible = false


func _process(delta: float) -> void:
	t += delta
	var p = main.player
	var shark = p.swallower if p.state == "swallowed" else null
	# 2対1のとどめ演出中は、見せ方に関係なく小窓を出す
	var fin: Dictionary = main.finisher.inset_state() if main.finisher != null else {"active": false}
	if fin.active:
		shark = p.swallower
	visible = shark != null and is_instance_valid(shark) and (fin.active or (shark.view_mode == "inside" and shark.is_dragging()))
	queue_redraw()
	if not visible:
		return
	# 小窓はサメの真上あたりに出す（画面の外に出ないように）
	position = Vector2(clampf(shark.position.x - W * 0.5, 10.0, 960.0 - W - 10.0), 104.0)
	# 胃袋がギュッと締まる（2対1のときは間隔が短く強い）
	var period := 1.1 if p.swallow_combo else 1.6
	var sq := pow(maxf(sin(t * TAU / period), 0.0), 3.0)
	var shake := 2.0
	flash = 0.0
	limp = false
	sink = 0.0
	if fin.active:
		sq = fin.sq
		shake = fin.shake
		flash = fin.flash
		limp = fin.limp
		sink = fin.get("sink", 0.0)
	sq_now = sq
	goo_fg.queue_redraw()
	if bg_mat:
		bg_mat.set_shader_parameter("squeeze", sq)
	var tex: Texture2D
	var mat: Material
	var feet := 0.0
	var holder = null
	if shark.has_method("get_swallowed"):
		holder = shark   # ワニに地中へ引きずり込まれている
	elif (p.swallow_combo or fin.active) and shark.caught_wani != null and is_instance_valid(shark.caught_wani):
		holder = shark.caught_wani   # サメの中で、ワニに抱え込まれたまま
	if holder != null:
		# 抱きつきの絵を流用
		var w = holder
		var f := int(t * 8.0) % 16
		if limp:
			f = 8   # ぐったりして動かない
		tex = w.anims["hug"][f if f < 9 else 16 - f]
		w.hug_mat.set_shader_parameter("cat_mask", w.anim_masks["hug"][f if f < 9 else 16 - f])
		w.hug_mat.set_shader_parameter("contamination", p.contamination())
		mat = w.hug_mat
		feet = 232.0
	else:
		# 1人：もがいている（被弾・掴まれのコマを使い回して小刻みに揺らす）
		tex = p.FRAMES[1 + int(t * 6.0) % 3]
		mat = p.sprite.material
		feet = 119.0
	content.texture = tex
	content.material = mat
	# 横倒しにして2倍でアップにする（2倍ならドットは崩れない）。
	# 見せるのは主人公と、それを抱え込む腕・胸だけ＝ワニの溶けた下半身は映さない
	# 小窓より大きめに切り出して、端は小窓の枠で切る（沈むときに切り口が見えないように）
	var crop := Rect2(24, 0, 150, 205) if tex.get_height() > 160 else Rect2(10, 0, 108, 128)
	content.centered = true
	content.region_enabled = true
	content.region_rect = crop
	content.rotation = -PI / 2.0   # 90度なのでドットは崩れない
	content.scale = Vector2(2.0 * (1.0 - 0.05 * sq), 2.0 * (1.0 + 0.06 * sq))
	content.modulate = Color(0.7, 0.6, 0.65) if limp else Color.WHITE
	content.flip_h = false
	content.position = Vector2(W * 0.5, H * 0.5 + sink * 50.0) + Vector2(sin(t * 37.0) * shake, cos(t * 29.0) * shake * 0.7).round()
	# ドーベルマンも中にいる：主人公の下側（小窓では右＝足側の下）から抱きついて、ぐりぐり押し上げる
	var dobe = shark.get("caught_dobe")
	dobe_layer.visible = dobe != null and is_instance_valid(dobe) and dobe.frames.has("belly")
	if dobe_layer.visible:
		var arr: Array = dobe.frames["belly"]
		dobe_layer.texture = arr[int(t * 8.0) % arr.size()]
		dobe_layer.scale = Vector2(2.0, 2.0)
		dobe_layer.position = Vector2(W * 0.5, H * 0.5 + 30.0 + sq * 6.0 + sink * 50.0).round()
		dobe_layer.modulate = content.modulate


## 手前にかぶさるネバネバ。締まるほど糸が太く、底の粘液がせり上がる
func _draw_goo() -> void:
	var dark := Color("5a1240")
	var pink := Color("ec5a9e")
	var light := Color("f489bd")
	var shine := Color("ffd6ea")
	var yel := Color("f9d84d")
	# 上下に引っ張られて伸びる太い糸（真ん中が細くなって揺れる）
	for k in 3:
		# 主人公が隠れないよう、糸は左右寄りに
		var x0: float = [26.0, 250.0, 70.0][k] + sin(t * 1.3 + k) * 8.0
		var thick := 7.0 + 5.0 * sq_now
		for y in range(0, int(H), 3):
			var fy := float(y) / H
			var w := thick * (0.35 + 0.65 * absf(fy - 0.5) * 2.0)
			var x := x0 + sin(t * 2.0 + fy * 5.0 + k) * 6.0 * (1.0 - absf(fy - 0.5) * 2.0)
			goo_fg.draw_rect(Rect2(roundf(x - w * 0.5) - 1, y, roundf(w) + 2, 3), dark)
			goo_fg.draw_rect(Rect2(roundf(x - w * 0.5), y, roundf(w), 3), pink if k % 3 else light)
		goo_fg.draw_rect(Rect2(roundf(x0 - 1), 20 + k * 13, 2, 6), shine)
	# 天井から垂れてくるしずく
	for k in 4:
		var ph := fmod(t * 0.6 + k * 0.37, 1.0)
		var dx: float = [12.0, 96.0, 200.0, 268.0][k]
		var ln := 10.0 + ph * 60.0
		goo_fg.draw_rect(Rect2(dx - 3, 0, 6, ln), dark)
		goo_fg.draw_rect(Rect2(dx - 2, 0, 4, ln), pink)
		goo_fg.draw_circle(Vector2(dx, ln), 5.0, dark)
		goo_fg.draw_circle(Vector2(dx, ln), 4.0, yel if k % 3 == 0 else pink)
	# 底に溜まって中身を呑み込むようにせり上がる粘液
	var level := H - 26.0 - 18.0 * minf(sq_now, 1.0) - sink * 110.0   # ぐったりすると粘液に沈んでいく
	var pts := PackedVector2Array()
	for x in range(0, int(W) + 8, 8):
		pts.append(Vector2(x, level + sin(t * 3.0 + x * 0.07) * 5.0))
	pts.append(Vector2(W, H))
	pts.append(Vector2(0, H))
	goo_fg.draw_colored_polygon(pts, dark)
	var pts2 := PackedVector2Array()
	for x in range(0, int(W) + 8, 8):
		pts2.append(Vector2(x, level + 3 + sin(t * 3.0 + x * 0.07) * 5.0))
	pts2.append(Vector2(W, H))
	pts2.append(Vector2(0, H))
	goo_fg.draw_colored_polygon(pts2, pink)
	for x in range(10, int(W), 37):
		goo_fg.draw_rect(Rect2(x, level + 8 + sin(t * 3.0 + x * 0.07) * 5.0, 10, 2), shine)
		goo_fg.draw_line(Vector2(x + 14, level + 16), Vector2(x + 26, level + 12), yel, 2.0)
	# とどめの瞬間：白く光る
	if flash > 0.0:
		goo_fg.draw_rect(Rect2(0, 0, W, H), Color(1, 1, 1, flash * 0.85))
	# 弾ける泡
	for k in 6:
		var ph2 := fmod(t * 1.4 + k * 0.29, 1.0)
		var bx := fmod(k * 53.0 + t * 7.0, W)
		var by := level - ph2 * 40.0
		goo_fg.draw_circle(Vector2(bx, by), 3.0 + 5.0 * ph2, dark)
		goo_fg.draw_circle(Vector2(bx, by), 2.0 + 5.0 * ph2, pink)


func _draw() -> void:
	if not visible:
		return
	# 枠（ドロドロの縁取り）
	draw_rect(Rect2(-4, -4, W + 8, H + 8), Color("5a1240"), false, 4.0)
	draw_rect(Rect2(-1, -1, W + 2, H + 2), Color("ec5a9e"), false, 2.0)
