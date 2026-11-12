extends Node2D
## HUD（960x540 基準）。拡大せずにそのまま描くので文字がにじまない。

var main
const FS := 20      # 文字の大きさ
const FS_SMALL := 14


var show_t := 0.0     # 抵抗ゲージの見え具合（もがくと 1、止めると消えていく）
var last_val := 0.0


func _process(delta: float) -> void:
	show_t = maxf(show_t - delta * 1.1, 0.0)
	queue_redraw()


func _txt(pos: Vector2, s: String, col := Color.WHITE, size := FS) -> void:
	# 影をつけて読みやすく
	draw_string(ThemeDB.fallback_font, pos + Vector2(2, 2), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, 0.6))
	draw_string(ThemeDB.fallback_font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _draw() -> void:
	var p = main.player
	var c: float = p.contamination()
	_txt(Vector2(18, 30), "HP %d" % int(ceil(p.hp)))
	draw_rect(Rect2(18, 38, 240, 10), Color("3a3a3a"))
	draw_rect(Rect2(18, 38, 240 * p.hp / p.HP_MAX, 10), Color("7fd17a"))
	_txt(Vector2(18, 76), "PAINT %d%%" % int(c * 100))
	draw_rect(Rect2(18, 84, 240, 8), Color("3a3a3a"))
	draw_rect(Rect2(18, 84, 240 * c, 8), Color("ec5a9e"))
	_txt(Vector2(800, 30), "TIME %.1f" % main.survive_time)
	if not DisplayServer.is_touchscreen_available() and main.survive_time < 8.0:
		_txt(Vector2(12, 532), "KB: WASD move   Space jump   Z attack   X wipe      Mouse: L attack / L hold walk / R wipe / Wheel jump", Color("aab3ba"), FS_SMALL)

	if p.state == "swallowed":
		# 地中：画面全体がドロドロに沈む
		draw_rect(Rect2(0, 0, 960, 540), Color(0.45, 0.05, 0.28, 0.22))
	# 拘束中のゲージ：文字は出さない。もがいた（ゲージが増えた）ときだけ、足元にうっすら出て、手を止めると消える
	var restrained: bool = p.state in ["grabbed", "swallowed", "crucified", "held", "pinned"]
	if restrained:
		var sandwiched: bool = p.state == "crucified" and p.sandwicher != null and is_instance_valid(p.sandwicher)
		var val: float = clampf(p.push if sandwiched else p.struggle, 0.0, 1.0)
		if val > last_val + 0.001:
			show_t = 1.0
		last_val = val
		if show_t > 0.0:
			var sp: Vector2 = main.get_viewport().get_canvas_transform() * p.position
			var bx := clampf(sp.x - 36.0, 8.0, 960.0 - 80.0)
			var by := clampf(sp.y + 14.0, 8.0, 540.0 - 12.0)
			var a := 0.6 * minf(show_t * 1.5, 1.0)
			draw_rect(Rect2(bx - 1, by - 1, 74, 6), Color(0.05, 0.02, 0.06, a * 0.7))
			draw_rect(Rect2(bx, by, 72 * val, 4), Color(1.0, 0.8, 0.92, a) if sandwiched else Color(0.88, 0.96, 1.0, a))
	else:
		last_val = 0.0
		show_t = 0.0

	if main.game_over and main.finisher_done():
		draw_rect(Rect2(0, 0, 960, 540), Color(0, 0, 0, 0.45))
		var f = main.finisher
		# 演出が左寄りのときは文字を右側に
		var ox := 380.0 if (f != null and f.position.x < 480.0) else 0.0
		draw_set_transform(Vector2(ox, 0), 0.0, Vector2.ONE)
		var title := "OVERWHELMED..."
		var sub := ""
		if f != null:
			title = f.INFO[f.kind].title
			sub = f.INFO[f.kind].sub
		_txt(Vector2(300 - title.length() * 10, 200), title, Color("ec5a9e"), 36)
		if sub != "":
			_txt(Vector2(300 - sub.length() * 5, 236), sub, Color("f4b6d4"), 18)
		if f != null and f.is_new:
			_txt(Vector2(300 + title.length() * 10 + 10, 190), "NEW!", Color("f9d84d"), 22)
		_txt(Vector2(220, 290), "Lasted %.1f sec" % main.survive_time)
		_txt(Vector2(200, 320), "Defeats collected  %d / %d" % [f.collected() if f else 0, f.ORDER.size() if f else 4], Color("aab3ba"))
		_txt(Vector2(225, 360), "R : try again", Color("aab3ba"))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
