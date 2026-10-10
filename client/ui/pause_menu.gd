class_name PauseMenu
extends CanvasLayer
## The Esc menu: a sheet of old parchment over the blurred game view, with Resume / Options /
## Leave the maze. Esc opens it, and Esc on a sub-page goes back a page.
##
## It doesn't pause the world: the game is online, so the maze carries on behind it. The player's
## input is cut off instead (fp_controller checks PauseMenu.is_open).

const FONT := "res://client/assets/fonts/IMFeENrm28P.ttf"
const FONT_ITALIC := "res://client/assets/fonts/IMFeENit28P.ttf"
const FONT_CAPS := "res://client/assets/fonts/IMFeENsc28P.ttf"
const SHEET := Vector2(440.0, 470.0)
const INK := InkButton.INK

static var is_open := false

var _root: Control
var _backdrop: ColorRect
var _sheet: ColorRect
var _pages := {}  # name -> VBoxContainer
var _page := ""
var _tween: Tween
var _blur := 0.0
var _italic: Font
var _caps: Font


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_italic = load(FONT_ITALIC)
	_caps = load(FONT_CAPS)

	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	var theme := Theme.new()
	theme.default_font = load(FONT)
	theme.default_font_size = 30
	theme.set_color("font_color", "Label", INK)
	_root.theme = theme
	add_child(_root)

	_backdrop = ColorRect.new()
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.material = ShaderMaterial.new()
	_backdrop.material.shader = load("res://client/ui/menu_backdrop.gdshader")
	_set_blur(0.0)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP  # clicks on the dimmed game do nothing
	_root.add_child(_backdrop)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)
	_sheet = ColorRect.new()
	_sheet.custom_minimum_size = SHEET
	_sheet.pivot_offset = SHEET * 0.5
	var paper := ShaderMaterial.new()
	paper.shader = load("res://client/ui/parchment.gdshader")
	paper.set_shader_parameter("sheet_size", SHEET)
	_sheet.material = paper
	center.add_child(_sheet)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 64)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 52)
	_sheet.add_child(margin)

	var main := _add_page(margin, "main", "Paused", "the lantern burns on")
	_add_button(main, "Resume", close)
	_add_button(main, "Options", _show_page.bind("options"))
	_add_button(main, "Leave the maze", _show_page.bind("leave"))
	_add_footer(main, "Esc to return")

	var options := _add_page(margin, "options", "Options", "")
	options.add_child(_caption("Controls"))
	var invert := InkCheck.new("Invert vertical look", Settings.invert_y)
	invert.add_theme_font_size_override("font_size", 26)
	invert.toggled.connect(func(on: bool) -> void:
		Settings.invert_y = on
		Settings.save())
	options.add_child(invert)
	_add_button(options, "Back", _show_page.bind("main"))
	_add_footer(options, "Esc to go back")

	var leave := _add_page(margin, "leave", "Leave the maze?", "")
	var note := _caption("You will return to the desktop.")
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	leave.add_child(note)
	_add_button(leave, "Stay", _show_page.bind("main"))
	_add_button(leave, "Leave", func() -> void: get_tree().quit())
	_add_footer(leave, "")

	_root.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	if not is_open:
		open()
	elif _page == "main":
		close()
	else:
		_show_page("main")


func open(page := "main") -> void:
	is_open = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_root.visible = true
	_show_page(page)
	if _tween:
		_tween.kill()
	_sheet.scale = Vector2.ONE * 0.94
	_sheet.modulate.a = 0.0
	_tween = create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_sheet, "scale", Vector2.ONE, 0.2)
	_tween.tween_property(_sheet, "modulate:a", 1.0, 0.14)
	_tween.tween_method(_set_blur, _blur, 1.0, 0.2)


func close() -> void:
	is_open = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	get_viewport().gui_release_focus()
	if _tween:
		_tween.kill()
	_tween = create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_tween.tween_property(_sheet, "scale", Vector2.ONE * 0.96, 0.12)
	_tween.tween_property(_sheet, "modulate:a", 0.0, 0.12)
	_tween.tween_method(_set_blur, _blur, 0.0, 0.12)
	_tween.chain().tween_callback(func() -> void: _root.visible = false)


func _set_blur(v: float) -> void:
	_blur = v
	(_backdrop.material as ShaderMaterial).set_shader_parameter("amount", v)


## Swap the visible page; its lines ink in one after another, and the first entry takes focus.
func _show_page(page: String) -> void:
	_page = page
	for key in _pages:
		_pages[key].visible = key == page
	var lines: Array = _pages[page].get_children()
	for i in lines.size():
		var line: Control = lines[i]
		line.modulate.a = 0.0
		var t := line.create_tween()
		t.tween_interval(0.04 + i * 0.035)
		t.tween_property(line, "modulate:a", 1.0, 0.16)
	for line in lines:
		if line is InkButton:
			line.grab_focus()
			break


func _add_page(parent: Control, key: String, title: String, subtitle: String) -> VBoxContainer:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 6)
	page.visible = false
	parent.add_child(page)
	_pages[key] = page
	var heading := Label.new()
	heading.text = title
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_override("font", _caps)
	heading.add_theme_font_size_override("font_size", 46 if title.length() < 12 else 36)
	page.add_child(heading)
	if subtitle != "":
		var sub := _caption(subtitle)
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		page.add_child(sub)
	page.add_child(InkRule.new())
	var gap := Control.new()
	gap.custom_minimum_size.y = 18.0
	page.add_child(gap)
	return page


func _add_button(page: VBoxContainer, label: String, action: Callable) -> InkButton:
	var b := InkButton.new(label)
	b.pressed.connect(action)
	page.add_child(b)
	return b


## Pushes the hint to the bottom of the sheet.
func _add_footer(page: VBoxContainer, hint: String) -> void:
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(fill)
	var l := _caption(hint)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 18)
	l.modulate.a = 0.7
	page.add_child(l)


func _caption(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _italic)
	l.add_theme_font_size_override("font_size", 21)
	l.add_theme_color_override("font_color", INK.lerp(Color(0.45, 0.33, 0.2), 0.45))
	return l


## A pen flourish under a heading: a tapering rule either side of a small lozenge.
class InkRule:
	extends Control

	func _init() -> void:
		custom_minimum_size = Vector2(0.0, 14.0)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var mid := Vector2(size.x * 0.5, size.y * 0.5)
		var reach := minf(size.x * 0.42, 150.0)
		for side in [-1.0, 1.0]:
			var prev := mid + Vector2(side * 10.0, 0.0)
			for i in range(1, 21):
				var t := i / 20.0
				var pt := mid + Vector2(side * lerpf(10.0, reach, t), sin(t * PI * 2.0) * 1.2 * side)
				draw_line(prev, pt, PauseMenu.INK, lerpf(2.0, 0.4, t), true)
				prev = pt
		var r := 5.0
		draw_colored_polygon(PackedVector2Array([mid + Vector2(-r, 0), mid + Vector2(0, -r * 0.75),
			mid + Vector2(r, 0), mid + Vector2(0, r * 0.75)]), PauseMenu.INK)
