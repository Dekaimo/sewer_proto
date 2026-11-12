extends Node2D
## 地中で暴れている様子のドット絵アニメ（手が突き出してまた引きずり込まれる・帽子の先が出て沈む・
## 体の形が下から押し上げる・腕に絡め取られる・大きな泡が弾ける）を、床の盛り上がりの上に重ねる。
## 毎回同じにならないように：パターン・位置・向き・速さをランダムに選び、途中で沈み返すこともある。
## 線はくっきりさせず、下は床のペンキに溶け込ませる（under_blend.gdshader）。

const BLEND = preload("res://under_blend.gdshader")
const FEET := 232.0          # 絵の中で水たまりが床に接する行

var patterns := {}           # 名前 → コマ配列（assets/ug_<name>_0..）
var slots: Array = []        # 再生中 {sp, mat, name, f, speed, end, dir, off}
var wait := 0.3
var allow_drag := false      # ワニ（腕）に絡め取られるパターンを出すか


func _ready() -> void:
	for n in ["paw", "body", "drag", "drag2", "burst", "burst2"]:
		var arr: Array[Texture2D] = []
		var i := 0
		while ResourceLoader.exists("res://assets/ug_%s_%d.png" % [n, i]):
			arr.append(load("res://assets/ug_%s_%d.png" % [n, i]))
			i += 1
		if arr.size() > 0:
			patterns[n] = arr


func has_art() -> bool:
	return patterns.size() > 0


func stop() -> void:
	for s in slots:
		s.sp.queue_free()
	slots.clear()
	visible = false


## intensity: 0〜1（1人／2対1／3対1）
func step(delta: float, intensity: float) -> void:
	if patterns.is_empty():
		return
	visible = true
	wait -= delta
	var max_slots := 1 if intensity < 0.6 else 2
	if wait <= 0.0 and slots.size() < max_slots:
		_spawn(intensity)
		wait = randf_range(0.15, 0.9) / (0.7 + intensity)
	for s in slots:
		var arr: Array = patterns[s.name]
		s.f += delta * s.speed * s.dir
		# 途中で沈み返す：決めたところまで行ったら逆再生で戻る（＝引きずり込まれる）
		if s.dir > 0 and s.f >= s.end:
			s.dir = -1.0 if s.bounce else 1.0
			if not s.bounce:
				s.f = minf(s.f, float(arr.size()) - 0.01)
		var fi: int = clampi(int(s.f), 0, arr.size() - 1)
		s.sp.texture = arr[fi]
		# にじむように現れて、にじむように消える
		var life: float = s.f / float(arr.size())
		var ap: float = clampf(minf(life * 6.0, 1.0), 0.0, 1.0)
		if s.dir < 0:
			ap = clampf(s.f / 3.0, 0.0, 1.0)
		elif s.f > float(arr.size()) - 2.0:
			ap = clampf(float(arr.size()) - s.f, 0.0, 1.0)
		s.mat.set_shader_parameter("appear", ap)
		s.sp.position = s.off + Vector2(sin(s.f * 0.9) * 2.0, 0).round()
	slots = slots.filter(func(s):
		var done: bool = (s.dir > 0 and s.f >= float(patterns[s.name].size()) - 0.05) or (s.dir < 0 and s.f <= 0.0)
		if done:
			s.sp.queue_free()
		return not done)


func _spawn(intensity: float) -> void:
	var names: Array = []
	for n in patterns.keys():
		if n.begins_with("drag") and not allow_drag:
			continue
		# 重み：手・体が多め、帽子はたまに、泡はつなぎ
		var w: int = {"paw": 3, "body": 3, "drag": 2, "drag2": 2, "burst": 1, "burst2": 1}.get(n, 1)
		for i in w:
			names.append(n)
	# 同じパターンを同時に2つ出さない
	for s in slots:
		names = names.filter(func(x): return x != s.name)
	if names.is_empty():
		return
	var nm: String = names[randi() % names.size()]
	var arr: Array = patterns[nm]
	var sp := Sprite2D.new()
	sp.centered = false
	sp.offset = Vector2(-128, -FEET)
	sp.flip_h = randf() < 0.5
	# 絵ごとの大きさ（主人公の手や頭と釣り合うように）
	var sc: float = {"paw": 0.5, "body": 0.8, "drag": 0.62, "drag2": 0.62, "burst": 0.7, "burst2": 0.7}.get(nm, 0.7)
	sp.scale = Vector2(sc, sc)
	var mat := ShaderMaterial.new()
	mat.shader = BLEND
	sp.material = mat
	add_child(sp)
	var bounce := randf() < 0.35   # 出きる前に引き戻される
	slots.append({"sp": sp, "mat": mat, "name": nm, "f": 0.0,
		"speed": randf_range(9.0, 15.0) * (0.85 + 0.3 * intensity),
		"end": randf_range(arr.size() * 0.35, arr.size() * 0.6) if bounce else float(arr.size()),
		"bounce": bounce, "dir": 1.0,
		"off": Vector2(randf_range(-40.0, 40.0), randf_range(-6.0, 8.0)).round()})
