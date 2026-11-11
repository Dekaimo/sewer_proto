extends Node2D
## HUD（960x540 基準）。拡大せずにそのまま描くので文字がにじまない。

var main
const FS := 20      # 文字の大きさ
const FS_SMALL := 14


func _process(_delta: float) -> void:
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
	_txt(Vector2(12, 532), "KB: WASD move   Space jump   Z attack   X wipe      Mouse: L attack / L hold walk / R wipe / Wheel jump", Color("aab3ba"), FS_SMALL)

	if p.state == "slipped":
		_txt(p.position + Vector2(-60, -80), "SLIPPED!  <- ->", Color("f9d84d"))

	if p.state == "swallowed":
		# 地中：画面全体がドロドロに沈む
		draw_rect(Rect2(0, 0, 960, 540), Color(0.45, 0.05, 0.28, 0.22))
		var dragged: bool = p.swallower != null and p.swallower.has_method("get_swallowed")
		var label := "2 vs 1 !!   <- ->" if p.swallow_combo else ("DRAGGED UNDER!   <- ->" if dragged else "SWALLOWED!   <- ->")
		var pos2: Vector2 = Vector2(clampf(p.position.x - 70.0, 10.0, 800.0), p.position.y - 90.0)
		_txt(pos2 + Vector2(0, -12), label, Color("f9d84d"))
		draw_rect(Rect2(pos2.x, pos2.y, 120, 8), Color("3a3a3a"))
		draw_rect(Rect2(pos2.x, pos2.y, 120 * p.struggle, 8), Color("bfefff"))

	if p.state == "grabbed":
		var pos: Vector2 = p.position + Vector2(-50, -150)
		_txt(pos + Vector2(-20, -8), "<- -> / SHAKE!", Color("f9d84d"))
		draw_rect(Rect2(pos.x, pos.y, 100, 8), Color("3a3a3a"))
		draw_rect(Rect2(pos.x, pos.y, 100 * p.struggle, 8), Color("bfefff"))

	if main.game_over and main.finisher_done():
		draw_rect(Rect2(0, 0, 960, 540), Color(0, 0, 0, 0.45))
		var f = main.finisher
		var title := "OVERWHELMED..."
		var sub := ""
		if f != null:
			title = f.INFO[f.kind].title
			sub = f.INFO[f.kind].sub
		_txt(Vector2(480 - title.length() * 10, 200), title, Color("ec5a9e"), 36)
		if sub != "":
			_txt(Vector2(480 - sub.length() * 5, 236), sub, Color("f4b6d4"), 18)
		if f != null and f.is_new:
			_txt(Vector2(480 + title.length() * 10 + 10, 190), "NEW!", Color("f9d84d"), 22)
		_txt(Vector2(400, 290), "Lasted %.1f sec" % main.survive_time)
		_txt(Vector2(380, 320), "Defeats collected  %d / %d" % [f.collected() if f else 0, f.ORDER.size() if f else 4], Color("aab3ba"))
		_txt(Vector2(405, 360), "R : try again", Color("aab3ba"))
