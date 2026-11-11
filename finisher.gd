extends Node2D
## フィニッシュ演出。力尽きたとき、相手ごとの専用の見せ場を流してからゲームオーバー画面を出す。
## 見た負け方は user://gallery.cfg に記録する（図鑑・回想モード用）。
##
## 種類:
##   hug   … 地上でワニに抱えられたまま水たまりに沈められる
##   shark … サメの腹の中で力尽きる → 床から顔を出してゲップ、帽子だけペッと吐き出す
##   wani  … ワニに地中へ引きずり込まれて力尽きる → 床から腕を出し、ドロドロの主人公を見せびらかす
##   duo   … サメの腹の中でワニと2対1 → 地中でとどめ → 2体そろって出てきてハイタッチ

const INFO := {
	"hug": {"title": "SUNK IN THE PUDDLE", "sub": "hugged down into the paint", "frames": "wani_swallow", "n": 9, "fps": 7.0, "feet": 253},
	"shark": {"title": "BURPED OUT", "sub": "only the hat came back", "frames": "fin_shark", "n": 9, "fps": 6.0, "feet": 226},
	"wani": {"title": "SHOWN OFF", "sub": "held up like a trophy", "frames": "fin_wani", "n": 9, "fps": 6.0, "feet": 232},
	"duo": {"title": "SPAT OUT", "sub": "the crocodile walked out. you didn't.", "frames": "fin_vomit", "n": 9, "fps": 7.0, "feet": 226},
}
const ORDER := ["hug", "shark", "wani", "duo"]
const GALLERY := "user://gallery.cfg"

var main
var kind := "hug"
var t := 0.0
var pre := 0.0          # 本編の前の「地中でとどめ」の時間（duo）
var frames: Array[Texture2D] = []
var sprite: Sprite2D
var strands: Node2D       # 床から体へ伸びる糸（手前に描く）
var rise := 0.0           # 床からゆっくり出てくる時間
var rise_k := 1.0         # 0=まだ床の中 1=全身が出た
var wani_frames: Array[Texture2D] = []   # 2対1：吐き出されたペンキから出てくるワニ（形成→マッスルポーズ）
var wani_sprite: Sprite2D
var vomited := false
var done := false
var is_new := false


func setup(k: String, at: Vector2) -> void:
	kind = k
	position = at
	var info: Dictionary = INFO[kind]
	for i in info.n:
		var p := "res://assets/%s_%d.png" % [info.frames, i]
		if ResourceLoader.exists(p):
			frames.append(load(p))
	# 予備：アニメが無いときは1枚絵（キーフレーム）
	if frames.is_empty() and ResourceLoader.exists("res://assets/%s_key.png" % info.frames):
		frames.append(load("res://assets/%s_key.png" % info.frames))
	pre = 2.4 if kind == "duo" else 0.0
	# 最初のコマのまま床から「ネバァ…」と糸を引きながらゆっくり出てくる
	rise = 1.6 if kind != "hug" else 0.0
	if kind == "duo":
		# 2対1：サメが吐き出したペンキの山から、ワニだけが余裕で形成されてくる
		for i in 9:
			wani_frames.append(load("res://assets/wani_emerge_%d.png" % i))
		for i in 9:
			wani_frames.append(load("res://assets/wani_flex_%d.png" % i))
	is_new = _record()


func _ready() -> void:
	sprite = Sprite2D.new()
	sprite.centered = false
	sprite.visible = false
	add_child(sprite)
	wani_sprite = Sprite2D.new()
	wani_sprite.centered = false
	wani_sprite.visible = false
	wani_sprite.z_index = 1
	add_child(wani_sprite)
	strands = Node2D.new()
	strands.draw.connect(_draw_strands)
	add_child(strands)
	z_index = 3000


func _process(delta: float) -> void:
	t += delta
	if t < pre:
		# 2対1のとどめ：地中（小窓）で、ワニに抱え込まれたままサメの胃袋がドンッと閉じて押し潰す
		if t > 1.4 and t - delta <= 1.4:
			main.sfx.play("assist", 2.0)
			main.sfx.play("defeat", 0.0)
		if t > 1.4 and fmod(t, 0.18) < delta:
			main.add_goop(position + Vector2(randf_range(-80, 80), randf_range(-10, 10)), randf_range(80, 140), 0.6)
			main.splat_wall(Vector2(position.x + randf_range(-200, 200), main.FLOOR_TOP - randf_range(20, 180)), randf_range(40, 70))
			main.sfx.play("hit", -2.0)
		return
	var tt := t - pre
	if frames.is_empty():
		done = true
		return
	var info: Dictionary = INFO[kind]
	strands.queue_redraw()
	if tt < rise:
		# 床から少しずつせり上がる（絵の上から見えている分だけ切り出す）
		rise_k = ease(tt / rise, 0.6)
		var full: float = info.feet
		var vh: float = maxf(full * rise_k, 1.0)
		sprite.visible = true
		sprite.texture = frames[0]
		sprite.region_enabled = true
		sprite.region_rect = Rect2(0, 0, frames[0].get_width(), vh)
		sprite.offset = Vector2(-frames[0].get_width() / 2.0, -vh)
		sprite.position = Vector2(sin(tt * 9.0) * 1.5, 0).round()
		if tt < delta * 1.5:
			var extra := 2.8 if kind == "duo" else 0.0
			main.zoom_moment(position + Vector2(75.0 if kind == "duo" else 0.0, -120), rise + frames.size() / float(info.fps) + extra + 0.8)
			main.sfx.play("gurgle", 0.0)
		if fmod(tt, 0.4) < delta:
			main.sfx.play_any(["gurgle", "grab_loop"], -2.0)
		return
	rise_k = 1.0
	sprite.region_enabled = false
	sprite.position = Vector2.ZERO
	tt -= rise
	var dur: float = frames.size() / float(info.fps)
	if kind == "duo":
		dur += 2.8   # 吐いたあと、ワニが形成されてポーズを決めるまで
		_update_duo(tt)
	var i := clampi(int(tt * info.fps), 0, frames.size() - 1)
	sprite.visible = true
	sprite.texture = frames[i]
	sprite.offset = Vector2(-frames[i].get_width() / 2.0, -float(info.feet))
	# 最後のコマで少し止めてから画面を出す
	if tt > dur + 0.8:
		done = true
	if kind == "duo":
		if tt > dur + 0.8:
			done = true
		return
	if tt < 0.05 and rise == 0.0:
		main.zoom_moment(position + Vector2(0, -120), dur + 0.8)


## 出てくる途中：床と体のあいだに、太い糸が何本も引っ張られて伸びる（伸びきると細くなってちぎれる）
func _draw_strands() -> void:
	if not sprite.visible or kind == "hug":
		return
	var tt := t - pre
	var k := rise_k if tt < rise else clampf(1.0 - (tt - rise) / 0.7, 0.0, 1.0)
	if k <= 0.0:
		return
	var dark := Color("5a1240")
	var pink := Color("ec5a9e")
	var light := Color("f489bd")
	# 足元の水たまりの縁
	draw_set_transform(Vector2(0, 2), 0.0, Vector2(1.0, 0.26))
	draw_circle(Vector2.ZERO, 110.0, dark)
	draw_circle(Vector2.ZERO, 104.0, pink)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var info: Dictionary = INFO[kind]
	var top: float = -minf(info.feet * rise_k, 120.0)   # 糸がくっついている高さ
	for i in 7:
		var x := (i - 3) * 26.0 + sin(i * 1.7) * 8.0
		var h := top * (0.35 + 0.65 * fmod(i * 0.37, 1.0))
		if tt >= rise and i % 2 == 0 and tt - rise > 0.25:
			continue   # 出きったら半分の糸からちぎれていく
		var thick := (6.0 + 3.0 * (i % 3)) * k
		var n := 10
		for j in n:
			var a := float(j) / n
			var b := float(j + 1) / n
			# 真ん中ほど細い（引っ張られて伸びている）
			var w := thick * (0.3 + 0.7 * absf(a - 0.5) * 2.0)
			var sway := sin(t * 3.0 + i) * 4.0 * (1.0 - absf(a - 0.5) * 2.0)
			var y0 := h * a
			var y1 := h * b
			draw_rect(Rect2(roundf(x + sway - w * 0.5) - 1, roundf(y1), roundf(w) + 2, roundf(y0 - y1) + 1), dark)
			draw_rect(Rect2(roundf(x + sway - w * 0.5), roundf(y1), roundf(w), roundf(y0 - y1) + 1), light if j % 4 == 1 else pink)
		draw_circle(Vector2(x, 0), thick * 0.9 + 2.0, dark)
		draw_circle(Vector2(x, 0), thick * 0.9, pink)


## 2対1の締め：サメがゲロのようにペンキを吐き出し、その山からワニだけが余裕で形成されてポーズ
func _update_duo(tt: float) -> void:
	var info: Dictionary = INFO["duo"]
	var vomit_end: float = frames.size() / float(info.fps)
	var i := clampi(int(tt * info.fps), 0, frames.size() - 1)
	sprite.visible = true
	sprite.texture = frames[i]
	sprite.offset = Vector2(-frames[i].get_width() / 2.0, -float(info.feet))
	# 吐き出す瞬間：床も壁も一気にペンキまみれ
	if not vomited and i >= 4:
		vomited = true
		var spot := position + Vector2(190, 10)
		main.add_goop(spot, 320.0, 1.0)
		for k in 10:
			main.splat_wall(Vector2(spot.x + randf_range(-300, 300), main.FLOOR_TOP - randf_range(10, 260)), randf_range(40, 90))
			main.add_goop(spot + Vector2(randf_range(-260, 260), randf_range(-50, 50)), randf_range(60, 140), 0.7)
		main.sfx.play("assist", 3.0)
		main.sfx.play("defeat", 0.0)
	# ワニ：吐き出された山（サメの口の先）から形成 → マッスルポーズで止める
	var wt := tt - vomit_end + 0.3
	if wt > 0.0 and wani_frames.size() == 18:
		var fi := 0
		if wt < 0.9:
			fi = clampi(int(wt * 10.0), 0, 8)
		else:
			var ft := wt - 0.9
			fi = 9 + (clampi(int(ft * 8.0), 0, 5) if ft < 1.2 else 5)
		wani_sprite.visible = true
		wani_sprite.texture = wani_frames[fi]
		wani_sprite.offset = Vector2(-128, -253)
		wani_sprite.position = Vector2(230, 14)
		wani_sprite.flip_h = true   # サメの方を向いて余裕の顔


## とどめの間の小窓の様子（belly_view が読む）
## active: 小窓を出すか / sq: 締まり具合 / shake: 揺れ / flash: 白く光る / limp: ぐったり（動かない）
func inset_state() -> Dictionary:
	if kind != "duo" or t >= pre:
		return {"active": false}
	if t < 1.4:
		# じわじわ締まっていく。主人公は必死にもがく
		var k := t / 1.4
		return {"active": true, "sq": 0.3 + 0.5 * k + 0.2 * sin(t * 14.0), "shake": 2.0 + 3.0 * k, "flash": 0.0, "limp": false}
	if t < 1.75:
		# ドンッ：一気に閉じて押し潰す
		return {"active": true, "sq": 1.6, "shake": 9.0, "flash": 1.0 - (t - 1.4) / 0.35, "limp": false}
	# ぐったりして、粘液に沈んでいく
	return {"active": true, "sq": 1.2, "shake": 0.0, "flash": 0.0, "limp": true, "sink": (t - 1.75) / (pre - 1.75)}


## 図鑑に記録。初めて見た負け方なら true
func _record() -> bool:
	var cfg := ConfigFile.new()
	cfg.load(GALLERY)
	var seen: bool = cfg.get_value("seen", kind, false)
	cfg.set_value("seen", kind, true)
	cfg.set_value("count", kind, int(cfg.get_value("count", kind, 0)) + 1)
	cfg.save(GALLERY)
	return not seen


static func collected() -> int:
	var cfg := ConfigFile.new()
	cfg.load(GALLERY)
	var n := 0
	for k in ORDER:
		if cfg.get_value("seen", k, false):
			n += 1
	return n
