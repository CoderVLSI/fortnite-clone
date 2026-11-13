## On-screen controls for phones and tablets, laid out like a mobile shooter: a move stick on the left (with a small
## left-thumb fire button above it), drag anywhere else to look, and a right-thumb cluster of round icon buttons:
## a big fire button, aim, jump, crouch, reload and build. In build mode the four pieces, the material and edit appear;
## USE only shows when there is something to use (with what it does beside it). Menu and backpack sit top left.
## Tap a hotbar box to select it and the minimap for the map.
extends Control

var game: Node
var move := Vector2.ZERO                 # x = right, y = forward
var look := Vector2.ZERO                 # accumulated drag in pixels, consumed by the player controller
var fire := false
var aim := false
var tsprint := false                     # tactical sprint: the sprint button, or the stick held at its rim
var edge_t := 0.0
var pressed_once := {}                   # button name -> true for one tick
var stick_id := -1
var stick_origin := Vector2.ZERO
var stick_pos := Vector2.ZERO
var look_ids := {}
var button_ids := {}                     # touch index -> button name
var font: Font
const FILL := Color(0.02, 0.03, 0.06, 0.32)
const RING := Color(1, 1, 1, 0.55)
const ICON := Color(1, 1, 1, 0.92)
const ACTIVE := Color(1.0, 0.72, 0.25, 0.55)


func setup(g: Node) -> void:
	game = g
	font = ThemeDB.fallback_font
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _mode() -> String:
	var ctl = game.controller
	if ctl and ctl.has_method("editing") and ctl.editing():
		return "edit"
	if game.player and game.player.build_piece != "":
		return "build"
	return "combat"


func buttons() -> Dictionary:
	## name -> [centre, radius, icon]. Sizes follow the screen height so every phone gets the same layout.
	var s := get_viewport_rect().size
	var u := s.y / 720.0
	var r := func(x: float, y: float) -> Vector2: return Vector2(s.x - x * u, s.y - y * u)
	var mode := _mode()
	var b := {
		"fire": [r.call(200, 270), 62.0 * u, "fire"],
		"fire_l": [Vector2(150 * u, s.y - 400 * u), 40.0 * u, "fire"],
		"jump": [r.call(80, 215), 46.0 * u, "jump"],
		"crouch": [r.call(330, 205), 34.0 * u, "crouch"],
		"aim": [r.call(320, 360), 38.0 * u, "aim"],
		"sprint": [r.call(440, 190), 32.0 * u, "sprint"],
		"build": [r.call(420, 290), 36.0 * u, "weapons" if mode != "combat" else "build"],
		"menu": [Vector2(46 * u, 40 * u), 26.0 * u, "menu"],
		"inv": [Vector2(112 * u, 40 * u), 26.0 * u, "inv"],
		"emote": [Vector2(178 * u, 40 * u), 26.0 * u, "emote"],
		"auto": [Vector2(s.x - 290 * u, 40 * u), 26.0 * u, "auto"],
	}
	if mode == "combat":
		b["reload"] = [r.call(110, 335), 32.0 * u, "reload"]
	else:
		b["edit"] = [r.call(110, 335), 32.0 * u, "edit"]                  # confirm an edit, or start one
		b["mat"] = [r.call(420, 380), 30.0 * u, "mat"]
		var x := 640.0
		for piece in ["b_wall", "b_floor", "b_stairs", "b_cone"]:
			b[piece] = [r.call(x, 440), 32.0 * u, piece]
			x -= 76.0
	if mode == "edit":
		b["reload"] = [r.call(420, 470), 28.0 * u, "reset"]              # reset the edit
	if game.controller and game.controller.prompt != "":
		b["use"] = [r.call(520, 300), 34.0 * u, "use"]
	return b


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
	if game.controller != null and game.controller.inv_open():       # the inventory screen takes the touches
		fire = false
		stick_id = -1
		move = Vector2.ZERO
		look_ids.clear()
		button_ids.clear()
		if e is InputEventScreenTouch and e.pressed:
			var bi: Array = buttons()["inv"]
			if e.position.distance_to(bi[0]) <= bi[1] * 1.2:
				pressed_once["inv"] = true
		return
	if e is InputEventScreenTouch:
		var p: Vector2 = e.position
		if e.pressed:
			var bs := buttons()
			for name in bs:
				var b: Array = bs[name]
				if p.distance_to(b[0]) <= b[1] * 1.2:
					button_ids[e.index] = name
					if name == "fire" or name == "fire_l":
						fire = true
						pressed_once["fire_down"] = true
						if name == "fire":
							look_ids[e.index] = true       # the right firing thumb can still steer the aim
					elif name == "aim":
						aim = not aim
						if aim:
							tsprint = false
					elif name == "sprint":
						tsprint = not tsprint
					elif name == "menu":
						game.pause_menu.open()
					else:
						pressed_once[name] = true
					return
			if game.controller != null and game.controller.show_map and game.hud != null and game.hud.fullmap_rect.has_point(p):
				game.controller.map_tap(p)               # the open map: a tap marks (or clears) a spot
				return
			var slot := _hotbar_slot(p)
			if slot > -2:
				game.cmd(game.player, "select", [slot])
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
				tsprint = false
			if button_ids.get(e.index, "") in ["fire", "fire_l"]:
				fire = false
			button_ids.erase(e.index)
			look_ids.erase(e.index)
	elif e is InputEventScreenDrag:
		if e.index == stick_id:
			stick_pos = e.position
			var u := get_viewport_rect().size.y / 720.0
			var d: Vector2 = (stick_pos - stick_origin) / (95.0 * u)
			if d.length() > 1.0:
				d = d.normalized()
			move = Vector2(d.x, -d.y) if d.length() > 0.15 else Vector2.ZERO
		elif look_ids.has(e.index):
			look += e.relative


func _process(d: float) -> void:
	# pushing the stick to its outer edge for 0.3 s starts a tactical sprint; easing off ends it
	if stick_id != -1 and move.length() > 0.96 and move.y > 0.3:
		edge_t += d
		if edge_t >= 0.3 and not fire and not aim:
			tsprint = true
	else:
		edge_t = 0.0
		if stick_id != -1 and move.length() < 0.5:
			tsprint = false
	queue_redraw()


# ----------------------------------------------------------------------------- drawing

func _draw() -> void:
	var s := get_viewport_rect().size
	var u := s.y / 720.0
	# the move stick: a resting ring bottom left, or under the thumb while it is held
	var sc := Vector2(170 * u, s.y - 170 * u) if stick_id == -1 else stick_origin
	draw_circle(sc, 82 * u, Color(0.02, 0.03, 0.06, 0.22))
	draw_arc(sc, 82 * u, 0, TAU, 48, Color(1, 1, 1, 0.35), 2.0 * u, true)
	var knob := sc if stick_id == -1 else sc + (stick_pos - stick_origin).limit_length(82 * u)
	draw_circle(knob, 34 * u, Color(1, 1, 1, 0.38))
	var bs := buttons()
	for name in bs:
		var b: Array = bs[name]
		var c: Vector2 = b[0]
		var rad: float = b[1]
		var held := button_ids.values().has(name)
		var on: bool = held or (name == "aim" and aim) or (name == "sprint" and tsprint) or ((name == "fire" or name == "fire_l") and fire) or (name == "auto" and Settings.auto_fire)
		if name.begins_with("b_"):
			on = on or game.player.build_piece == {"b_wall": "wall", "b_floor": "floor", "b_stairs": "stairs", "b_cone": "cone"}[name]
		draw_circle(c, rad, ACTIVE if on else FILL)
		draw_arc(c, rad, 0, TAU, 48, RING, 2.0 * u, true)
		_icon(b[2], c, rad * 0.5, u)
	# what USE will do, on a pill beside it
	if bs.has("use"):
		var t: String = game.controller.prompt
		var i := t.find(" ")
		t = t.substr(i + 1).strip_edges() if i >= 0 else t
		var fs := int(17 * u)
		var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 24 * u
		var pos: Vector2 = bs.use[0] + Vector2(-w - bs.use[1] - 8 * u, -16 * u)
		draw_rect(Rect2(pos, Vector2(w, 32 * u)), Color(0.02, 0.03, 0.06, 0.6))
		draw_string(font, pos + Vector2(12 * u, 22 * u), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 0.92, 0.55))


func _line(a: Vector2, b: Vector2, w: float) -> void:
	draw_line(a, b, ICON, w, true)


func _icon(kind: String, c: Vector2, r: float, u: float) -> void:
	## Simple vector icons, drawn at radius r around c.
	var w := maxf(2.5 * u, r * 0.13)
	match kind:
		"fire":                                     # crosshair
			draw_arc(c, r * 0.62, 0, TAU, 32, ICON, w, true)
			for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
				_line(c + d * r * 0.3, c + d * r * 1.0, w)
			draw_circle(c, w * 0.6, ICON)
		"aim":                                      # scope with a plus
			draw_arc(c, r * 0.75, 0, TAU, 32, ICON, w, true)
			_line(c + Vector2(-r * 0.35, 0), c + Vector2(r * 0.35, 0), w)
			_line(c + Vector2(0, -r * 0.35), c + Vector2(0, r * 0.35), w)
		"jump":                                     # double chevron up
			for k in 2:
				var y := c.y + r * (0.25 - 0.5 * k)
				_line(Vector2(c.x - r * 0.6, y + r * 0.3), Vector2(c.x, y - r * 0.25), w)
				_line(Vector2(c.x, y - r * 0.25), Vector2(c.x + r * 0.6, y + r * 0.3), w)
		"crouch":                                   # chevron down onto a line
			_line(Vector2(c.x - r * 0.55, c.y - r * 0.45), Vector2(c.x, c.y + r * 0.05), w)
			_line(Vector2(c.x, c.y + r * 0.05), Vector2(c.x + r * 0.55, c.y - r * 0.45), w)
			_line(Vector2(c.x - r * 0.7, c.y + r * 0.5), Vector2(c.x + r * 0.7, c.y + r * 0.5), w)
		"sprint":                                   # an arrow up with speed lines
			_line(Vector2(c.x - r * 0.55, c.y - r * 0.05), Vector2(c.x, c.y - r * 0.6), w)
			_line(Vector2(c.x, c.y - r * 0.6), Vector2(c.x + r * 0.55, c.y - r * 0.05), w)
			_line(Vector2(c.x, c.y - r * 0.6), Vector2(c.x, c.y + r * 0.6), w)
			_line(Vector2(c.x - r * 0.5, c.y + r * 0.3), Vector2(c.x - r * 0.5, c.y + r * 0.75), w * 0.8)
			_line(Vector2(c.x + r * 0.5, c.y + r * 0.3), Vector2(c.x + r * 0.5, c.y + r * 0.75), w * 0.8)
		"reload", "reset":                          # circular arrow
			draw_arc(c, r * 0.6, -PI * 0.35, PI * 1.45, 28, ICON, w, true)
			var tip := c + Vector2(cos(-PI * 0.35), sin(-PI * 0.35)) * r * 0.6
			_line(tip, tip + Vector2(-r * 0.4, -r * 0.05), w)
			_line(tip, tip + Vector2(0.05 * r, r * 0.4), w)
		"build":                                    # a brick wall
			for row in 3:
				var y := c.y - r * 0.6 + row * r * 0.42
				var off := 0.0 if row % 2 == 0 else r * 0.3
				for col in 3:
					var x := c.x - r * 0.75 + off + col * r * 0.5
					if x + r * 0.42 <= c.x + r * 0.8:
						draw_rect(Rect2(x, y, r * 0.42, r * 0.34), ICON)
		"weapons":                                  # a rifle: back to the guns
			draw_rect(Rect2(c.x - r * 0.85, c.y - r * 0.2, r * 1.5, r * 0.32), ICON)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.2, r * 0.1), c + Vector2(r * 0.05, r * 0.1), c + Vector2(-r * 0.05, r * 0.65), c + Vector2(-r * 0.3, r * 0.65)]), ICON)
			draw_colored_polygon(PackedVector2Array([c + Vector2(r * 0.55, -r * 0.2), c + Vector2(r * 0.85, -r * 0.35), c + Vector2(r * 0.85, r * 0.25), c + Vector2(r * 0.55, r * 0.12)]), ICON)
		"b_wall":
			draw_rect(Rect2(c.x - r * 0.5, c.y - r * 0.65, r * 1.0, r * 1.3), ICON, false, w)
			_line(Vector2(c.x - r * 0.5, c.y), Vector2(c.x + r * 0.5, c.y), w * 0.6)
		"b_floor":
			draw_polyline(PackedVector2Array([c + Vector2(-r * 0.8, r * 0.3), c + Vector2(-r * 0.3, -r * 0.3), c + Vector2(r * 0.8, -r * 0.3), c + Vector2(r * 0.3, r * 0.3), c + Vector2(-r * 0.8, r * 0.3)]), ICON, w, true)
		"b_stairs":
			draw_polyline(PackedVector2Array([c + Vector2(-r * 0.7, r * 0.6), c + Vector2(-r * 0.7, r * 0.2), c + Vector2(-r * 0.25, r * 0.2), c + Vector2(-r * 0.25, -r * 0.2),
					c + Vector2(r * 0.2, -r * 0.2), c + Vector2(r * 0.2, -r * 0.6), c + Vector2(r * 0.7, -r * 0.6)]), ICON, w, true)
		"b_cone":
			draw_polyline(PackedVector2Array([c + Vector2(-r * 0.75, r * 0.5), c + Vector2(0, -r * 0.6), c + Vector2(r * 0.75, r * 0.5), c + Vector2(-r * 0.75, r * 0.5)]), ICON, w, true)
		"mat":                                      # the current material's colour inside two turning arrows
			var m: String = game.player.build_mat
			draw_circle(c, r * 0.38, Items.MAT_COLORS.get(m, ICON))
			draw_arc(c, r * 0.75, 0.3, PI - 0.3, 16, ICON, w, true)
			draw_arc(c, r * 0.75, PI + 0.3, TAU - 0.3, 16, ICON, w, true)
		"edit":                                     # a 3 x 3 grid
			for i in 3:
				for j in 3:
					draw_rect(Rect2(c.x - r * 0.65 + i * r * 0.46, c.y - r * 0.65 + j * r * 0.46, r * 0.38, r * 0.38), ICON, (i + j) % 2 == 0)
		"use":                                      # a hand pointer: a dot in a ring
			draw_arc(c, r * 0.6, 0, TAU, 28, ICON, w, true)
			draw_circle(c, r * 0.25, ICON)
		"emote":                                    # a smiley
			draw_arc(c, r * 0.75, 0, TAU, 28, ICON, w * 0.8, true)
			draw_circle(c + Vector2(-r * 0.28, -r * 0.2), w * 0.7, ICON)
			draw_circle(c + Vector2(r * 0.28, -r * 0.2), w * 0.7, ICON)
			draw_arc(c + Vector2(0, r * 0.05), r * 0.38, 0.4, PI - 0.4, 14, ICON, w * 0.8, true)
		"auto":                                     # a crosshair with an A: auto fire
			draw_arc(c, r * 0.75, 0, TAU, 28, ICON, w * 0.8, true)
			draw_string(font, c + Vector2(-r * 0.75, r * 0.38), "A", HORIZONTAL_ALIGNMENT_CENTER, r * 1.5, int(r * 1.15), ICON)
		"menu":                                     # three bars
			for k in 3:
				_line(c + Vector2(-r * 0.6, (k - 1) * r * 0.45), c + Vector2(r * 0.6, (k - 1) * r * 0.45), w)
		"inv":                                      # a backpack
			draw_rect(Rect2(c.x - r * 0.55, c.y - r * 0.45, r * 1.1, r * 1.1), ICON, false, w)
			draw_arc(c + Vector2(0, -r * 0.45), r * 0.3, PI, TAU, 10, ICON, w, true)
			draw_rect(Rect2(c.x - r * 0.3, c.y + r * 0.1, r * 0.6, r * 0.35), ICON, false, w * 0.7)
