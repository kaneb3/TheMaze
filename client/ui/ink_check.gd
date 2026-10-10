class_name InkCheck
extends InkButton
## An on/off option: the label on the left, a hand-ruled box on the right that gets an inked tick.

const BOX := 22.0

var _tick := 0.0:  # 0..1, how much of the tick has been drawn
	set(v):
		_tick = v
		queue_redraw()
var _tick_tween: Tween


func _init(label := "", on := false) -> void:
	super(label)
	toggle_mode = true
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	button_pressed = on
	_tick = 1.0 if on else 0.0
	custom_minimum_size = Vector2(0.0, BOX + 8.0)
	toggled.connect(_on_toggled)


func _on_toggled(on: bool) -> void:
	if _tick_tween:
		_tick_tween.kill()
	_tick_tween = create_tween()
	_tick_tween.tween_property(self, "_tick", 1.0 if on else 0.0, 0.2 if on else 0.1)


func _text_span() -> Vector2:
	var span := super()
	return Vector2(span.x, minf(span.y, size.x - BOX - 16.0))


func _draw() -> void:
	super()
	var c := INK.lerp(INK_LIT, lit)
	var o := Vector2(size.x - BOX - 2.0, (size.y - BOX) * 0.5)
	# four ruled sides, each slightly off true and overshooting at the corners like a quick pen box
	var corners := [o + Vector2(0.5, 0.8), o + Vector2(BOX + 0.6, -0.3), o + Vector2(BOX - 0.4, BOX + 0.7), o + Vector2(-0.6, BOX - 0.2)]
	for i in 4:
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % 4]
		var dir := (b - a).normalized()
		draw_line(a - dir * 1.5, b + dir * 1.0, c, 1.6, true)
	if _tick <= 0.0:
		return
	# the tick: a short down-stroke into a long up-stroke that runs out past the box
	var pts := [o + Vector2(3.5, BOX * 0.52), o + Vector2(BOX * 0.42, BOX - 3.0), o + Vector2(BOX + 5.0, -5.0)]
	var first := 0.3  # share of the drawing time spent on the short stroke
	var t1 := clampf(_tick / first, 0.0, 1.0)
	var t2 := clampf((_tick - first) / (1.0 - first), 0.0, 1.0)
	var ink := INK_LIT.lerp(INK, 0.4)
	draw_line(pts[0], pts[0].lerp(pts[1], t1), ink, 2.6, true)
	if t2 > 0.0:
		var steps := 10
		var prev: Vector2 = pts[1]
		for i in range(1, steps + 1):
			var t := float(i) / steps * t2
			var pt: Vector2 = pts[1].lerp(pts[2], t)
			draw_line(prev, pt, ink, lerpf(2.8, 0.8, t), true)  # the nib lifts as it flicks away
			prev = pt
