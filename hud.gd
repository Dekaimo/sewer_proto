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
	_txt(Vector2(12, 532), "KB: A/D move   Space jump   Z attack   X wipe      Mouse: L attack / L hold walk / R wipe / Wheel jump", Color("aab3ba"), FS_SMALL)

	if p.state == "grabbed":
		var pos: Vector2 = p.position + Vector2(-50, -150)
		_txt(pos + Vector2(-20, -8), "<- -> / SHAKE!", Color("f9d84d"))
		draw_rect(Rect2(pos.x, pos.y, 100, 8), Color("3a3a3a"))
		draw_rect(Rect2(pos.x, pos.y, 100 * p.struggle, 8), Color("bfefff"))

	if main.game_over:
		draw_rect(Rect2(0, 0, 960, 540), Color(0, 0, 0, 0.45))
		_txt(Vector2(370, 230), "OVERWHELMED...", Color("ec5a9e"), 32)
		_txt(Vector2(395, 270), "Lasted %.1f sec" % main.survive_time)
		_txt(Vector2(405, 305), "R : try again", Color("aab3ba"))
