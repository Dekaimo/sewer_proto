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
	"duo": {"title": "HIGH FIVE", "sub": "teamwork makes the dream work", "frames": "fin_duo", "n": 9, "fps": 6.0, "feet": 232},
}
const ORDER := ["hug", "shark", "wani", "duo"]
const GALLERY := "user://gallery.cfg"

var main
var kind := "hug"
var t := 0.0
var pre := 0.0          # 本編の前の「地中でとどめ」の時間（duo）
var frames: Array[Texture2D] = []
var sprite: Sprite2D
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
	pre = 1.2 if kind == "duo" else 0.0
	is_new = _record()


func _ready() -> void:
	sprite = Sprite2D.new()
	sprite.centered = false
	sprite.visible = false
	add_child(sprite)
	z_index = 3000


func _process(delta: float) -> void:
	t += delta
	if t < pre:
		# 2対1：地中で最後に思いきり締め上げられる（床が激しく噴き上がる）
		if fmod(t, 0.18) < delta:
			main.add_goop(position + Vector2(randf_range(-80, 80), randf_range(-10, 10)), randf_range(80, 140), 0.6)
			main.splat_wall(Vector2(position.x + randf_range(-200, 200), main.FLOOR_TOP - randf_range(20, 180)), randf_range(40, 70))
			main.sfx.play("hit", -2.0)
		return
	var tt := t - pre
	if frames.is_empty():
		done = true
		return
	var info: Dictionary = INFO[kind]
	var dur: float = frames.size() / float(info.fps)
	var i := clampi(int(tt * info.fps), 0, frames.size() - 1)
	sprite.visible = true
	sprite.texture = frames[i]
	sprite.offset = Vector2(-frames[i].get_width() / 2.0, -float(info.feet))
	# 最後のコマで少し止めてから画面を出す
	if tt > dur + 0.8:
		done = true
	if tt < 0.05:
		main.zoom_moment(position + Vector2(0, -120), dur + 0.8)


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
