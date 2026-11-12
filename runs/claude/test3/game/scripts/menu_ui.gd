## Shared look for every menu screen: a dark theme with an orange accent, built entirely in code.
class_name MenuUI
extends RefCounted

const ACCENT := Color(0.98, 0.62, 0.14)
const PANEL := Color(0.05, 0.07, 0.11, 0.9)
const TEXT := Color(0.93, 0.95, 0.98)
const DIM := Color(0.62, 0.68, 0.76)


static func box(bg: Color, border: Color = Color(0, 0, 0, 0), radius := 8, margin := 10.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(2 if border.a > 0.0 else 0)
	s.set_corner_radius_all(radius)
	s.content_margin_left = margin * 1.6
	s.content_margin_right = margin * 1.6
	s.content_margin_top = margin
	s.content_margin_bottom = margin
	return s


static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 20
	for c in ["Label", "CheckBox", "Button", "OptionButton"]:
		t.set_color("font_color", c, TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color(0.1, 0.1, 0.1))
	t.set_color("font_focus_color", "Button", Color.WHITE)
	t.set_stylebox("normal", "Button", box(Color(0.14, 0.18, 0.26, 0.95), Color(1, 1, 1, 0.12)))
	t.set_stylebox("hover", "Button", box(Color(0.22, 0.28, 0.4, 1.0), ACCENT))
	t.set_stylebox("pressed", "Button", box(ACCENT, ACCENT))
	t.set_stylebox("focus", "Button", box(Color(0, 0, 0, 0), ACCENT))
	t.set_stylebox("disabled", "Button", box(Color(0.1, 0.12, 0.16, 0.6)))
	for n in ["normal", "hover", "pressed", "focus", "disabled"]:
		t.set_stylebox(n, "OptionButton", t.get_stylebox(n, "Button"))
	t.set_stylebox("panel", "PanelContainer", box(PANEL, Color(1, 1, 1, 0.14), 14, 16.0))
	t.set_stylebox("panel", "TabContainer", box(Color(0, 0, 0, 0.25), Color(0, 0, 0, 0), 8, 10.0))
	t.set_stylebox("tab_selected", "TabContainer", box(ACCENT, ACCENT, 8, 8.0))
	t.set_stylebox("tab_unselected", "TabContainer", box(Color(0.14, 0.18, 0.26, 0.9), Color(0, 0, 0, 0), 8, 8.0))
	t.set_stylebox("tab_hovered", "TabContainer", box(Color(0.22, 0.28, 0.4), Color(0, 0, 0, 0), 8, 8.0))
	t.set_color("font_selected_color", "TabContainer", Color(0.08, 0.08, 0.08))
	t.set_color("font_unselected_color", "TabContainer", TEXT)
	t.set_color("font_hovered_color", "TabContainer", Color.WHITE)
	var sl := box(Color(1, 1, 1, 0.16), Color(0, 0, 0, 0), 4, 2.0)
	sl.content_margin_top = 4
	sl.content_margin_bottom = 4
	t.set_stylebox("slider", "HSlider", sl)
	t.set_stylebox("grabber_area", "HSlider", box(ACCENT, Color(0, 0, 0, 0), 4, 2.0))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(ACCENT.lightened(0.2), Color(0, 0, 0, 0), 4, 2.0))
	return t


static func label(text: String, size := 20, col := TEXT, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.horizontal_alignment = align
	return l


static func button(text: String, size := 24, min_size := Vector2(300, 56)) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.add_theme_font_size_override("font_size", size)
	b.focus_mode = Control.FOCUS_NONE
	return b


static func spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c
