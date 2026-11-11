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
	content = Sprite2D.new()
	content.centered = false
	bg.add_child(content)
	visible = false


func _process(delta: float) -> void:
	t += delta
	var p = main.player
	var shark = p.swallower if p.state == "swallowed" else null
	visible = shark != null and is_instance_valid(shark) and shark.view_mode == "inside" and shark.state == "drag"
	queue_redraw()
	if not visible:
		return
	# 小窓はサメの真上あたりに出す（画面の外に出ないように）
	position = Vector2(clampf(shark.position.x - W * 0.5, 10.0, 960.0 - W - 10.0), 104.0)
	# 胃袋がギュッと締まる（2対1のときは間隔が短く強い）
	var period := 1.1 if p.swallow_combo else 1.6
	var sq := pow(maxf(sin(t * TAU / period), 0.0), 3.0)
	if bg_mat:
		bg_mat.set_shader_parameter("squeeze", sq)
	var tex: Texture2D
	var mat: Material
	var feet := 0.0
	if p.swallow_combo and shark.caught_wani != null and is_instance_valid(shark.caught_wani):
		# ワニに抱え込まれたまま（抱きつきの絵を流用）
		var w = shark.caught_wani
		var f := int(t * 8.0) % 16
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
	# 等倍のまま横倒しにして（胃袋の中で寝かされている）、見せたい部分が小窓の中央に来るように置く
	content.centered = true
	content.rotation = -PI / 2.0   # 90度なのでドットは崩れない
	content.scale = Vector2(1.0 - 0.08 * sq, 1.0 + 0.10 * sq)
	content.flip_h = false
	var focus := Vector2(110.0, 140.0) if tex.get_height() > 160 else Vector2(64.0, 70.0)
	var off: Vector2 = (focus - tex.get_size() * 0.5) * content.scale
	off = off.rotated(content.rotation)
	content.position = Vector2(W * 0.5, H * 0.52) - off + Vector2(sin(t * 9.0) * 2.0, cos(t * 7.0) * 1.5)


func _draw() -> void:
	if not visible:
		return
	# 枠（ドロドロの縁取り）
	draw_rect(Rect2(-4, -4, W + 8, H + 8), Color("5a1240"), false, 4.0)
	draw_rect(Rect2(-1, -1, W + 2, H + 2), Color("ec5a9e"), false, 2.0)
