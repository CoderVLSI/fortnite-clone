## --summarytest=<dir>: scripted front-end check. Captures the pause menu, then eliminates the bots so the player wins,
## lets the Victory banner and the summary panel appear, captures them and quits.
extends Node

var game: Node
var dir := ""


func setup(g: Node, d: String) -> void:
	game = g
	dir = d
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(dir)
	_run()


func _save(nm: String) -> void:
	get_viewport().get_texture().get_image().save_png(dir.path_join(nm + ".png"))
	print("SHOT ", nm)


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout


func _run() -> void:
	await _wait(1.0)
	var t0: float = game.match_time
	game.pause_menu.open()
	await _wait(0.5)
	var paused_ok: bool = get_tree().paused and absf(game.match_time - t0) < 0.05
	_save("menu_pause")
	game.pause_menu.resume()
	await _wait(0.3)
	print("SUMMARYTEST pause: paused_and_frozen=%s resumed=%s" % [paused_ok, not get_tree().paused])
	# the player lands some hits, then every bot is eliminated
	var n := 0
	for a in game.actors:
		if a != game.player:
			if n < 4:
				game.on_damage_dealt(game.player, a, 35.0, a.global_position)    # (shots report damage like this)
			n += 1
	for a in game.actors:
		if a != game.player and a.alive():
			a.die(game.player)
	await _wait(1.5)
	_save("menu_victory_banner")
	for i in 200:                                                    # match time may run slower than real time on a software renderer
		if game.summary_shown:
			break
		await _wait(0.1)
	await _wait(0.5)
	_save("menu_summary")
	print("SUMMARYTEST summary_shown=%s place=%d kills=%d damage=%d" % [game.summary_shown, game.player.placement, game.player.kills, int(game.player_damage)])
	get_tree().quit()
