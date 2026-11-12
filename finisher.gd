extends Node2D
const GooMound = preload("res://goo_mound.gd")
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
	"crucify": {"title": "ABSORBED ON DISPLAY", "sub": "should have stayed on the ground", "frames": "none", "n": 0, "fps": 6.0, "feet": 253},
	"duo": {"title": "SPAT OUT", "sub": "the crocodile walked out. you didn't.", "frames": "fin_vomit", "n": 9, "fps": 7.0, "feet": 226},
}
const ORDER := ["hug", "shark", "wani", "crucify", "duo"]
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
var trio_dobe = null          # 3対1で負けた：サメはワニと一緒にドーベルマンも吐き出す
var dobe_sprite: Sprite2D
var dirt_mat: ShaderMaterial   # 掲げられ：主人公だけをドロドロに（猫のマスクで）
var cat_masks: Array = []
var cat_feet: Array = []      # コマごとの、ぶら下がった体の下端（糸を垂らす場所）
var goo_fx: Node2D
var wani_mat: ShaderMaterial
var pile: Sprite2D       # 2対1：吐き出されたペンキの山（ワニはこの中から形成される）
var pile_frames: Array[Texture2D] = []
var hat: Sprite2D        # サメのゲップ：主人公の帽子（本物の帽子をペンキまみれにした絵）
const HAT_PATH := [[2.0, 207, 90, -0.5], [3.0, 216, 107, 0.9], [4.0, 217, 132, 2.4], [5.0, 209, 178, 4.4], [6.0, 206, 205, 6.283]]   # [コマ, x, y, 回転]（絵の座標）
var vomited := false
var sink_frames: Array[Texture2D] = []
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
	if kind == "wani":
		_setup_dirty_cat()
	# 最初のコマのまま床から「ネバァ…」と糸を引きながらゆっくり出てくる
	rise = 1.6 if kind != "hug" else 0.0
	if kind == "duo":
		# 2対1：サメが吐き出したペンキの山から、ワニだけが余裕で形成されてくる
		for i in 9:
			wani_frames.append(load("res://assets/wani_emerge_%d.png" % i))
		for i in 9:
			wani_frames.append(load("res://assets/wani_flex_%d.png" % i))
		for i in 9:
			sink_frames.append(load("res://assets/same_sink2_%d.png" % i))
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
	dobe_sprite = Sprite2D.new()
	dobe_sprite.centered = false
	dobe_sprite.visible = false
	dobe_sprite.z_index = 1
	add_child(dobe_sprite)
	pile = Sprite2D.new()
	pile.centered = false
	pile.visible = false
	pile.z_index = 2
	add_child(pile)
	for i in 8:
		if ResourceLoader.exists("res://assets/goo_mound_%d.png" % i):
			pile_frames.append(load("res://assets/goo_mound_%d.png" % i))
	hat = Sprite2D.new()
	hat.texture = load("res://assets/fin_hat.png") if ResourceLoader.exists("res://assets/fin_hat.png") else null
	hat.visible = false
	hat.z_index = 2
	add_child(hat)
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
	if kind == "crucify":
		# 負け確定後もねちっこく続く：晒されたまま揺らされ（0〜3秒）→ 胸に半分取り込まれる（3〜6.5秒）
		# → ほぼ呑み込まれて、帽子としっぽだけ（6.5〜10秒）→ 画面
		var w = main.player.crucifier
		if tt < 0.05:
			main.zoom_moment(position + Vector2(0, -170), 10.5, false)   # 長いのでスローはかけない
		if w != null and is_instance_valid(w):
			w.set_crucify_stage(0 if tt < 3.0 else (1 if tt < 6.5 else 2))
			# 段階が進むほど、主人公がどんどん汚れていく
			if fmod(tt, 0.3) < get_process_delta_time():
				main.player.add_dirt(main.player.random_body_point(), 2 + int(tt / 3.0))
		done = tt > 10.0
		return
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
		dur += 4.2   # 吐いたあと、ワニが形成されてポーズを決めるまで
		if trio_dobe != null:
			dur += 1.6   # ドーベルマンも形成されて決めポーズまで
		_update_duo(tt)
		if tt > dur + 0.8:
			done = true
		return
	var i := clampi(int(tt * info.fps), 0, frames.size() - 1)
	sprite.visible = true
	sprite.texture = frames[i]
	sprite.offset = Vector2(-frames[i].get_width() / 2.0, -float(info.feet))
	if kind == "shark":
		_update_hat(tt * info.fps)
	if kind == "wani" and dirt_mat != null:
		sprite.material = dirt_mat
		dirt_mat.set_shader_parameter("cat_mask", cat_masks[i] if i < cat_masks.size() else null)
		goo_fx.queue_redraw()
	# 最後のコマで少し止めてから画面を出す
	if tt > dur + 0.8:
		done = true
	if kind == "duo":
		if tt > dur + 0.8:
			done = true
		return
	if tt < 0.05 and rise == 0.0:
		main.zoom_moment(position + Vector2(0, -120), dur + 0.8)


## 掲げられ：主人公の部分にだけ汚れシェーダーをかけ、体の下端を調べておく（糸を垂らす）
func _setup_dirty_cat() -> void:
	dirt_mat = ShaderMaterial.new()
	dirt_mat.shader = load("res://hug_dirt.gdshader")
	dirt_mat.set_shader_parameter("contamination", 1.0)
	dirt_mat.set_shader_parameter("absorb_y", 1.0)
	for i in frames.size():
		var mp := "res://assets/masks/%s_%d_mask.png" % [INFO[kind].frames, i]
		var mt: Texture2D = load(mp) if ResourceLoader.exists(mp) else null
		cat_masks.append(mt)
		var feet: Array = []
		if mt != null:
			var img := mt.get_image()
			if img.is_compressed():
				img.decompress()
			# 列ごとの一番下の点 → 低いものから3〜4か所（足先・しっぽ・すそ）
			var lows: Array = []
			for x in range(0, img.get_width(), 3):
				for y in range(img.get_height() - 1, 0, -1):
					if img.get_pixel(x, y).r > 0.5:
						lows.append(Vector2(x, y))
						break
			lows.sort_custom(func(a, b): return a.y > b.y)
			for p in lows:
				var far := true
				for q in feet:
					if absf(p.x - q.x) < 10.0:
						far = false
				if far:
					feet.append(p)
				if feet.size() >= 4:
					break
		cat_feet.append(feet)
	sprite.material = dirt_mat
	if cat_masks.size() > 0:
		dirt_mat.set_shader_parameter("cat_mask", cat_masks[0])
	goo_fx = Node2D.new()
	goo_fx.z_index = 3
	goo_fx.draw.connect(_draw_goo_fx)
	add_child(goo_fx)


## 掲げられ：ぶら下がった体からしずくが落ちる（床までの太い糸は不自然なので描かない）
func _draw_goo_fx() -> void:
	if kind != "wani" or not sprite.visible or cat_feet.is_empty():
		return
	var i := clampi(int((t - pre - rise) * INFO[kind].fps), 0, cat_feet.size() - 1)
	var feet: Array = cat_feet[i]
	var ox := -128.0
	var oy := -float(INFO[kind].feet)
	var tt := t
	var pink := Color("ec5a9e")
	var floor_y := -6.0
	# 体からぽたぽた落ちるしずく
	for j in 6:
		var ph := fmod(tt * 1.4 + j * 0.37, 1.0)
		if feet.is_empty():
			break
		var f: Vector2 = feet[j % feet.size()]
		var st := Vector2(ox, oy) + f + Vector2((j - 2.5) * 4.0, 0)
		var y := lerpf(st.y, floor_y, ph * ph)
		GooMound.draw_glob(goo_fx, Vector2(st.x, y), Vector2(0, 200.0 * ph + 20.0), 2.5, pink if j % 3 else Color("f9d84d"), j)


## ゲップで吐き出された帽子：口から飛び出して、くるくる回りながら床にベチャッと落ちる
func _update_hat(f: float) -> void:
	if hat.texture == null:
		return
	hat.visible = f >= 2.0
	if not hat.visible:
		return
	var a: Array = HAT_PATH[0]
	var b: Array = HAT_PATH[HAT_PATH.size() - 1]
	for i in HAT_PATH.size() - 1:
		if f >= HAT_PATH[i][0] and f < HAT_PATH[i + 1][0]:
			a = HAT_PATH[i]
			b = HAT_PATH[i + 1]
			break
	var k: float = clampf((f - a[0]) / maxf(b[0] - a[0], 0.001), 0.0, 1.0) if f < b[0] else 1.0
	var px: float = lerpf(a[1], b[1], k)
	var py: float = lerpf(a[2], b[2], k)
	hat.position = Vector2(px - 128.0, py - float(INFO[kind].feet)).round()
	hat.rotation = lerpf(a[3], b[3], k)
	if f >= 6.0 and not has_meta("hat_landed"):
		set_meta("hat_landed", true)
		main.sfx.play("step_paint", 0.0)
		main.add_goop(position + Vector2(hat.position.x, 0.0), 50.0, 0.3)


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
	# 吐き終わったら、満足げに沈んで退場（ワニの見せ場を空ける）
	if tt > vomit_end + 0.2 and sink_frames.size() == 9:
		var si := clampi(2 + int((tt - vomit_end - 0.2) * 9.0), 2, 8)
		sprite.texture = sink_frames[si]
		sprite.offset = Vector2(-128, -226)
	# 吐き出す瞬間：床も壁も一気にペンキまみれ
	if not vomited and i >= 4:
		vomited = true
		var spot := position + Vector2(67, 14)   # 吐いたペンキが落ちる場所（絵の中で測った位置）
		main.add_goop(spot, 320.0, 1.0)
		for k in 10:
			main.splat_wall(Vector2(spot.x + randf_range(-300, 300), main.FLOOR_TOP - randf_range(10, 260)), randf_range(40, 90))
			main.add_goop(spot + Vector2(randf_range(-260, 260), randf_range(-50, 50)), randf_range(60, 140), 0.7)
		main.sfx.play("assist", 3.0)
		main.sfx.play("defeat", 0.0)
	# ワニ：吐き出したペンキが落ちた水たまりそのものが、ワニの形成の1コマ目になる。
	# 吐いている間に水たまりがにじむように重なり（別の塊は出さない）、サメが沈んで残った水たまりから立ち上がる
	const RISE_W := 1.8
	var pool_t := 6.0 / float(info.fps)          # 吐いたペンキが床に届くコマ
	var hold := vomit_end + 0.7                    # サメが沈みきるまで、水たまりのまま待つ
	if tt > pool_t and wani_frames.size() == 18:
		var fi := 0
		var wt := tt - hold
		if wt > 0.0:
			if wt < RISE_W:
				fi = clampi(int(wt / RISE_W * 9.0), 0, 8)
			else:
				var ft := wt - RISE_W
				fi = 9 + (clampi(int(ft * 8.0), 0, 5) if ft < 1.2 else 5)
		wani_sprite.visible = true
		wani_sprite.texture = wani_frames[fi]
		wani_sprite.offset = Vector2(-128, -253)
		wani_sprite.position = Vector2(66, 14)
		wani_sprite.flip_h = false   # 左のサメの方を向いて余裕の顔
		# サメがいる間は、水たまりはサメの後ろ（口から流れ落ちたペンキの先に広がる）
		wani_sprite.z_index = -1 if tt < hold else 1
		if wani_mat == null:
			wani_mat = ShaderMaterial.new()
			wani_mat.shader = load("res://lean.gdshader")
			wani_mat.set_shader_parameter("lean_px", 0.0)
		wani_sprite.material = wani_mat
		wani_mat.set_shader_parameter("appear", clampf((tt - pool_t) / 0.5, 0.0, 1.0))
	_update_trio_dobe(tt, pool_t, hold)


## 3対1：吐いたペンキのもう一方の水たまりから、ドーベルマンも（少し遅れて）形成される
func _update_trio_dobe(tt: float, pool_t: float, hold: float) -> void:
	if trio_dobe == null or not is_instance_valid(trio_dobe) or tt < pool_t:
		return
	var fr: Dictionary = trio_dobe.frames
	var seq := [["rise", 0.9], ["form", 2.0], ["settle", 0.8]]
	var wt := tt - hold - 0.5
	var tex: Texture2D = null
	if wt <= 0.0:
		if fr.has("rise"):
			tex = fr["rise"][0]
	else:
		for ph in seq:
			var k: String = ph[0]
			var d: float = ph[1]
			if not fr.has(k):
				continue
			if wt < d:
				var arr: Array = fr[k]
				tex = arr[trio_dobe.timed_index(k, wt / d, arr.size())]   # ドーベルマンと同じ溜め・詰め
				break
			wt -= d
		if tex == null:
			if fr.has("idle"):
				var ia: Array = fr["idle"]
				tex = ia[int(wt * 8.0) % ia.size()]
			else:
				tex = trio_dobe.base_tex
	if tex == null:
		return
	dobe_sprite.visible = true
	dobe_sprite.texture = tex
	dobe_sprite.offset = Vector2(-128, -240)
	dobe_sprite.position = Vector2(230, 22)
	dobe_sprite.flip_h = false   # 左のサメの方を向く
	dobe_sprite.z_index = -1 if tt < hold else 2


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
