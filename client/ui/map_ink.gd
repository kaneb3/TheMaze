class_name MapInk
extends Node2D
## Everything inked on the hand-held map, drawn into a SubViewport that map_parchment.gdshader lays
## over the parchment's face (spec §9.1, §11.4). Channels, not colours: R = iron-gall ink coverage,
## G = the gold of lantern-lit cells.
## The shader picks the actual colours, bleeds the ink into the paper and spreads it in.
##
## Explored cells: their walls in ink. Lit cells: a warm gold wash. Unexplored: blank parchment.
## "You are here": a trail of inked footprints with a small name ribbon (Marauder's Map style).

const CANVAS := Vector2(1536.0, 1152.0)  # the 40 x 30 cm sheet's face
const MAZE_RECT := Rect2(318.0, 214.0, 880.0, 880.0)  # the drawn maze area on the face
const ZOOMS: Array[float] = [1.0, 1.75, 2.75]
const FONT := "res://client/assets/fonts/IMFeENrm28P.ttf"
const FONT_ITALIC := "res://client/assets/fonts/IMFeENit28P.ttf"
const FONT_CAPS := "res://client/assets/fonts/IMFeENsc28P.ttf"
const INK := Color(1, 0, 0)
const GOLD := Color(0, 1, 0)
const FRESH_S := 1.2  # newly revealed cells bleed in over this long

var reveal: MapReveal  # walls and bounds of the area this map covers
var revealed := {}  # Vector2i -> time revealed (s)
var lit := {}  # Vector2i -> true: cells lit by a placed lantern or camp (gold where revealed)
var footprints: Array = []  # [Vector2 cell-space position, angle, side(-1/1)] oldest first
var player_pos := Vector2.ZERO  # cell space (1 = one cell), +y = south
var player_yaw := 0.0  # map angle the player faces (0 = north/up, clockwise)
var to_centre := Vector2(0, -1)  # direction to the Lighthouse, for the compass
var title := "The Labyrinth"
var subtitle := "the First Ring"
var zoom := 0
var now := 0.0

var _font: Font
var _italic: Font
var _caps: Font


func _ready() -> void:
	_font = load(FONT)
	_italic = load(FONT_ITALIC)
	_caps = load(FONT_CAPS)


## True while something is still animating (fresh cells), so the viewport must keep re-rendering.
func animating() -> bool:
	for t in revealed.values():
		if now - t < FRESH_S:
			return true
	return false


func _draw() -> void:
	_draw_face()


# ---------------------------------------------------------------------------------------------
# the inked face

func _draw_face() -> void:
	_border(Rect2(Vector2.ZERO, CANVAS), 44.0, 1.0)
	_text(_caps, title, Vector2(CANVAS.x * 0.5, 112.0), 66, 0.92)
	_text(_italic, subtitle, Vector2(CANVAS.x * 0.5, 154.0), 34, 0.8)
	_compass(Vector2(165.0, 850.0), 92.0)
	_legend(Vector2(1262.0, 330.0))
	if reveal == null:
		return
	var cell := MAZE_RECT.size.x / maxf(reveal.width, reveal.height) * ZOOMS[zoom]
	var origin := _maze_origin(cell)
	# lit cells first (gold underneath the ink), each with a soft halo
	for c in revealed:
		if lit.has(c):
			var r := _cell_rect(c, origin, cell)
			var k := _fresh(c)
			for i in 3:
				var grow := cell * (0.28 - i * 0.12)
				_clip_rect(r.grow(grow), Color(GOLD, 0.22 * k))
			_clip_rect(r.grow(-cell * 0.08), Color(GOLD, 0.55 * k))
	# walls of every explored cell (each edge once)
	var drawn := {}
	for c in revealed:
		var k := _fresh(c)
		for d in reveal.closed_sides(c):
			var key := Vector4i(c.x, c.y, d.x, d.y) if (d.x > 0 or d.y > 0) else Vector4i(c.x + d.x, c.y + d.y, -d.x, -d.y)
			if drawn.has(key):
				continue
			drawn[key] = true
			var a := origin + (Vector2(c) + Vector2(0.5, 0.5) + Vector2(d) * 0.5 + Vector2(-d.y, d.x) * 0.5) * cell
			var b := origin + (Vector2(c) + Vector2(0.5, 0.5) + Vector2(d) * 0.5 - Vector2(-d.y, d.x) * 0.5) * cell
			_ink_line(a, b, clampf(cell * 0.07, 4.0, 9.0), 0.88 * k, float(key.x * 31 + key.y * 7 + key.z * 3 + key.w))
	_footprints(origin, cell)


func _maze_origin(cell: float) -> Vector2:
	var full := Vector2(reveal.width, reveal.height) * cell
	var origin := MAZE_RECT.position + (MAZE_RECT.size - full) * 0.5
	if ZOOMS[zoom] > 1.0:  # keep the player in view, without scrolling past the drawn area
		origin = MAZE_RECT.get_center() - player_pos * cell
		origin = origin.clamp(MAZE_RECT.end - full, MAZE_RECT.position)
	return origin


func _cell_rect(c: Vector2i, origin: Vector2, cell: float) -> Rect2:
	return Rect2(origin + Vector2(c) * cell, Vector2(cell, cell))


func _fresh(c: Vector2i) -> float:
	return clampf((now - float(revealed[c])) / FRESH_S, 0.0, 1.0)


func _clip_rect(r: Rect2, col: Color) -> void:
	r = r.intersection(MAZE_RECT.grow(6.0))
	if r.has_area():
		draw_rect(r, col)


## A pen stroke: wobbles a little, swells and thins with the nib, rounded ends.
func _ink_line(a: Vector2, b: Vector2, w: float, alpha: float, seed: float) -> void:
	if alpha <= 0.01:
		return
	if not MAZE_RECT.grow(4.0).has_point(a) and not MAZE_RECT.grow(4.0).has_point(b):
		if not Rect2(a, Vector2.ZERO).expand(b).intersects(MAZE_RECT):
			return
	a = a.clamp(MAZE_RECT.position, MAZE_RECT.end)
	b = b.clamp(MAZE_RECT.position, MAZE_RECT.end)
	var n := maxi(2, int(a.distance_to(b) / 14.0))
	var side := (b - a).orthogonal().normalized()
	var pts := PackedVector2Array()
	for i in n + 1:
		var t := float(i) / n
		var wob := sin(seed * 1.7 + t * 9.0) * 0.8 + sin(seed * 3.1 + t * 23.0) * 0.45
		pts.append(a.lerp(b, t) + side * wob)
	var col := Color(INK, alpha)
	draw_polyline(pts, col, w * (0.9 + 0.2 * fposmod(sin(seed) * 43.7, 1.0)), true)
	draw_circle(a, w * 0.5, col, true, -1.0, true)
	draw_circle(b, w * 0.5, col, true, -1.0, true)


func _footprints(origin: Vector2, cell: float) -> void:
	var foot := clampf(cell * 0.2, 11.0, 26.0)  # exaggerated so they read at a glance
	var n := footprints.size()
	for i in n:
		var f: Array = footprints[i]
		var p: Vector2 = origin + (f[0] as Vector2) * cell
		if MAZE_RECT.has_point(p):
			_foot(p, f[1], foot, float(i + 1) / n * 0.85, f[2])
	# the standing pair, where you are now, facing your way
	var here := origin + player_pos * cell
	if not MAZE_RECT.has_point(here):
		return
	var side := Vector2(cos(player_yaw), sin(player_yaw)) * foot * 0.36
	_foot(here - side, player_yaw, foot, 0.95, -1)
	_foot(here + side, player_yaw, foot, 0.95, 1)
	# name ribbon, Marauder's style, up and to the right of the feet
	# (below the feet when they stand near the top edge, clear of the title)
	var below := here.y - MAZE_RECT.position.y < 70.0
	var at := here + Vector2(foot * 1.0, foot * 2.2 if below else -foot * 1.5)
	var label := "You"
	var size := 38
	var tw := _italic.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var box := Rect2(at - Vector2(10.0, 32.0), Vector2(tw + 20.0, 44.0))
	_ink_line_free(box.position, box.position + Vector2(box.size.x, 0.0), 2.4, 0.85)
	_ink_line_free(box.position + Vector2(0.0, box.size.y), box.end, 2.4, 0.85)
	_ink_line_free(box.position, box.position + Vector2(-9.0, box.size.y * 0.5), 2.4, 0.85)
	_ink_line_free(box.position + Vector2(-9.0, box.size.y * 0.5), box.position + Vector2(0.0, box.size.y), 2.4, 0.85)
	_ink_line_free(box.position + Vector2(box.size.x, 0.0), box.end + Vector2(9.0, -box.size.y * 0.5), 2.4, 0.85)
	_ink_line_free(box.end + Vector2(9.0, -box.size.y * 0.5), box.end, 2.4, 0.85)
	draw_string(_italic, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(INK, 0.95))


## One footprint: a sole and a heel, `ang` = direction of travel (0 = up, clockwise).
func _foot(p: Vector2, ang: float, size: float, alpha: float, side: int) -> void:
	var fwd := Vector2(sin(ang), -cos(ang))
	var right := Vector2(cos(ang), sin(ang))
	var toe_out := right * side * size * 0.06
	_ellipse(p + fwd * size * 0.18 + toe_out, size * 0.2, size * 0.32, ang + side * 0.12, Color(INK, alpha))
	_ellipse(p - fwd * size * 0.3, size * 0.15, size * 0.17, ang, Color(INK, alpha))


func _ellipse(c: Vector2, rx: float, ry: float, ang: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 16:
		var t := TAU * i / 16.0
		pts.append(c + Vector2(cos(t) * rx, sin(t) * ry).rotated(ang))
	draw_colored_polygon(pts, col)


func _ink_line_free(a: Vector2, b: Vector2, w: float, alpha: float) -> void:
	draw_line(a, b, Color(INK, alpha), w, true)


# ---------------------------------------------------------------------------------------------
# frame, lettering, compass, legend

func _border(r: Rect2, inset: float, alpha: float) -> void:
	var outer := r.grow(-inset)
	var inner := r.grow(-inset - 13.0)
	for rr in [outer, inner]:
		var w := 4.5 if rr == outer else 2.2
		var corners := [rr.position, Vector2(rr.end.x, rr.position.y), rr.end, Vector2(rr.position.x, rr.end.y)]
		for i in 4:
			_ink_line_any(corners[i], corners[(i + 1) % 4], w, alpha * 0.85, float(i) * 5.3 + w)
	# corner flourishes: small diamonds where the rules meet
	for c in [outer.position, Vector2(outer.end.x, outer.position.y), outer.end, Vector2(outer.position.x, outer.end.y)]:
		var d := 9.0
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -d), c + Vector2(d, 0), c + Vector2(0, d), c + Vector2(-d, 0)]), Color(INK, alpha * 0.85))


## Like _ink_line, without clipping to the maze.
func _ink_line_any(a: Vector2, b: Vector2, w: float, alpha: float, seed: float) -> void:
	var n := maxi(2, int(a.distance_to(b) / 18.0))
	var side := (b - a).orthogonal().normalized()
	var pts := PackedVector2Array()
	for i in n + 1:
		var t := float(i) / n
		pts.append(a.lerp(b, t) + side * (sin(seed * 1.3 + t * 11.0) * 0.9 + sin(seed * 2.9 + t * 31.0) * 0.4))
	draw_polyline(pts, Color(INK, alpha), w, true)


func _text(font: Font, s: String, centre: Vector2, size: int, alpha: float) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(font, centre - Vector2(w * 0.5, 0.0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(INK, alpha))


func _compass(c: Vector2, r: float) -> void:
	var col := Color(INK, 0.85)
	draw_arc(c, r, 0.0, TAU, 72, col, 2.5, true)
	draw_arc(c, r * 0.9, 0.0, TAU, 72, col, 1.4, true)
	for i in 32:  # degree ticks
		var a := TAU * i / 32.0
		var l := 0.08 if i % 4 == 0 else 0.04
		draw_line(c + Vector2(sin(a), -cos(a)) * r * 0.9, c + Vector2(sin(a), -cos(a)) * r * (0.9 - l), col, 1.4, true)
	for i in 8:  # eight-point star, the long points half filled (the old engravers' way)
		var a := TAU * i / 8.0
		var long := i % 2 == 0
		var tip := c + Vector2(sin(a), -cos(a)) * r * (0.82 if long else 0.5)
		var w := r * (0.13 if long else 0.1)
		var l := c + Vector2(sin(a - PI / 2), -cos(a - PI / 2)) * w
		var rr := c + Vector2(sin(a + PI / 2), -cos(a + PI / 2)) * w
		draw_colored_polygon(PackedVector2Array([c, tip, l]), col)
		draw_polyline(PackedVector2Array([c, tip, rr, c]), col, 1.6, true)
	draw_circle(c, r * 0.06, Color(INK, 0.0))
	_text(_caps, "N", c + Vector2(0.0, -r - 12.0), 36, 0.9)
	# the Lighthouse: an arrow off the rose towards the centre of the maze
	var dir := to_centre.normalized()
	var a0 := c + dir * r * 1.1
	var a1 := c + dir * r * 1.38
	_ink_line_any(a0, a1, 3.0, 0.85, 2.0)
	var side := dir.orthogonal()
	draw_colored_polygon(PackedVector2Array([a1 + dir * 16.0, a1 + side * 9.0, a1 - side * 9.0]), col)
	var lh := a1 + dir * 34.0 + Vector2(0.0, 14.0)
	_lighthouse(lh, 28.0)
	_text(_italic, "to the Light", lh + Vector2(0.0, 34.0), 24, 0.85)


func _lighthouse(base: Vector2, h: float) -> void:
	var col := Color(INK, 0.85)
	var bw := h * 0.32
	var tw := h * 0.2
	draw_polyline(PackedVector2Array([base + Vector2(-bw, 0), base + Vector2(-tw, -h), base + Vector2(tw, -h),
		base + Vector2(bw, 0), base + Vector2(-bw, 0)]), col, 2.0, true)
	draw_rect(Rect2(base + Vector2(-tw * 1.1, -h - h * 0.22), Vector2(tw * 2.2, h * 0.22)), col, false, 2.0)
	draw_colored_polygon(PackedVector2Array([base + Vector2(-tw * 1.3, -h * 1.22), base + Vector2(0, -h * 1.45),
		base + Vector2(tw * 1.3, -h * 1.22)]), col)
	for k in [0.33, 0.66]:  # bands
		var y: float = -h * k
		var half := lerpf(bw, tw, k)
		draw_line(base + Vector2(-half, y), base + Vector2(half, y), col, 1.6, true)


func _legend(at: Vector2) -> void:
	var size := 26
	var col := Color(INK, 0.85)
	_text(_caps, "Key", at + Vector2(80.0, 0.0), 32, 0.9)
	var y := at.y + 52.0
	# walked: an ink wall
	_ink_line_any(Vector2(at.x, y - 8.0), Vector2(at.x + 46.0, y - 8.0), 4.5, 0.85, 1.0)
	draw_string(_italic, Vector2(at.x + 60.0, y), "walked", HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
	y += 50.0
	draw_rect(Rect2(at.x + 4.0, y - 26.0, 38.0, 26.0), Color(GOLD, 0.6))
	draw_rect(Rect2(at.x - 2.0, y - 32.0, 50.0, 38.0), Color(GOLD, 0.2))
	draw_string(_italic, Vector2(at.x + 60.0, y), "lantern-lit", HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
	y += 50.0
	_foot(Vector2(at.x + 14.0, y - 10.0), 0.0, 22.0, 0.85, -1)
	_foot(Vector2(at.x + 30.0, y - 14.0), 0.0, 22.0, 0.85, 1)
	draw_string(_italic, Vector2(at.x + 60.0, y), "your steps", HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
