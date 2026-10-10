class_name InkButton
extends Button
## A menu entry written in ink on parchment: no box, just the words. When it's highlighted (mouse
## over or keyboard focus, which are the same thing here) the ink turns a wetter red-brown and a
## calligraphic underline runs out from the middle, with a small diamond at each end.

const INK := Color(0.19, 0.10, 0.05)
const INK_LIT := Color(0.45, 0.10, 0.04)
const STROKE_STEPS := 28

var lit := 0.0:  # 0..1, animated
	set(v):
		lit = v
		_tint()
		queue_redraw()
var _tween: Tween


func _init(label := "") -> void:
	text = label
	flat = true
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	_tint()
	mouse_entered.connect(grab_focus)
	focus_entered.connect(_highlight.bind(true))
	focus_exited.connect(_highlight.bind(false))


func _highlight(on: bool) -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "lit", 1.0 if on else 0.0, 0.22 if on else 0.12) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _tint() -> void:
	var c := INK.lerp(INK_LIT, lit)
	for key in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
		add_theme_color_override(key, c)


## Horizontal span of the label's text inside the button.
func _text_span() -> Vector2:
	var w := get_theme_font("font").get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, get_theme_font_size("font_size")).x
	match alignment:
		HORIZONTAL_ALIGNMENT_LEFT:
			return Vector2(0.0, w)
		HORIZONTAL_ALIGNMENT_RIGHT:
			return Vector2(size.x - w, size.x)
	return Vector2((size.x - w) * 0.5, (size.x + w) * 0.5)


func _draw() -> void:
	if lit <= 0.01:
		return
	var span := _text_span()
	var mid := (span.x + span.y) * 0.5
	var half := (span.y - span.x) * 0.5 + 6.0
	var y := size.y * 0.5 + get_theme_font_size("font_size") * 0.42
	var c := INK_LIT
	c.a = minf(1.0, lit * 1.5)
	# a pen stroke: thin at the ends, swelling in the middle, with a lazy wave
	var prev := Vector2.ZERO
	for i in STROKE_STEPS + 1:
		var t := float(i) / STROKE_STEPS
		var x := mid + lerpf(-half, half, t) * lit
		var pt := Vector2(x, y + sin(t * TAU * 1.0 + 0.6) * 1.4)
		if i > 0:
			draw_line(prev, pt, c, lerpf(0.5, 2.2, sin(t * PI)), true)
		prev = pt
	# end diamonds
	for side in [-1.0, 1.0]:
		var at := Vector2(mid + side * (half + 9.0) * lit, y + 0.5)
		var r := 3.2 * lit
		draw_colored_polygon(PackedVector2Array([at + Vector2(-r, 0), at + Vector2(0, -r * 0.7),
			at + Vector2(r, 0), at + Vector2(0, r * 0.7)]), c)
