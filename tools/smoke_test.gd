extends SceneTree
## 画面なしでゲームを動かして、ドーベルマンが出てきて動いているかを記録する（CI用）。
## 主人公は3秒ごとに左右へ歩かせる。2秒ごとに敵と主人公の状態を出力。

var main
var t := 0.0
var next_log := 0.0
var dir := 1
const DURATION := 60.0

func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)

var solo := false

func _process(delta: float) -> bool:
	t += delta
	# SMOKE_SOLO=1：ワニとサメを出さず、ドーベルマンだけで待ち伏せを確かめる
	if OS.get_environment("SMOKE_SOLO") == "shark":
		# サメだけ：遊撃（回り込み→溜め→突っ込み→離脱）を確かめる
		for e in main.enemies.duplicate():
			if is_instance_valid(e):
				main.enemies.erase(e)
				e.queue_free()
		for d in main.dobes.duplicate():
			if is_instance_valid(d):
				main.dobes.erase(d)
				d.queue_free()
		main.dobe_spawn_t = 9999.0
		if main.shark_spawn_t > 1.0:
			main.shark_spawn_t = 1.0
	if OS.get_environment("SMOKE_SOLO") == "1":
		for e in main.enemies.duplicate():
			if is_instance_valid(e):
				main.enemies.erase(e)
				e.queue_free()
		if main.get("shark_spawn_t") != null:
			main.shark_spawn_t = 9999.0
		for c in main.get_children():
			if c.has_method("can_maw"):
				c.queue_free()
	var mode := OS.get_environment("SMOKE_SOLO")
	if mode == "hd" or mode == "hds":
		# ヒップドロップ確認：ワニを消し、ドーベルマンはすぐ跳ぶ。主人公は立ち止まる
		for e in main.enemies.duplicate():
			if is_instance_valid(e):
				main.enemies.erase(e)
				e.queue_free()
		if mode == "hd":
			if main.shark_spawn_t > 0.0:
				main.shark_spawn_t = 9999.0
			for c in main.get_children():
				if c.has_method("can_maw"):
					c.queue_free()
		for d in main.dobes:
			if is_instance_valid(d) and d.state != "hipdrop":
				d.hd_cd = 0.0
				d.peek_t = minf(d.peek_t, 1.0)
		Input.action_release("left"); Input.action_release("right")
		if main.player.state == "engulfed" and t > 34.0 and mode == "hd":
			main.player.touch_mash += 1
	elif int(t / 3.0) % 2 == 0:
		Input.action_release("left"); Input.action_press("right")
	else:
		Input.action_release("right"); Input.action_press("left")
	if t >= next_log:
		next_log += 0.5
		var p = main.player
		var line := "t=%.1f player=%s hp=%.0f pos=(%.0f,%.0f)" % [t, p.state, p.hp, p.position.x, p.position.y]
		var dl: Array = main.get("dobes") if main.get("dobes") != null else []
		line += " dobes=%d" % dl.size()
		for d in dl:
			if is_instance_valid(d):
				line += " [dobe %s/%s vis=%s pos=(%.0f,%.0f)]" % [d.state, d.hd_phase, str(d.sprite.visible), d.position.x, d.position.y]
		for c in main.get_children():
			if c.has_method("can_maw"):
				line += " [same %s/%s d=%.0f]" % [c.state, c.prowl, c.position.distance_to(p.position)]
		for c in main.get_children():
			if c.has_method("on_engulf_escape"):
				line += " [mound %s]" % c.state
		for e in main.enemies:
			if is_instance_valid(e):
				line += " [wani %s]" % e.state
		print(line)
	return t >= DURATION
