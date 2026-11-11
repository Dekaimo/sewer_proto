extends Node
## 効果音。res://sfx/<イベント名>/ に .ogg / .wav / .mp3 を置くと、その中からランダムに鳴る。
## ファイルが無いイベントは何も鳴らない。毎回ピッチと音量を少し揺らして単調さを消す。

const EVENTS := ["hit", "grab", "grab_loop", "assist", "step_paint", "mop", "wipe", "escape", "defeat", "gurgle"]
const VOICES := 10

var banks := {}
var players: Array[AudioStreamPlayer] = []
var next_voice := 0
var gate := {}


func _ready() -> void:
	for ev in EVENTS:
		banks[ev] = _load_dir("res://sfx/" + ev)
	for i in VOICES:
		var a := AudioStreamPlayer.new()
		add_child(a)
		players.append(a)


func _load_dir(path: String) -> Array:
	var found := {}
	var d := DirAccess.open(path)
	if d == null:
		return []
	for f in d.get_files():
		# 書き出し後はファイル名に .import / .remap が付くので外して読む
		f = f.trim_suffix(".import").trim_suffix(".remap")
		if not f.get_extension().to_lower() in ["ogg", "wav", "mp3"] or found.has(f):
			continue
		var full := path + "/" + f
		if ResourceLoader.exists(full):
			var s = load(full)
			if s is AudioStream:
				found[f] = s
	return found.values()


## min_gap：同じイベントが連続しすぎないための最短間隔（秒）
func play(ev: String, vol_db := 0.0, min_gap := 0.0) -> void:
	var bank: Array = banks.get(ev, [])
	if bank.is_empty():
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now < gate.get(ev, 0.0):
		return
	gate[ev] = now + min_gap
	var a := players[next_voice]
	next_voice = (next_voice + 1) % VOICES
	a.stream = bank.pick_random()
	a.pitch_scale = randf_range(0.88, 1.12)
	a.volume_db = vol_db + randf_range(-2.0, 1.0)
	a.play()


## 候補の中で、音が用意されている最初のイベントを鳴らす（新しい音がまだ無いときの代わり）
func play_any(evs: Array, vol_db := 0.0, min_gap := 0.0) -> void:
	for ev in evs:
		if not (banks.get(ev, []) as Array).is_empty():
			play(ev, vol_db, min_gap)
			return
