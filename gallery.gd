extends RefCounted
## ギャラリー（やられ方の記録）。見た負け方は user://gallery.cfg に残る。
## frames は assets/ の連番（<frames>_0.png …）。ギャラリーではそのコマを繰り返し流すだけ（仮）。

const PATH := "user://gallery.cfg"
const ENTRIES := [
	{"id": "hug", "name": "みずたまりに しずめられる", "who": "ペンキワニ", "frames": "wani_swallow", "n": 9, "fps": 7.0},
	{"id": "wani", "name": "みせびらかされる", "who": "ペンキワニ", "frames": "fin_wani", "n": 9, "fps": 6.0},
	{"id": "crucify", "name": "はりつけのまま とりこまれる", "who": "ペンキワニ", "frames": "cru2/go_absorb", "n": 9, "fps": 6.0},
	{"id": "shark", "name": "ぼうしだけ はきだされる", "who": "ペンキサメ", "frames": "fin_shark", "n": 9, "fps": 6.0},
	{"id": "duo", "name": "ワニだけ でてくる", "who": "サメ と ワニ", "frames": "fin_vomit", "n": 9, "fps": 7.0},
	{"id": "hipdrop", "name": "とぐろの なかで もてあそばれる", "who": "ペンキドーベルマン", "frames": "dobe_hd_done", "n": 8, "fps": 6.0},
	{"id": "trio", "name": "はさまれて とりこまれる", "who": "ワニ と ドーベルマン", "frames": "trio_absorbed", "n": 8, "fps": 6.0},
]


## 記録する。初めて見た負け方なら true
static func record(id: String) -> bool:
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	var was: bool = cfg.get_value("seen", id, false)
	cfg.set_value("seen", id, true)
	cfg.set_value("count", id, int(cfg.get_value("count", id, 0)) + 1)
	cfg.save(PATH)
	return not was


static func load_cfg() -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	return cfg


static func collected() -> int:
	var cfg := load_cfg()
	var n := 0
	for e in ENTRIES:
		if cfg.get_value("seen", e.id, false):
			n += 1
	return n
