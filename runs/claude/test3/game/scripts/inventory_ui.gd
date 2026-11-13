## Inventory screen (Tab): the five slots, ammo reserves, materials and health. The match keeps running behind it.
## Drag a slot onto another to swap, right-click or drag outside the panel to drop; on touch tap, then tap again.
extends Control

const PW := 860.0                         # panel size in logical pixels (the layout is designed for 1280x720)
const PH := 540.0
const SLOT := Vector2(150, 176)
const GAP := 12.0
const DRAG_MIN := 8.0

var game: Node
var ctl: Node
var font: Font
var is_open := false
var touch_mode := false
var sel := -1                             # touch: the slot picked for swap / drop
var drag_from := -1
var drag_start := Vector2.ZERO
var drag_pos := Vector2.ZERO
var dragging := false
var hover := -1
var mouse := Vector2.ZERO                 # in screen pixels
var _prev_mode := Input.MOUSE_MODE_VISIBLE


func setup(g: Node, controller: Node) -> void:
	game = g
	ctl = controller
	font = ThemeDB.fallback_font
	touch_mode = ctl.touch != null
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


# ----------------------------------------------------------------------------- open / close

func toggle() -> void:
	if is_open:
		close()
	else:
		open()


func open() -> void:
	## Refused while dead, after the match, or behind the pause menu.
	if is_open or not game.player.alive() or game.over or game.pause_menu.is_open:
		return
	is_open = true
	visible = true
	sel = -1
	drag_from = -1
	dragging = false
	_prev_mode = Input.mouse_mode
	if not touch_mode and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	game.player.in_fire = false


func close() -> void:
	if not is_open:
		return
	is_open = false
	visible = false
	dragging = false
	drag_from = -1
	if not touch_mode and _prev_mode == Input.MOUSE_MODE_CAPTURED and not game.over and not game.pause_menu.is_open:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# ----------------------------------------------------------------------------- actions

func swap_slots(i: int, j: int) -> void:
	## Swaps two slots; the hand keeps pointing at the same item.
	var a: Actor = game.player
	if i == j or i < 0 or j < 0 or i >= Items.SLOTS or j >= Items.SLOTS:
		return
	var t = a.slots[i]
	a.slots[i] = a.slots[j]
	a.slots[j] = t
	if a.using > 0.0 and (a.use_slot == i or a.use_slot == j):
		a.cancel_use()
	if a.active == i:
		a.active = j
	elif a.active == j:
		a.active = i
	a._refresh_held()


func drop(i: int) -> void:
	game.player.drop_slot(i)
	if sel == i:
		sel = -1


func _tap(i: int) -> void:
	## A click without a drag: select the slot (touch: first tap picks, second tap swaps).
	var a: Actor = game.player
	if touch_mode and sel >= 0 and sel != i:
		swap_slots(sel, i)
		sel = -1
		return
	if touch_mode:
		sel = -1 if sel == i else i
	if a.slots[i] != null:
		a.select(i)


# ----------------------------------------------------------------------------- input

func _scale() -> float:
	var sz := get_viewport_rect().size
	return clampf(minf(sz.x / 1280.0, sz.y / 720.0), 0.6, 2.5)


func _origin() -> Vector2:
	## Top-left of the panel in screen pixels.
	var sz := get_viewport_rect().size
	return (sz - Vector2(PW, PH) * _scale()) / 2.0


func _to_logical(p: Vector2) -> Vector2:
	return (p - _origin()) / _scale()


func slot_rect(i: int) -> Rect2:
	## Slot box in panel-local logical coordinates.
	var x0 := (PW - (SLOT.x * 5 + GAP * 4)) / 2.0
	return Rect2(x0 + i * (SLOT.x + GAP), 74, SLOT.x, SLOT.y)


func _slot_at(lp: Vector2) -> int:
	for i in Items.SLOTS:
		if slot_rect(i).has_point(lp):
			return i
	return -1


func _btn_rect(which: String) -> Rect2:
	return Rect2(PW - 174 if which == "close" else PW - 336, PH - 58, 150, 40)


func _input(e: InputEvent) -> void:
	if ctl.demo:
		return
	if e is InputEventKey and e.pressed and not e.echo:
		if e.is_action_pressed("inventory"):               # Tab by default; follows a rebind in Settings
			toggle()
			get_viewport().set_input_as_handled()
		elif is_open and e.physical_keycode == KEY_ESCAPE:
			close()
			get_viewport().set_input_as_handled()
		return
	if not is_open:
		return
	if e is InputEventMouseMotion:
		press_move(e.position)
		get_viewport().set_input_as_handled()
	elif e is InputEventMouseButton:
		if e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				press_down(e.position)
			else:
				press_up(e.position)
		elif e.button_index == MOUSE_BUTTON_RIGHT and e.pressed:
			var i := _slot_at(_to_logical(e.position))
			if i >= 0:
				drop(i)
		get_viewport().set_input_as_handled()


func press_down(p: Vector2) -> void:
	## Left button / finger down at screen position p.
	mouse = p
	var lp := _to_logical(p)
	if touch_mode:
		if _btn_rect("close").has_point(lp):
			close()
			return
		if _btn_rect("drop").has_point(lp):
			if sel >= 0:
				drop(sel)
			return
	var i := _slot_at(lp)
	if i >= 0:
		drag_from = i
		drag_start = p
		drag_pos = p
		dragging = false


func press_move(p: Vector2) -> void:
	mouse = p
	hover = _slot_at(_to_logical(p))
	if drag_from >= 0:
		drag_pos = p
		if p.distance_to(drag_start) > DRAG_MIN * _scale():
			dragging = true


func press_up(p: Vector2) -> void:
	## Left button / finger up: finish a swap, a drop or a plain click.
	mouse = p
	if drag_from < 0:
		return
	var from := drag_from
	drag_from = -1
	var lp := _to_logical(p)
	if not dragging:
		_tap(from)
		return
	dragging = false
	var to := _slot_at(lp)
	if to >= 0:
		swap_slots(from, to)
	elif not Rect2(Vector2.ZERO, Vector2(PW, PH)).has_point(lp):
		drop(from)


func _process(_d: float) -> void:
	if not is_open:
		return
	var a: Actor = game.player
	if not a.alive() or game.over:
		close()
		return
	size = get_viewport_rect().size
	if not touch_mode:
		mouse = get_viewport().get_mouse_position()
		if drag_from < 0:
			hover = _slot_at(_to_logical(mouse))
	queue_redraw()


# ----------------------------------------------------------------------------- drawing

func txt(pos: Vector2, s: String, size := 18, col := Color.WHITE, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	draw_string(font, pos + Vector2(1.5, 1.5), s, align, width, size, Color(0, 0, 0, 0.75 * col.a))
	draw_string(font, pos, s, align, width, size, col)


func _icon(name: String, r: Rect2) -> bool:
	var t: Texture2D = game.hud.icon(name)
	if t == null:
		return false
	draw_texture_rect(t, r, false)
	return true


func _draw() -> void:
	if not is_open:
		return
	var sz := get_viewport_rect().size
	var k := _scale()
	var a: Actor = game.player
	draw_rect(Rect2(Vector2.ZERO, sz), Color(0, 0, 0, 0.45))
	draw_set_transform(_origin(), 0.0, Vector2(k, k))
	draw_rect(Rect2(0, 0, PW, PH), Color(0.05, 0.07, 0.1, 0.9))
	draw_rect(Rect2(0, 0, PW, PH), Color(1, 1, 1, 0.35), false, 2.0)
	txt(Vector2(24, 44), "INVENTORY", 30, Color(1.0, 0.9, 0.5))
	var hint := "Drag to swap  ·  right-click or drag out to drop  ·  Tab / Esc to close" if not touch_mode else "Tap a slot, then tap another to swap"
	txt(Vector2(0, 42), hint, 14, Color(0.75, 0.8, 0.86), HORIZONTAL_ALIGNMENT_RIGHT, PW - 24)
	for i in Items.SLOTS:
		_draw_slot(i, a)
	_draw_reserves(a)
	_draw_bars(a)
	if touch_mode:
		_draw_button("drop", "DROP", sel >= 0 and a.slots[sel] != null)
		_draw_button("close", "CLOSE", true)
	if dragging and drag_from >= 0 and a.slots[drag_from] != null:
		var lp := _to_logical(drag_pos)
		var it: Dictionary = a.slots[drag_from]
		var rc: Color = Items.RARITY_COLORS[it.rarity]
		var r := Rect2(lp - Vector2(48, 48), Vector2(96, 96))
		draw_rect(r, Color(rc.r * 0.55, rc.g * 0.55, rc.b * 0.55, 0.9))
		draw_rect(r, Color(1, 1, 1, 0.9), false, 2.0)
		if not _icon(it.id, Rect2(r.position + Vector2(8, 8), Vector2(80, 80))):
			txt(r.position + Vector2(0, 54), Items.def(it).name, 13, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 96)
		if not Rect2(Vector2.ZERO, Vector2(PW, PH)).has_point(lp):
			txt(lp + Vector2(-60, 70), "DROP", 18, Color(1.0, 0.45, 0.35), HORIZONTAL_ALIGNMENT_CENTER, 120)
	elif hover >= 0 and a.slots[hover] != null and not touch_mode:
		_draw_tooltip(a.slots[hover], _to_logical(mouse))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_slot(i: int, a: Actor) -> void:
	var r := slot_rect(i)
	var it = a.slots[i]
	var col := Color(0.08, 0.1, 0.14, 0.75)
	if it != null:
		var rc: Color = Items.RARITY_COLORS[it.rarity]
		col = Color(rc.r * 0.55, rc.g * 0.55, rc.b * 0.55, 0.9)
	draw_rect(r, col)
	var act: bool = a.active == i
	var picked: bool = sel == i or (dragging and drag_from == i)
	var edge := Color(1, 1, 1, 0.95) if act else Color(1, 1, 1, 0.25)
	if hover == i and not act:
		edge = Color(1, 1, 1, 0.6)
	draw_rect(r, Color(1.0, 0.85, 0.3) if picked else edge, false, 3.0 if (act or picked) else 1.5)
	txt(r.position + Vector2(8, 20), str(i + 1), 15, Color(1, 1, 1, 0.8))
	if it == null:
		txt(r.position + Vector2(0, 100), "empty", 15, Color(1, 1, 1, 0.3), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		return
	var d: Dictionary = Items.def(it)
	var rc2: Color = Items.RARITY_COLORS[it.rarity]
	var fa := 0.35 if (dragging and drag_from == i) else 1.0
	var ir := Rect2(r.position + Vector2((r.size.x - 84) / 2, 16), Vector2(84, 84))
	if not _icon(it.id, ir):
		txt(r.position + Vector2(0, 62), d.name, 14, Color(1, 1, 1, fa), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	txt(r.position + Vector2(0, 122), d.name, 16 if d.name.length() < 16 else 11, Color(1, 1, 1, fa), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	txt(r.position + Vector2(0, 140), Items.RARITY_NAMES[it.rarity], 12, Color(rc2.r, rc2.g, rc2.b, fa), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	var line := ""
	if d.kind == "weapon" and Items.infinite_ammo(it):
		line = "\u221e   ·   %.1f s cooldown" % d.cooldown        # web shooters and the grasp: a cooldown instead of ammo
	elif d.kind == "weapon":
		line = "%d / %d   ·   dmg %d" % [it.loaded, d.mag, int(round(Items.damage(it)))]
	elif d.kind == "throwable":
		line = "x%d   ·   dmg %d" % [it.count, int(d.damage)]
	else:
		line = "x%d" % it.count
	txt(r.position + Vector2(0, 160), line, 13, Color(0.92, 0.95, 1.0, fa), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)


func _chip(r: Rect2, icon_name: String, label: String, n: int, col: Color) -> void:
	draw_rect(r, Color(0.08, 0.1, 0.14, 0.75))
	draw_rect(r, Color(1, 1, 1, 0.2), false, 1.5)
	if not _icon(icon_name, Rect2(r.position + Vector2(6, 6), Vector2(30, 30))):
		draw_rect(Rect2(r.position + Vector2(10, 10), Vector2(22, 22)), col)
	txt(r.position + Vector2(0, 30), str(n), 20, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 8)
	txt(r.position + Vector2(8, 54), label, 12, col)


func _draw_reserves(a: Actor) -> void:
	var y := 276.0
	var x := 24.0
	txt(Vector2(x, y), "AMMO", 14, Color(0.75, 0.8, 0.86))
	for t in Items.AMMO_TYPES:
		_chip(Rect2(x, y + 10, 84, 62), "ammo_" + t, String(t).capitalize(), int(a.ammo[t]), Items.AMMO_COLORS[t])
		x += 89.0
	x += 14.0
	txt(Vector2(x, y), "MATERIALS", 14, Color(0.75, 0.8, 0.86))
	for m in Structures.MATS:
		_chip(Rect2(x, y + 10, 86, 62), "mat_" + m, Items.MAT_NAMES[m], int(a.mats[m]), Items.MAT_COLORS[m])
		x += 91.0
	_chip(Rect2(x, y + 10, 86, 62), "mat_gold", "Gold", a.gold, Color(1.0, 0.8, 0.25))


func _bar(r: Rect2, icon_name: String, label: String, v: float, back: Color, fill: Color) -> void:
	draw_rect(r, back)
	draw_rect(r, Color(1, 1, 1, 0.2), false, 1.5)
	draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(v / 100.0, 0, 1), r.size.y)), fill)
	_icon(icon_name, Rect2(r.position + Vector2(-34, -2), Vector2(28, 28)))
	txt(r.position + Vector2(10, r.size.y - 7), label, 13, Color(0.95, 1, 0.95))
	txt(r.position + Vector2(0, r.size.y - 6), "%d / 100" % int(ceil(v)), 17, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 10)


func _draw_bars(a: Actor) -> void:
	var w := 370.0
	_bar(Rect2(60, 382, w, 26), "health", "HEALTH", a.hp, Color(0.12, 0.18, 0.12, 0.9), Color(0.3, 0.82, 0.3) if a.hp > 30.0 else Color(0.9, 0.3, 0.2))
	_bar(Rect2(PW - 24 - w, 382, w, 26), "shield", "SHIELD", a.shield, Color(0.1, 0.14, 0.22, 0.9), Color(0.25, 0.6, 1.0))
	txt(Vector2(24, 450), a.display_name, 16, Color(0.9, 0.92, 0.95))
	var held = a.item()
	var hs := "Holding: Pickaxe" if held == null else "Holding: " + Items.label(held)
	txt(Vector2(24, 472), hs, 14, Color(0.75, 0.8, 0.86) if held == null else Items.RARITY_COLORS[held.rarity])


func _draw_button(which: String, label: String, enabled: bool) -> void:
	var r := _btn_rect(which)
	draw_rect(r, Color(0.1, 0.25, 0.45, 0.85) if enabled else Color(0.08, 0.1, 0.14, 0.7))
	draw_rect(r, Color(1, 1, 1, 0.6 if enabled else 0.25), false, 2.0)
	txt(Vector2(r.position.x, r.position.y + 27), label, 18, Color(1, 1, 1, 1.0 if enabled else 0.4), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)


func tip_lines(it: Dictionary) -> Array:
	## Tooltip text lines for an item: [text, colour] pairs.
	var d: Dictionary = Items.def(it)
	var L: Array = []
	var dim := Color(0.85, 0.88, 0.92)
	match d.kind:
		"weapon" when Items.infinite_ammo(it):
			L.append([{"web_shooters": "Shoots a web to anything within 70 m and swings you on it",
					"ravage_grasp": "Lash a tendril 30 m: yank and slam an enemy (60 damage, stun), or pull yourself to a surface"}.get(it.id, ""), Color(1.0, 0.8, 0.6)])
			L.append(["No ammo   Cooldown %.1f s" % d.cooldown, dim])
			L.append(["Mythic: dropped by a boss, cannot be upgraded", Items.RARITY_COLORS[5]])
		"weapon":
			var pel := (" x %d pellets" % d.pellets) if d.pellets > 1 else ""
			L.append(["Damage %d%s" % [int(round(Items.damage(it))), pel], dim])
			L.append(["Fire rate %.1f / s%s" % [d.rate, "  (auto)" if d.get("auto", false) else ""], dim])
			L.append(["Magazine %d / %d   %s ammo" % [it.loaded, d.mag, d.ammo], Items.AMMO_COLORS[d.ammo]])
			L.append(["Reload %.1f s   Range %d m" % [Items.reload_time(it), int(d.range)], dim])
			if d.get("mythic", false):
				L.append([{"charge_shotgun": "Hold to charge: up to 2x damage and a tight spread",
						"shockwave_launcher": "Orb bursts into a shockwave that launches players and wrecks builds"}.get(it.id, "Mythic"), Color(1.0, 0.8, 0.6)])
		"throwable":
			L.append(["Damage %d, radius %.1f m" % [int(d.damage), d.radius], dim])
		"heal", "shield":
			var what := "health" if d.kind == "heal" else "shield"
			L.append(["Restores %d %s (up to %d)" % [int(d.amount), what, int(d.cap)], dim])
			if d.has("shield_amount"):
				L.append(["and %d shield (up to %d)" % [int(d.shield_amount), int(d.shield_cap)], dim])
			L.append(["Takes %.1f s to use" % d.use_time, dim])
		"launcher":
			L.append(["Place on the ground to launch", dim])
		"keycard":
			var lair: String = {"weaver": "Frostpeak", "ravage": "Sandbar Depot", "tinker": "Gearworks Yard"}.get(d.vault, "")
			L.append(["Opens the vault at %s, once" % lair, d.color])
			L.append(["Walk up to the vault door and press E", dim])
	if d.has("stack"):
		L.append(["Stack %d / %d" % [it.count, d.stack], dim])
	return L


func _draw_tooltip(it: Dictionary, lp: Vector2) -> void:
	var d: Dictionary = Items.def(it)
	var L := tip_lines(it)
	var w := 270.0
	var h := 50.0 + L.size() * 19.0
	var p := lp + Vector2(18, 18)
	if p.x + w > PW + 100:
		p.x = lp.x - w - 12
	if p.y + h > PH:
		p.y = PH - h
	draw_rect(Rect2(p, Vector2(w, h)), Color(0.03, 0.04, 0.07, 0.96))
	draw_rect(Rect2(p, Vector2(w, h)), Items.RARITY_COLORS[it.rarity], false, 2.0)
	txt(p + Vector2(10, 22), Items.label(it), 16, Color.WHITE)
	txt(p + Vector2(10, 40), "%s  ·  %s" % [Items.RARITY_NAMES[it.rarity], String(d.kind).capitalize()], 12, Items.RARITY_COLORS[it.rarity])
	for i in L.size():
		txt(p + Vector2(10, 62 + i * 19), L[i][0], 13, L[i][1])
