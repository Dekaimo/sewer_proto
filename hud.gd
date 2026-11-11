extends Node2D

var main


func _ready() -> void:
	scale = Vector2(3, 3)   # 320x180 基準で描いて3倍表示


func _process(_delta: float) -> void:
	queue_redraw()


func _txt(pos: Vector2, s: String, col := Color.WHITE, size := 8) -> void:
	draw_string(ThemeDB.fallback_font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _draw() -> void:
	var p = main.player
	var c: float = p.contamination()
	_txt(Vector2(6, 9), "HP %d" % int(ceil(p.hp)))
	draw_rect(Rect2(6, 11, 80, 4), Color("3a3a3a"))
	draw_rect(Rect2(6, 11, 80 * p.hp / p.HP_MAX, 4), Color("7fd17a"))
	_txt(Vector2(6, 24), "PAINT %d%%" % int(c * 100))
	draw_rect(Rect2(6, 26, 80, 3), Color("3a3a3a"))
	draw_rect(Rect2(6, 26, 80 * c, 3), Color("ec5a9e"))
	_txt(Vector2(230, 10), "TIME %.1f" % main.survive_time)
	_txt(Vector2(4, 177), "KB: AD move / Space jump / Z attack / X wipe    Mouse: L attack, L hold walk, R wipe, Wheel jump", Color("8a949c"), 5)

	if p.state == "grabbed":
		var pos: Vector2 = p.position / 3.0 + Vector2(-16, -48)
		_txt(pos + Vector2(-12, -3), "<- -> / SHAKE!", Color("f9d84d"))
		draw_rect(Rect2(pos.x, pos.y, 32, 3), Color("3a3a3a"))
		draw_rect(Rect2(pos.x, pos.y, 32 * p.struggle, 3), Color("bfefff"))

	if main.game_over:
		draw_rect(Rect2(0, 0, 320, 180), Color(0, 0, 0, 0.55))
		_txt(Vector2(108, 80), "OVERWHELMED...", Color("ec5a9e"))
		_txt(Vector2(118, 94), "Lasted %.1f sec" % main.survive_time)
		_txt(Vector2(120, 108), "R : try again", Color("8a949c"))
