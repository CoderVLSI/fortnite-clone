## End-of-match summary panel, shown a few seconds after the Victory / Match over banner.
extends CanvasLayer


func setup(game: Node) -> void:
	layer = 15
	var root := Control.new()
	root.theme = MenuUI.make_theme()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(centre)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 0)
	centre.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	panel.add_child(col)
	var p: Actor = game.player
	var won: bool = game.winner == p
	col.add_child(MenuUI.label("LAST ONE STANDING" if won else "MATCH OVER", 44, MenuUI.ACCENT if won else MenuUI.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	col.add_child(MenuUI.label("#%d of %d" % [p.placement, game.actors.size()], 72, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER))
	if not won and game.winner:
		col.add_child(MenuUI.label("%s won the match" % game.winner.display_name, 20, MenuUI.DIM, HORIZONTAL_ALIGNMENT_CENTER))
	col.add_child(MenuUI.spacer(6))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 40)
	grid.add_theme_constant_override("v_separation", 8)
	col.add_child(grid)
	var secs := int(game.player_survived)
	var rows := [
		["Eliminations", str(p.kills)],
		["Damage dealt", str(int(round(game.player_damage)))],
		["Time survived", "%d:%02d" % [secs / 60, secs % 60]],
		["XP earned", "+%d" % game.xp_earned if game.xp_earned >= 0 else "-"],
	]
	if game.stats.has("harvested"):
		rows.append(["Materials harvested", str(int(game.stats["harvested"]))])
	for r in rows:
		var l := MenuUI.label(r[0], 24, MenuUI.DIM)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(l)
		grid.add_child(MenuUI.label(r[1], 28, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT))
	col.add_child(MenuUI.spacer(10))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	col.add_child(row)
	var again := MenuUI.button("Play again", 24, Vector2(240, 58))
	again.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/game.tscn"))
	row.add_child(again)
	if game.net_active:
		again.visible = false                                  # a party goes back to the lobby together
	var menu := MenuUI.button("Main menu", 24, Vector2(240, 58))
	menu.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/menu.tscn"))
	if game.net_active:
		menu.text = "Back to lobby"
	row.add_child(menu)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
