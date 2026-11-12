## Heads-up display, drawn with immediate-mode calls on one full-screen Control.
extends Control

const MAP_METRES := 460.0                 # the minimap texture covers 460 x 460 m centred on the island
const STORM_COL := Color(0.62, 0.3, 0.95)

var game: Node
var font: Font
var map_tex: Texture2D
var numbers: Array = []                   # floating damage numbers {pos, text, color, born}
var arcs: Array = []                      # incoming damage directions {from, born}
var notes: Array = []                     # pickup notes {text, color, born}
var hit_time := -9.0
var kill_time := -9.0
var mat_notes: Array = []
var icons := {}                           # name -> Texture2D (null when missing)                 # +N popups next to the material counters {mat, n, crit, born}


func setup(g: Node) -> void:
	game = g
	font = ThemeDB.fallback_font
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_tex = load("res://textures/minimap.png")


func add_damage_number(at: Vector3, amount: float, shielded: bool, killed: bool) -> void:
	numbers.append({"pos": at + Vector3(0, 0.3, 0), "text": str(int(round(amount))), "color": Color(0.45, 0.75, 1.0) if shielded else Color(1, 1, 1), "born": game.match_time,
			"dx": randf_range(-30, 30)})
	hit_time = game.match_time
	if killed:
		kill_time = game.match_time


func add_structure_number(at: Vector3, amount: float) -> void:
	numbers.append({"pos": at, "text": str(int(round(amount))), "color": Color(0.82, 0.84, 0.86), "born": game.match_time, "dx": randf_range(-20, 20)})


func add_mat_note(mat: String, n: int, crit: bool) -> void:
	mat_notes.append({"mat": mat, "n": n, "crit": crit, "born": game.match_time})
	if mat_notes.size() > 8:
		mat_notes.pop_front()


func add_damage_arc(from: Vector3) -> void:
	arcs.append({"from": from, "born": game.match_time})


func add_pickup_note(it: Dictionary) -> void:
	var t := ""
	var c := Color.WHITE
	if it.has("ammo"):
		t = "+%d %s ammo" % [it.get("count", Items.AMMO_PICKUP[it.ammo]), it.ammo]
		c = Items.AMMO_COLORS[it.ammo]
	elif it.has("mat"):
		add_mat_note(it.mat, int(it.count), false)
		return
	elif it.has("forage"):
		t = "+5 health" if it.forage == "apple" else "+5 shield"
		c = Color(0.5, 0.95, 0.4) if it.forage == "apple" else Color(0.45, 0.75, 1.0)
	else:
		t = "+ " + Items.label(it)
		c = Items.RARITY_COLORS[it.rarity]
	notes.append({"text": t, "color": c, "born": game.match_time, "icon": item_icon(it)})
	if notes.size() > 5:
		notes.pop_front()


func _process(_d: float) -> void:
	queue_redraw()


func icon(name: String) -> Texture2D:
	if not icons.has(name):
		var p := "res://textures/icons/%s.png" % name
		icons[name] = load(p) if ResourceLoader.exists(p) else null
	return icons[name]


func draw_icon(name: String, r: Rect2, mod := Color.WHITE) -> bool:
	## Draws the icon into the rectangle; false when there is no icon for it.
	var t := icon(name)
	if t == null:
		return false
	draw_texture_rect(t, r, false, mod)
	return true


func item_icon(it: Dictionary) -> String:
	if it.has("ammo"):
		return "ammo_" + it.ammo
	if it.has("mat"):
		return "mat_" + it.mat
	if it.has("forage"):
		return "health" if it.forage == "apple" else "shield"
	return it.id


func txt(pos: Vector2, s: String, size := 18, col := Color.WHITE, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	draw_string(font, pos + Vector2(1.5, 1.5), s, align, width, size, Color(0, 0, 0, 0.75 * col.a))
	draw_string(font, pos, s, align, width, size, col)


func panel(r: Rect2, col := Color(0.05, 0.07, 0.1, 0.55)) -> void:
	draw_rect(r, col)


func _draw() -> void:
	if game == null or game.controller == null:
		return
	var sz := get_viewport_rect().size       # the control itself has no layout size inside a CanvasLayer
	var ctl = game.controller
	var s: Actor = ctl.subject()
	var p: Actor = game.player
	var now: float = game.match_time
	if s == null:
		return
	# purple wash while inside the storm
	if game.storm.active and s.alive() and game.storm.outside(s.global_position) > 0.0 and s.state != Actor.State.BLIMP:
		draw_rect(Rect2(Vector2.ZERO, sz), Color(0.45, 0.15, 0.75, 0.26 + 0.05 * sin(now * 4.0)))
		txt(Vector2(0, sz.y * 0.2), "YOU ARE IN THE STORM", 26, Color(0.9, 0.75, 1.0), HORIZONTAL_ALIGNMENT_CENTER, sz.x)
	if scoped(s, ctl):
		_draw_scope(sz)                            # under the rest of the HUD
	_draw_world_numbers(ctl.cam, now)
	_draw_arcs(sz, ctl, now)
	_draw_compass(sz, ctl.yaw)
	_draw_minimap(sz, s)
	_draw_feed(sz, now)
	_draw_status(sz, s)
	_draw_hotbar(sz, s)
	_draw_centre(sz, s, ctl, now)
	_draw_notes(sz, now)
	if game.structures.edit_entry != null:
		var hint := "EDITING   click or drag tiles   ·   G confirm   ·   R reset" if ctl.touch == null else "EDITING   tap tiles with FIRE   ·   EDIT confirm   ·   RELOAD reset"
		var w := font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x + 40
		panel(Rect2(sz.x / 2 - w / 2, sz.y - 168, w, 36), Color(0.1, 0.25, 0.45, 0.8))
		txt(Vector2(0, sz.y - 143), hint, 18, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, sz.x)
	if p.alive():
		_draw_target_health(sz, ctl, p)
	if ctl.show_map:
		_draw_full_map(sz, s)
	if not p.alive() and not game.over:
		panel(Rect2(sz.x / 2 - 260, sz.y - 250, 520, 64))
		txt(Vector2(0, sz.y - 222), "Spectating  %s" % s.display_name, 24, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, sz.x)
		txt(Vector2(0, sz.y - 198), "You placed #%d with %d eliminations    [Click] next player" % [p.placement, p.kills], 16, Color(0.85, 0.88, 0.92), HORIZONTAL_ALIGNMENT_CENTER, sz.x)
	if game.over:
		_draw_end(sz, p)


func _draw_world_numbers(cam: Camera3D, now: float) -> void:
	for n in numbers.duplicate():
		var age: float = now - n.born
		if age > 0.9:
			numbers.erase(n)
			continue
		if cam.is_position_behind(n.pos):
			continue
		var sp := cam.unproject_position(n.pos) + Vector2(n.dx, -70.0 * age)
		txt(sp, n.text, 26, Color(n.color.r, n.color.g, n.color.b, 1.0 - age / 0.9))


func _draw_arcs(sz: Vector2, ctl: Node, now: float) -> void:
	var c := sz / 2
	var s: Actor = ctl.subject()
	for a in arcs.duplicate():
		var age: float = now - a.born
		if age > 1.6:
			arcs.erase(a)
			continue
		var to: Vector3 = a.from - s.global_position
		var ang = atan2(-to.x, -to.z) - ctl.yaw          # 0 = straight ahead, positive = to the left
		var mid = -PI / 2 - ang
		draw_arc(c, 150.0, mid - 0.32, mid + 0.32, 14, Color(1.0, 0.2, 0.15, 0.85 * (1.0 - age / 1.6)), 9.0)


func _draw_compass(sz: Vector2, yaw: float) -> void:
	var w := 520.0
	var x0 := sz.x / 2 - w / 2
	panel(Rect2(x0, 14, w, 34))
	var heading := fposmod(-rad_to_deg(yaw), 360.0)      # 0 = north (-Z), 90 = east
	var names := {0: "N", 45: "NE", 90: "E", 135: "SE", 180: "S", 225: "SW", 270: "W", 315: "NW"}
	for d in range(0, 360, 15):
		var rel := fposmod(d - heading + 180.0, 360.0) - 180.0
		if absf(rel) > 78.0:
			continue
		var x := sz.x / 2 + rel / 78.0 * (w / 2 - 14)
		if names.has(d):
			txt(Vector2(x - 30, 38), names[d], 18 if d % 90 == 0 else 14, Color.WHITE if d % 90 == 0 else Color(0.8, 0.84, 0.9), HORIZONTAL_ALIGNMENT_CENTER, 60)
		else:
			draw_line(Vector2(x, 24), Vector2(x, 36), Color(1, 1, 1, 0.5), 1.5)
	draw_colored_polygon(PackedVector2Array([Vector2(sz.x / 2 - 7, 48), Vector2(sz.x / 2 + 7, 48), Vector2(sz.x / 2, 58)]), Color(1.0, 0.85, 0.3))
	txt(Vector2(sz.x / 2 - 30, 78), "%d" % int(heading), 15, Color(1.0, 0.9, 0.5), HORIZONTAL_ALIGNMENT_CENTER, 60)


func _map_point(world: Vector2, origin: Vector2, extent: float, centre: Vector2, span: float) -> Vector2:
	## world metres -> screen, for a map rectangle at `origin` of size `extent` showing `span` metres around `centre`
	return origin + (world - centre) / span * extent + Vector2(extent, extent) / 2


func _draw_map(origin: Vector2, extent: float, centre: Vector2, span: float, s: Actor, big: bool) -> void:
	var st: Storm = game.storm
	if map_tex:
		var uv0 := (centre - Vector2(span, span) / 2) / MAP_METRES + Vector2(0.5, 0.5)
		var src := Rect2(uv0 * Vector2(map_tex.get_size()), Vector2(span, span) / MAP_METRES * Vector2(map_tex.get_size()))
		draw_texture_rect_region(map_tex, Rect2(origin, Vector2(extent, extent)), src)
	else:
		draw_rect(Rect2(origin, Vector2(extent, extent)), Color(0.2, 0.4, 0.6))
	# storm: the current wall and the next safe circle
	var k := extent / span
	if st.active:
		draw_arc(_map_point(st.center, origin, extent, centre, span), maxf(st.radius * k, 1.0), 0, TAU, 72, STORM_COL, 3.0 if big else 2.0)
		draw_arc(_map_point(st.next_center, origin, extent, centre, span), maxf(st.next_radius * k, 1.0), 0, TAU, 72, Color(1, 1, 1, 0.95), 2.0 if big else 1.5)
	if game.match_time < game.BLIMP_TIME:
		var a := _map_point(Vector2(game.blimp_from.x, game.blimp_from.z), origin, extent, centre, span)
		var e: Vector3 = game.blimp_from + game.blimp_dir * game.BLIMP_SPEED * game.BLIMP_TIME
		draw_dashed_line(a, _map_point(Vector2(e.x, e.z), origin, extent, centre, span), Color(1, 1, 1, 0.8), 2.0, 8.0)
		var bp: Vector3 = game.blimp_pos()
		draw_circle(_map_point(Vector2(bp.x, bp.z), origin, extent, centre, span), 5.0, Color(1.0, 0.6, 0.2))
	# supply drops: falling ones pulse, landed unopened ones stay marked
	for d in game.events.drops:
		var dp: Vector3 = (d.node as Node3D).global_position
		var opened := false
		for c in game.containers:
			if c.node == d.node and c.opened:
				opened = true
		if opened:
			continue
		var mp := _map_point(Vector2(dp.x, dp.z), origin, extent, centre, span)
		var ms := (16.0 if big else 12.0) * (1.0 + (0.25 * sin(game.match_time * 6.0) if not d.landed else 0.0))
		if not draw_icon("supply_drop", Rect2(mp - Vector2(ms, ms), Vector2(ms, ms) * 2.0)):
			draw_circle(mp, ms * 0.5, Color(0.3, 0.75, 1.0))
	# the player arrow
	var pp := _map_point(Vector2(s.global_position.x, s.global_position.z), origin, extent, centre, span)
	var yaw: float = game.controller.yaw
	var f := Vector2(-sin(yaw), -cos(yaw))
	var r := Vector2(f.y, -f.x)
	var sc := 9.0 if big else 7.0
	draw_colored_polygon(PackedVector2Array([pp + f * sc * 1.4, pp - f * sc * 0.8 + r * sc * 0.8, pp - f * sc * 0.3, pp - f * sc * 0.8 - r * sc * 0.8]), Color(1.0, 0.95, 0.3))
	draw_polyline(PackedVector2Array([pp + f * sc * 1.4, pp - f * sc * 0.8 + r * sc * 0.8, pp - f * sc * 0.3, pp - f * sc * 0.8 - r * sc * 0.8, pp + f * sc * 1.4]), Color(0, 0, 0, 0.8), 1.5)


func _draw_minimap(sz: Vector2, s: Actor) -> void:
	var extent := 230.0
	var origin := Vector2(sz.x - extent - 22, 22)
	var centre := Vector2(s.global_position.x, s.global_position.z)
	var span := 190.0
	centre = centre.clamp(Vector2(-MAP_METRES / 2 + span / 2, -MAP_METRES / 2 + span / 2), Vector2(MAP_METRES / 2 - span / 2, MAP_METRES / 2 - span / 2))
	draw_rect(Rect2(origin - Vector2(3, 3), Vector2(extent + 6, extent + 6)), Color(0.05, 0.07, 0.1, 0.8))
	_draw_map(origin, extent, centre, span, s, false)
	draw_rect(Rect2(origin, Vector2(extent, extent)), Color(1, 1, 1, 0.5), false, 2.0)
	# storm timer, players left, eliminations
	var st: Storm = game.storm
	var y := origin.y + extent + 12
	panel(Rect2(origin.x - 3, y, extent + 6, 36))
	var label := "Storm forms in" if not st.active else ("Storm closing" if st.shrinking else "Storm moves in")
	var t: float = st.time_left() if st.active else maxf(20.0 - game.match_time, 0.0)
	if st.done:
		label = "Final circle"; t = 0.0
	var sx := origin.x + 8
	if draw_icon("storm", Rect2(origin.x + 4, y + 4, 28, 28)):
		sx += 30
	txt(Vector2(sx, y + 24), "%s  %d:%02d" % [label, int(t) / 60, int(t) % 60], 16, Color(0.85, 0.7, 1.0) if st.shrinking else Color.WHITE)
	panel(Rect2(origin.x - 3, y + 40, extent + 6, 36))
	if draw_icon("alive", Rect2(origin.x + 4, y + 44, 28, 28)):
		txt(Vector2(origin.x + 36, y + 64), "%d" % game.alive_count(), 20)
	else:
		txt(Vector2(origin.x + 8, y + 64), "Alive  %d" % game.alive_count(), 18)
	if draw_icon("elims", Rect2(origin.x + 118, y + 44, 28, 28)):
		txt(Vector2(origin.x + 150, y + 64), "%d" % game.player.kills, 20)
	else:
		txt(Vector2(origin.x + 120, y + 64), "Elims  %d" % game.player.kills, 18)


func _draw_full_map(sz: Vector2, s: Actor) -> void:
	var extent := minf(sz.y - 120.0, 760.0)
	var origin := Vector2((sz.x - extent) / 2, (sz.y - extent) / 2)
	draw_rect(Rect2(Vector2.ZERO, sz), Color(0, 0, 0, 0.45))
	draw_rect(Rect2(origin - Vector2(6, 6), Vector2(extent + 12, extent + 12)), Color(0.05, 0.07, 0.1, 0.9))
	_draw_map(origin, extent, Vector2.ZERO, MAP_METRES, s, true)
	for i in 7:                                           # 6 x 6 grid like the reference map
		var o := extent * (0.5 + (i - 3) * (400.0 / 6.0) / MAP_METRES)
		draw_line(origin + Vector2(o, 0), origin + Vector2(o, extent), Color(1, 1, 1, 0.18), 1.0)
		draw_line(origin + Vector2(0, o), origin + Vector2(extent, o), Color(1, 1, 1, 0.18), 1.0)
	txt(Vector2(0, origin.y - 14), "ISLAND MAP   [M] close", 20, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, sz.x)


func _draw_feed(_sz: Vector2, now: float) -> void:
	var y := 120.0
	for k in game.kill_feed:
		var age: float = now - k.time
		if age > 7.0:
			continue
		var al := clampf(7.0 - age, 0.0, 1.0)
		var w := font.get_string_size(k.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x + 20
		panel(Rect2(18, y - 20, w, 28), Color(0.05, 0.07, 0.1, 0.55 * al))
		txt(Vector2(28, y), k.text, 16, Color(1.0, 0.9, 0.45, al) if k.mine else Color(1, 1, 1, al))
		y += 32


func _draw_status(sz: Vector2, s: Actor) -> void:
	var x := 60.0
	var y := sz.y - 96.0
	var w := 340.0
	# shield above health
	panel(Rect2(x - 4, y - 4, w + 8, 66))
	draw_rect(Rect2(x, y, w, 22), Color(0.1, 0.14, 0.22, 0.9))
	draw_rect(Rect2(x, y, w * clampf(s.shield / 100.0, 0, 1), 22), Color(0.25, 0.6, 1.0))
	if draw_icon("shield", Rect2(x - 34, y - 3, 28, 28)):
		pass
	txt(Vector2(x + 8, y + 17), "SHIELD", 13, Color(0.9, 0.95, 1.0))
	txt(Vector2(x, y + 17), str(int(ceil(s.shield))), 16, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, w - 8)
	draw_rect(Rect2(x, y + 30, w, 28), Color(0.12, 0.18, 0.12, 0.9))
	draw_rect(Rect2(x, y + 30, w * clampf(s.hp / 100.0, 0, 1), 28), Color(0.3, 0.82, 0.3) if s.hp > 30.0 else Color(0.9, 0.3, 0.2))
	draw_icon("health", Rect2(x - 34, y + 30, 28, 28))
	txt(Vector2(x + 8, y + 51), "HEALTH", 13, Color(0.92, 1.0, 0.92))
	txt(Vector2(x, y + 51), str(int(ceil(s.hp))), 20, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, w - 8)
	txt(Vector2(x, y - 14), s.display_name, 16, Color(0.9, 0.92, 0.95))
	var mv := "SWIMMING" if s.state == Actor.State.SWIM else ("SLIDING" if s.sliding else ("CROUCHED" if s.crouched else ""))
	if mv != "":
		txt(Vector2(x, y - 14), mv, 14, Color(0.6, 0.85, 1.0), HORIZONTAL_ALIGNMENT_RIGHT, w)


func _draw_hotbar(sz: Vector2, s: Actor) -> void:
	var box := 78.0
	var gap := 8.0
	var total := (box + gap) * 6
	var x0 := sz.x - total - 18
	var y0 := sz.y - box - 26
	_draw_mats(Vector2(x0 - 132, y0 - 4), s)
	if s.build_piece != "":
		_draw_build_bar(x0, y0, box, gap, s)
	for i in (0 if s.build_piece != "" else 6):
		var slot := i - 1                                  # the first box is the pickaxe
		var r := Rect2(x0 + i * (box + gap), y0, box, box)
		var it = s.slots[slot] if slot >= 0 else null
		var col := Color(0.08, 0.1, 0.14, 0.7)
		if it != null:
			var rc: Color = Items.RARITY_COLORS[it.rarity]
			col = Color(rc.r * 0.55, rc.g * 0.55, rc.b * 0.55, 0.85)
		draw_rect(r, col)
		var act: bool = s.active == slot
		draw_rect(r, Color(1, 1, 1, 0.95) if act else Color(1, 1, 1, 0.25), false, 3.0 if act else 1.5)
		txt(r.position + Vector2(5, 15), "F" if slot < 0 else str(slot + 1), 12, Color(1, 1, 1, 0.8))
		var ir := Rect2(r.position + Vector2(9, 9), Vector2(box - 18, box - 18))
		if slot < 0:
			if not draw_icon("pickaxe", ir):
				txt(r.position + Vector2(0, 46), "Pickaxe", 13, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, box)
		elif it != null:
			var d: Dictionary = Items.def(it)
			if not draw_icon(it.id, ir):
				var words: PackedStringArray = d.name.split(" ")
				for wi in words.size():
					txt(r.position + Vector2(0, 36 + wi * 15), words[wi], 13, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, box)
			if d.kind == "weapon":
				txt(r.position + Vector2(0, box - 7), "%d" % it.loaded, 14, Color(1, 1, 1, 0.95), HORIZONTAL_ALIGNMENT_RIGHT, box - 6)
			else:
				txt(r.position + Vector2(0, box - 7), "x%d" % it.count, 14, Color(1, 1, 1, 0.95), HORIZONTAL_ALIGNMENT_RIGHT, box - 6)
	# ammo for the weapon in hand, and the reserves by type
	var held = s.item()
	if held != null and Items.def(held).kind == "weapon":
		var d2: Dictionary = Items.def(held)
		panel(Rect2(sz.x - 260, y0 - 74, 242, 60))
		txt(Vector2(sz.x - 250, y0 - 28), "%d" % held.loaded, 40, Color.WHITE if held.loaded > 0 else Color(1.0, 0.4, 0.3))
		txt(Vector2(sz.x - 170, y0 - 28), "/ %d" % s.ammo[d2.ammo], 24, Color(0.85, 0.88, 0.92))
		txt(Vector2(sz.x - 260, y0 - 50), Items.label(held), 14, Items.RARITY_COLORS[held.rarity], HORIZONTAL_ALIGNMENT_RIGHT, 232)
		txt(Vector2(sz.x - 260, y0 - 30), d2.ammo + " ammo", 13, Items.AMMO_COLORS[d2.ammo], HORIZONTAL_ALIGNMENT_RIGHT, 232)
	var ax := x0
	for t in Items.AMMO_TYPES:
		if not draw_icon("ammo_" + t, Rect2(ax - 4, y0 - 31, 20, 20)):
			draw_rect(Rect2(ax, y0 - 24, 10, 10), Items.AMMO_COLORS[t])
		txt(Vector2(ax + 17, y0 - 14), "%d" % s.ammo[t], 13, Color(0.9, 0.92, 0.95))
		ax += 52


func _draw_mats(o: Vector2, s: Actor) -> void:
	var now: float = game.match_time
	panel(Rect2(o.x - 6, o.y - 4, 122, 92))
	for i in Structures.MATS.size():
		var m: String = Structures.MATS[i]
		var y := o.y + i * 29
		var col: Color = Items.MAT_COLORS[m]
		if not draw_icon("mat_" + m, Rect2(o.x - 3, y + 1, 24, 24)):
			draw_rect(Rect2(o.x, y + 4, 18, 18), col)
			draw_rect(Rect2(o.x, y + 4, 18, 18), Color(0, 0, 0, 0.6), false, 1.5)
		var low: bool = s.build_piece != "" and m == s.build_mat and int(s.mats[m]) < Structures.COST
		txt(Vector2(o.x + 26, y + 21), "%d" % int(s.mats[m]), 19, Color(1.0, 0.45, 0.35) if low else Color.WHITE)
		if s.build_piece != "" and m == s.build_mat:
			draw_rect(Rect2(o.x - 4, y + 1, 114, 26), Color(1, 1, 1, 0.9), false, 2.0)
	# +N popups rise from the counter they belong to
	for n in mat_notes.duplicate():
		var age: float = now - n.born
		if age > 1.4:
			mat_notes.erase(n)
			continue
		var i2: int = Structures.MATS.find(n.mat)
		var y2 := o.y + i2 * 29 + 20 - age * 26.0
		var c: Color = Color(0.4, 0.8, 1.0) if n.crit else Items.MAT_COLORS[n.mat]
		c.a = clampf(1.4 - age, 0.0, 1.0)
		txt(Vector2(o.x - 64, y2), "+%d" % n.n, 20 if n.crit else 17, c, HORIZONTAL_ALIGNMENT_RIGHT, 56)


func _draw_build_bar(x0: float, y0: float, box: float, gap: float, s: Actor) -> void:
	var keys := {"wall": "Q", "floor": "Z", "stairs": "C", "cone": "V"}
	for i in Structures.PIECES.size():
		var p: String = Structures.PIECES[i]
		var r := Rect2(x0 + i * (box + gap), y0, box, box)
		var act: bool = s.build_piece == p
		draw_rect(r, Color(0.15, 0.35, 0.6, 0.85) if act else Color(0.08, 0.1, 0.14, 0.7))
		draw_rect(r, Color(1, 1, 1, 0.95) if act else Color(1, 1, 1, 0.25), false, 3.0 if act else 1.5)
		txt(r.position + Vector2(5, 15), keys[p], 12, Color(1, 1, 1, 0.8))
		if draw_icon("build_" + p, Rect2(r.position + Vector2(13, 10), Vector2(box - 26, box - 26))):
			txt(r.position + Vector2(0, box - 5), Structures.PIECE_NAMES[p], 11, Color(1, 1, 1, 0.9), HORIZONTAL_ALIGNMENT_CENTER, box)
		else:
			txt(r.position + Vector2(0, 47), Structures.PIECE_NAMES[p], 14, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, box)
	var r2 := Rect2(x0 + 4 * (box + gap), y0, box * 2 + gap, box)
	var mc: Color = Items.MAT_COLORS[s.build_mat]
	draw_rect(r2, Color(mc.r * 0.45, mc.g * 0.45, mc.b * 0.45, 0.85))
	draw_rect(r2, Color(1, 1, 1, 0.6), false, 1.5)
	txt(r2.position + Vector2(0, 30), Items.MAT_NAMES[s.build_mat], 20, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, r2.size.x)
	var enough: bool = int(s.mats[s.build_mat]) >= Structures.COST
	txt(r2.position + Vector2(0, 52), "%d each   %d left" % [Structures.COST, int(s.mats[s.build_mat])], 13, Color.WHITE if enough else Color(1.0, 0.45, 0.35), HORIZONTAL_ALIGNMENT_CENTER, r2.size.x)
	txt(r2.position + Vector2(0, 70), "Right click: material" if game.controller.touch == null else "MAT: material", 12, Color(0.85, 0.88, 0.92), HORIZONTAL_ALIGNMENT_CENTER, r2.size.x)


func _draw_target_health(sz: Vector2, ctl: Node, s: Actor) -> void:
	var e = ctl.look_entry
	if e == null or e.dead:
		return
	if e.kind != "build" and e.hp >= e.max and s.active != -1:
		return
	var w := 200.0
	var r := Rect2(sz.x / 2 - w / 2, sz.y / 2 + 44, w, 10)
	draw_rect(r, Color(0, 0, 0, 0.55))
	var k := clampf(e.hp / e.max, 0.0, 1.0)
	var col: Color = Items.MAT_COLORS[e.mat]
	draw_rect(Rect2(r.position, Vector2(w * k, r.size.y)), col)
	var label: String = (Items.MAT_NAMES[e.mat] + " " + Structures.PIECE_NAMES[e.piece]) if e.kind == "build" else e.name.replace("_", " ").capitalize()
	if e.kind == "build" and e.get("born", -9.0) + Structures.BUILD_TIME[e.mat] > game.match_time:
		label += "  (building)"
	txt(Vector2(0, r.position.y - 4), "%s   %d / %d" % [label, int(ceil(e.hp)), int(e.max)], 14, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, sz.x)


func _spread_px(sz: Vector2, ctl: Node, deg: float) -> float:
	## How many pixels from the centre a shot at the edge of the cone lands, for the current zoom.
	var cam: Camera3D = ctl.cam
	return tan(deg_to_rad(deg)) / tan(deg_to_rad(cam.fov) * 0.5) * sz.y * 0.5


func _xline(a: Vector2, b: Vector2, w := 2.0) -> void:
	draw_line(a, b, Color(0, 0, 0, 0.65), w + 2.0)
	draw_line(a, b, Color(1, 1, 1, 0.95), w)


func _xring(c: Vector2, r: float, w := 2.0) -> void:
	draw_arc(c, r, 0, TAU, 48, Color(0, 0, 0, 0.6), w + 2.0)
	draw_arc(c, r, 0, TAU, 48, Color(1, 1, 1, 0.92), w)


func _draw_crosshair(sz: Vector2, s: Actor, ctl: Node) -> void:
	## A reticle per weapon, sized to the weapon's real spread right now.
	var c := sz / 2
	if s.state == Actor.State.SWIM:
		_xring(c, 3.0, 1.5)
		return
	if s.build_piece != "" or game.structures.edit_entry != null:
		draw_rect(Rect2(c - Vector2(5, 5), Vector2(10, 10)), Color(0, 0, 0, 0.6), false, 3.0)
		draw_rect(Rect2(c - Vector2(5, 5), Vector2(10, 10)), Color(1, 1, 1, 0.95), false, 1.5)
		return
	var it = s.item()
	if it == null:                                  # pickaxe: a small circle
		_xring(c, 6.0, 1.5)
		draw_circle(c, 1.5, Color(1, 1, 1, 0.9))
		return
	var d: Dictionary = Items.def(it)
	if d.kind != "weapon":                          # consumables and throwables: a dot
		draw_circle(c, 3.5, Color(0, 0, 0, 0.6))
		draw_circle(c, 2.2, Color(1, 1, 1, 0.95))
		return
	var gap := maxf(_spread_px(sz, ctl, s.spread_deg(d)), 4.0)
	match it.id:
		"shotgun":                                  # a wide ring the size of the pellet spread
			_xring(c, gap, 2.0)
			for dv in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
				_xline(c + dv * (gap - 4.0), c + dv * (gap + 6.0), 2.0)
			draw_circle(c, 1.6, Color(1, 1, 1, 0.9))
		"sniper_rifle":
			if not scoped(s, ctl):
				draw_circle(c, 2.2, Color(1, 1, 1, 0.95))
				_xring(c, 9.0, 1.2)
		"rocket_launcher":                          # a ring with range ticks below
			_xring(c, 14.0, 2.0)
			draw_circle(c, 2.0, Color(1, 1, 1, 0.95))
			for k in 3:
				_xline(c + Vector2(-6 + k * 1.5, 22 + k * 9), c + Vector2(6 - k * 1.5, 22 + k * 9), 1.5)
		_:                                          # pistol and rifle: four lines that open with the spread
			for dv in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
				_xline(c + dv * gap, c + dv * (gap + 9.0), 2.0)
			draw_circle(c, 1.6, Color(1, 1, 1, 0.9))


func scoped(s: Actor, ctl: Node) -> bool:
	var it = s.item()
	return it != null and it.id == "sniper_rifle" and ctl.zoom > 0.85 and s == game.player and s.alive()


func _draw_scope(sz: Vector2) -> void:
	var c := sz / 2
	var r := sz.y * 0.44
	var black := Color(0.02, 0.02, 0.03, 1.0)
	# everything outside the lens is black
	var pts := PackedVector2Array()
	for k in 65:
		var a := TAU * k / 64.0
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	draw_rect(Rect2(0, 0, c.x - r + 1, sz.y), black)
	draw_rect(Rect2(c.x + r - 1, 0, sz.x - c.x - r + 1, sz.y), black)
	for k in 64:
		var a0 := TAU * k / 64.0
		var a1 := TAU * (k + 1) / 64.0
		var p0 := c + Vector2(cos(a0), sin(a0)) * r
		var p1 := c + Vector2(cos(a1), sin(a1)) * r
		var edge := Vector2(p0.x, c.y - r - 2 if p0.y < c.y else c.y + r + 2)
		var edge2 := Vector2(p1.x, c.y - r - 2 if p1.y < c.y else c.y + r + 2)
		draw_colored_polygon(PackedVector2Array([p0, p1, edge2, edge]), black)
	draw_rect(Rect2(c.x - r, 0, r * 2, c.y - r), black)
	draw_rect(Rect2(c.x - r, c.y + r, r * 2, sz.y - c.y - r), black)
	draw_arc(c, r, 0, TAU, 96, Color(0.1, 0.1, 0.12), 6.0)
	# thin cross with mil dots, thicker towards the edge
	var line := Color(0.05, 0.05, 0.05, 0.95)
	draw_line(c - Vector2(r, 0), c - Vector2(r * 0.35, 0), line, 4.0)
	draw_line(c + Vector2(r * 0.35, 0), c + Vector2(r, 0), line, 4.0)
	draw_line(c + Vector2(0, r * 0.35), c + Vector2(0, r), line, 4.0)
	draw_line(c - Vector2(r * 0.35, 0), c + Vector2(r * 0.35, 0), line, 1.2)
	draw_line(c - Vector2(0, r * 0.6), c + Vector2(0, r * 0.35), line, 1.2)
	for k in range(1, 5):
		var o := r * 0.08 * k
		draw_circle(c + Vector2(o, 0), 2.2, line)
		draw_circle(c - Vector2(o, 0), 2.2, line)
		draw_circle(c + Vector2(0, o), 2.2, line)
	draw_circle(c, 1.8, Color(0.9, 0.15, 0.1))


func _draw_centre(sz: Vector2, s: Actor, ctl: Node, now: float) -> void:
	var c := sz / 2
	if s.alive() and (s.state == Actor.State.GROUND or s.state == Actor.State.SWIM):
		_draw_crosshair(sz, s, ctl)
	# hit marker: white cross, red when it was an elimination
	var ht := now - hit_time
	if ht < 0.22:
		var col := Color(1.0, 0.25, 0.2) if now - kill_time < 0.4 else Color(1, 1, 1)
		col.a = 1.0 - ht / 0.22
		for d2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			draw_line(c + d2 * 9, c + d2 * 19, col, 3.0)
	# reload / use progress
	var prog := -1.0
	var label := ""
	if s.using > 0.0:
		prog = 1.0 - s.using / maxf(s.use_total, 0.01)
		label = "Using  %.1f s" % s.using
	elif s.reloading > 0.0 and s.item() != null:
		prog = 1.0 - s.reloading / Items.reload_time(s.item())
		label = "Reloading"
	if prog >= 0.0:
		var r := Rect2(c.x - 130, c.y + 90, 260, 14)
		draw_rect(r, Color(0, 0, 0, 0.6))
		draw_rect(Rect2(r.position, Vector2(r.size.x * prog, r.size.y)), Color(1.0, 0.85, 0.3))
		txt(Vector2(0, r.position.y - 8), label, 16, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, sz.x)
	if ctl.prompt != "":
		var w := font.get_string_size(ctl.prompt, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x + 36
		panel(Rect2(c.x - w / 2, c.y + 130, w, 40), Color(0.05, 0.07, 0.1, 0.75))
		txt(Vector2(0, c.y + 157), ctl.prompt, 20, Color(1.0, 0.92, 0.5), HORIZONTAL_ALIGNMENT_CENTER, sz.x)
	# drop phase information
	if s.state == Actor.State.BLIMP:
		txt(Vector2(0, sz.y * 0.72), "Tap JUMP to drop" if game.controller.touch != null else "[Space]  Jump", 30, Color(1.0, 0.92, 0.5), HORIZONTAL_ALIGNMENT_CENTER, sz.x)
		txt(Vector2(0, sz.y * 0.72 + 30), "The blimp leaves the island in %d s" % int(maxf(game.BLIMP_TIME - now, 0.0)), 18, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, sz.x)
	elif s.state == Actor.State.SKYDIVE or s.state == Actor.State.GLIDE:
		var h := s.height_above_ground()
		txt(Vector2(0, sz.y * 0.76), "%d m" % int(h), 30, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, sz.x)
		txt(Vector2(0, sz.y * 0.76 + 26), "Glider open" if s.state == Actor.State.GLIDE else "Glider opens at %d m    look down or hold Shift to dive" % int(Actor.GLIDER_HEIGHT), 16,
				Color(0.85, 0.9, 1.0), HORIZONTAL_ALIGNMENT_CENTER, sz.x)
	if now - game.announce_time < 4.0 and game.announce_text != "":
		txt(Vector2(0, sz.y * 0.28), game.announce_text, 28, Color(1, 1, 1, clampf(4.0 - (now - game.announce_time), 0, 1)), HORIZONTAL_ALIGNMENT_CENTER, sz.x)


func _draw_notes(sz: Vector2, now: float) -> void:
	var y := sz.y - 190.0
	for n in notes.duplicate():
		var age: float = now - n.born
		if age > 3.0:
			notes.erase(n)
			continue
		var al := clampf(3.0 - age, 0, 1)
		var tx := 30.0
		if draw_icon(n.get("icon", ""), Rect2(26, y - 20, 26, 26), Color(1, 1, 1, al)):
			tx = 58.0
		txt(Vector2(tx, y), n.text, 16, Color(n.color.r, n.color.g, n.color.b, al))
		y -= 22


func _draw_end(sz: Vector2, p: Actor) -> void:
	draw_rect(Rect2(Vector2.ZERO, sz), Color(0, 0, 0, 0.45))
	var won: bool = game.winner == p
	var band := Rect2(0, sz.y * 0.3, sz.x, 190)
	draw_rect(band, Color(0.95, 0.72, 0.15, 0.92) if won else Color(0.08, 0.1, 0.14, 0.9))
	txt(Vector2(0, band.position.y + 88), "VICTORY!  LAST ONE STANDING" if won else "MATCH OVER", 64 if won else 56, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, sz.x)
	var line := "#1 of %d   ·   %d eliminations" % [game.actors.size(), p.kills] if won else "You placed #%d   ·   %d eliminations   ·   %s won" % [p.placement, p.kills, game.winner.display_name if game.winner else "Nobody"]
	txt(Vector2(0, band.position.y + 140), line, 26, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, sz.x)
