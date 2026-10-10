class_name MapReveal
extends RefCounted
## Which cells a light reveals (spec §6.1-6.2), for look-dev only: until the server exists (S1) the
## map is filled from the player's own lantern. The real client never decides this; it is told.
##
## A light at a cell reveals every cell within `radius` (Euclidean, cell centre to cell centre) that
## it can see: first a flood fill through open edges inside the Chebyshev window, then a grid DDA
## (Amanatides-Woo) ray from centre to centre, blocked by any closed edge it crosses. A ray through a
## grid corner is blocked if either way round the corner is walled.

var width := 0
var height := 0
var _walls := {}  # Vector3i(x, y, 0=E / 1=S) -> true for closed edges (look_dev.gd's format)


func _init(w: int, h: int, walls: Dictionary) -> void:
	width = w
	height = h
	_walls = walls


func inside(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < width and c.y < height


## Is the edge from cell `c` towards the neighbour `c + d` open? (d is one of the 4 unit steps)
func is_open(c: Vector2i, d: Vector2i) -> bool:
	if not inside(c) or not inside(c + d):
		return false
	if d.x == 1: return not _walls.has(Vector3i(c.x, c.y, 0))
	if d.x == -1: return not _walls.has(Vector3i(c.x - 1, c.y, 0))
	if d.y == 1: return not _walls.has(Vector3i(c.x, c.y, 1))
	return not _walls.has(Vector3i(c.x, c.y - 1, 1))


## The closed edges of a cell, as unit steps (for drawing its walls).
func closed_sides(c: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
		if not is_open(c, d):
			out.append(d)
	return out


## Cells a light at `from` reveals within `radius` cells.
func visible_from(from: Vector2i, radius: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not inside(from):
		return out
	var seen := {from: true}
	var queue: Array[Vector2i] = [from]
	var head := 0
	while head < queue.size():
		var c := queue[head]
		head += 1
		if c != from and (c - from).length_squared() > radius * radius:
			continue
		if c == from or _ray_clear(from, c):
			out.append(c)
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if seen.has(n) or absi(n.x - from.x) > radius or absi(n.y - from.y) > radius:
				continue
			if is_open(c, d):
				seen[n] = true
				queue.append(n)
	return out


func _ray_clear(a: Vector2i, b: Vector2i) -> bool:
	var dx := b.x - a.x
	var dy := b.y - a.y
	var sx := signi(dx)
	var sy := signi(dy)
	# parametric distance (0..1 along the ray) to the next vertical / horizontal grid line
	var t_dx := 1.0 / absf(dx) if dx != 0 else INF
	var t_dy := 1.0 / absf(dy) if dy != 0 else INF
	var t_x := 0.5 * t_dx
	var t_y := 0.5 * t_dy
	var c := a
	while c != b:
		if is_equal_approx(t_x, t_y):
			# through a corner: both ways round must be open
			var via_x := is_open(c, Vector2i(sx, 0)) and is_open(c + Vector2i(sx, 0), Vector2i(0, sy))
			var via_y := is_open(c, Vector2i(0, sy)) and is_open(c + Vector2i(0, sy), Vector2i(sx, 0))
			if not (via_x and via_y):
				return false
			c += Vector2i(sx, sy)
			t_x += t_dx
			t_y += t_dy
		elif t_x < t_y:
			if not is_open(c, Vector2i(sx, 0)):
				return false
			c.x += sx
			t_x += t_dx
		else:
			if not is_open(c, Vector2i(0, sy)):
				return false
			c.y += sy
			t_y += t_dy
	return true
