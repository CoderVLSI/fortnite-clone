## On-screen controls for phones and tablets: a move stick on the left, drag anywhere else to look,
## and buttons for fire, jump, reload, use and aim. Tap a hotbar box to select it and the minimap for the map.
extends Control

var game: Node
var move := Vector2.ZERO                 # x = right, y = forward
var look := Vector2.ZERO                 # accumulated drag in pixels, consumed by the player controller
var fire := false
var aim := false
var pressed_once := {}                   # button name -> true for one tick
var stick_id := -1
var stick_origin := Vector2.ZERO
var stick_pos := Vector2.ZERO
var look_ids := {}
var button_ids := {}                     # touch index -> button name
var font: Font


func setup(g: Node) -> void:
	game = g
	font = ThemeDB.fallback_font
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func buttons() -> Dictionary:
	var s := get_viewport_rect().size
	return {
		"fire": [Vector2(s.x - 150, s.y - 290), 74.0, "FIRE"],
		"jump": [Vector2(s.x - 345, s.y - 215), 56.0, "JUMP"],
		"aim": [Vector2(s.x - 300, s.y - 370), 44.0, "AIM"],
		"reload": [Vector2(s.x - 120, s.y - 450), 44.0, "RELOAD"],
		"use": [Vector2(s.x - 450, s.y - 300), 44.0, "USE"],
		"drop": [Vector2(s.x - 440, s.y - 420), 36.0, "DROP"],
		"crouch": [Vector2(s.x - 480, s.y - 165), 40.0, "CROUCH"],
		"b_wall": [Vector2(s.x - 560, s.y - 560), 34.0, "WALL"],
		"b_floor": [Vector2(s.x - 480, s.y - 560), 34.0, "FLOOR"],
		"b_stairs": [Vector2(s.x - 400, s.y - 560), 34.0, "STAIR"],
		"b_cone": [Vector2(s.x - 320, s.y - 560), 34.0, "CONE"],
		"mat": [Vector2(s.x - 240, s.y - 560), 34.0, "MAT"],
	}


func take(name: String) -> bool:
	if pressed_once.has(name):
		pressed_once.erase(name)
		return true
	return false


func _hotbar_slot(p: Vector2) -> int:
	## Matches the HUD hotbar layout. Returns -2 when the point is not on it, -1 for the pickaxe box.
	var box := 78.0
	var gap := 8.0
	var vs := get_viewport_rect().size
	var x0 := vs.x - (box + gap) * 6 - 18
	var y0 := vs.y - box - 26
	if p.y < y0 - 6 or p.y > y0 + box + 6 or p.x < x0:
		return -2
	var i := int((p.x - x0) / (box + gap))
	return clampi(i, 0, 5) - 1


func _input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		var p: Vector2 = e.position
		if e.pressed:
			for name in buttons():
				var b: Array = buttons()[name]
				if p.distance_to(b[0]) <= b[1] * 1.15:
					button_ids[e.index] = name
					if name == "fire":
						fire = true
						look_ids[e.index] = true           # the firing thumb can still steer the aim
					elif name == "aim":
						aim = not aim
					else:
						pressed_once[name] = true
					return
			var slot := _hotbar_slot(p)
			if slot > -2:
				game.player.select(slot)
				return
			if p.x > get_viewport_rect().size.x - 260 and p.y < 260:
				pressed_once["map"] = true
				return
			if p.x < get_viewport_rect().size.x * 0.42 and stick_id == -1:
				stick_id = e.index
				stick_origin = p
				stick_pos = p
			else:
				look_ids[e.index] = true
		else:
			if e.index == stick_id:
				stick_id = -1
				move = Vector2.ZERO
			if button_ids.get(e.index, "") == "fire":
				fire = false
			button_ids.erase(e.index)
			look_ids.erase(e.index)
	elif e is InputEventScreenDrag:
		if e.index == stick_id:
			stick_pos = e.position
			var d: Vector2 = (stick_pos - stick_origin) / 95.0
			if d.length() > 1.0:
				d = d.normalized()
			move = Vector2(d.x, -d.y) if d.length() > 0.15 else Vector2.ZERO
		elif look_ids.has(e.index):
			look += e.relative


func _process(_d: float) -> void:
	queue_redraw()


func _draw() -> void:
	var col := Color(1, 1, 1, 0.28)
	for name in buttons():
		var b: Array = buttons()[name]
		var on: bool = (name == "fire" and fire) or (name == "aim" and aim)
		draw_circle(b[0], b[1], Color(1.0, 0.8, 0.3, 0.4) if on else Color(0.05, 0.07, 0.1, 0.35))
		draw_arc(b[0], b[1], 0, TAU, 40, Color(1, 1, 1, 0.6), 2.5)
		draw_string(font, b[0] + Vector2(-b[1], 6), b[2], HORIZONTAL_ALIGNMENT_CENTER, b[1] * 2, 17 if b[1] > 50 else 14, Color(1, 1, 1, 0.9))
	var base := stick_origin if stick_id != -1 else Vector2(190, get_viewport_rect().size.y - 210)
	draw_circle(base, 95.0, Color(0.05, 0.07, 0.1, 0.25))
	draw_arc(base, 95.0, 0, TAU, 48, col, 2.5)
	var knob := base
	if stick_id != -1:
		var d := stick_pos - stick_origin
		knob = base + (d.normalized() * minf(d.length(), 95.0))
	draw_circle(knob, 40.0, Color(1, 1, 1, 0.4))
