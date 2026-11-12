## Walks the whole front end the way a player would: main menu -> lobby -> READY countdown -> match ->
## match over -> summary -> Play again -> new match -> pause -> leave to the main menu.
##   godot --headless --path <project> -s scripts/flowtest.gd
extends SceneTree

var lines: Array = []
var fails := 0


func check(name: String, ok: bool, detail := "") -> void:
	lines.append(("PASS  " if ok else "FAIL  ") + name + ("   " + detail if detail != "" else ""))
	if not ok:
		fails += 1


func wait(n: int) -> void:
	for i in n:
		await process_frame


func until(cond: Callable, seconds: float) -> void:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end and not cond.call():
		await process_frame


func scene_name() -> String:
	return current_scene.scene_file_path.get_file() if current_scene else ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	change_scene_to_file("res://scenes/menu.tscn")
	await wait(10)
	check("the game opens on the main menu", scene_name() == "menu.tscn", scene_name())
	var menu = current_scene
	menu._show_lobby()
	await wait(3)
	check("Play shows the lobby", menu.lobby_box.visible)
	var st: Node = root.get_node("Settings")                      # (autoloads are not compile-time names in a SceneTree script)
	check("bot difficulty is a valid value", st.bot_difficulty in st.DIFFICULTIES, st.bot_difficulty)
	check("difficulty labels", st.difficulty_label("easy") == "Easy" and st.difficulty_label("sweaty") == "Sweaty")
	var d0: String = st.bot_difficulty                       # (the saved file may hold any value, so test relative to it)
	var want_label: String = "Bots: " + st.difficulty_label(d0)
	check("lobby Bots button shows the current difficulty", menu.bots_btn.text == want_label, menu.bots_btn.text)
	var seen: Array = []
	for i in 3:
		menu.bots_btn.pressed.emit()
		seen.append(st.bot_difficulty)
		check("Bots button label follows the setting", menu.bots_btn.text == "Bots: " + st.difficulty_label(st.bot_difficulty))
	var i0: int = st.DIFFICULTIES.find(d0)
	check("Bots button cycles Easy > Normal > Sweaty", seen == [st.DIFFICULTIES[(i0 + 1) % 3], st.DIFFICULTIES[(i0 + 2) % 3], d0], str(seen))
	menu._on_ready()
	check("Bots button is disabled after READY", menu.bots_btn.disabled and menu.back_btn.disabled)
	await wait(30)
	check("READY starts a countdown", menu.countdown > 0.0, "%.1f s left" % menu.countdown)
	await until(func(): return scene_name() == "game.tscn", 8.0)
	check("the countdown starts the match", scene_name() == "game.tscn")
	await wait(30)
	var game = current_scene
	check("the match is running", game.match_time > 0.2 and game.actors.size() == 50, "t=%.1f" % game.match_time)
	# end the match: eliminate every bot
	game.player.state = Actor.State.GROUND
	for a in game.actors:
		if a != game.player:
			a.die(game.player)
	await until(func(): return game.summary_shown, 10.0)
	check("the summary appears after the match", game.summary_shown and game.over and game.winner == game.player)
	var again: Button = null
	for b in game.find_children("*", "Button", true, false):
		if b.text == "Play again":
			again = b
	check("the summary has Play again", again != null)
	if again:
		again.pressed.emit()
		await until(func(): return current_scene != game and current_scene != null and scene_name() == "game.tscn", 8.0)
		await wait(10)
		check("Play again starts a fresh match", scene_name() == "game.tscn" and current_scene != game and current_scene.match_time < 2.0)
	game = current_scene
	await wait(10)
	if game.pause_menu and game.pause_menu.has_method("open"):
		game.pause_menu.open()
	else:
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_ESCAPE
		ev.keycode = KEY_ESCAPE
		ev.pressed = true
		root.push_input(ev)
	await wait(5)
	check("Esc pauses the match", paused)
	var t0: float = game.match_time
	await wait(20)
	check("time stands still while paused", absf(game.match_time - t0) < 0.001)
	var leave: Button = null
	for b in game.find_children("*", "Button", true, false):
		if b.text.begins_with("Leave"):
			leave = b
	if leave:
		leave.pressed.emit()
	await wait(20)
	check("Leave match returns to the main menu unpaused", scene_name() == "menu.tscn" and not paused)
	print("FLOWTEST\n" + "\n".join(lines))
	print("FLOWTEST %s  (%d checks, %d failed)" % ["OK" if fails == 0 else "FAILED", lines.size(), fails])
	quit()
