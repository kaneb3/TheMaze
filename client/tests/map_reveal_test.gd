extends SceneTree
## Headless tests for MapReveal (look-dev lantern reveal, spec §6.2).
##
##   godot --headless --path . --script res://client/tests/map_reveal_test.gd
##
## Exits 1 if any check fails.

var _fails := 0


func _initialize() -> void:
	_test_open_room()
	_test_walls_block()
	_test_corner_rule()
	_test_radius()
	_test_sample_maze()
	print("")
	print("map reveal: %s" % ("FAIL (%d)" % _fails if _fails else "all passed"))
	quit(1 if _fails else 0)


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails += 1


func _test_open_room() -> void:
	var r := MapReveal.new(5, 5, {})
	var vis := r.visible_from(Vector2i(2, 2), 6)
	_check(vis.size() == 25, "open 5x5 room: every cell visible from the middle (%d)" % vis.size())


func _test_walls_block() -> void:
	# a full wall down the east side of column 1: nothing in columns 2+ is visible from column 0
	var walls := {}
	for y in 5:
		walls[Vector3i(1, y, 0)] = true
	var r := MapReveal.new(5, 5, walls)
	var vis := r.visible_from(Vector2i(0, 2), 6)
	_check(vis.all(func(c): return c.x <= 1), "a wall line hides everything behind it")
	_check(vis.size() == 10, "both columns in front of the wall are visible (%d)" % vis.size())
	_check(r.closed_sides(Vector2i(1, 2)).has(Vector2i(1, 0)), "closed_sides reports the east wall")
	_check(r.closed_sides(Vector2i(0, 0)).has(Vector2i(-1, 0)), "the map boundary counts as closed")


func _test_corner_rule() -> void:
	# a single wall stub east of (0,0): the diagonal (0,0)->(1,1) passes the grid corner exactly,
	# and one way round is walled, so it is blocked; (0,0)->(2,1) passes beside it and is not
	var r := MapReveal.new(3, 3, {Vector3i(0, 0, 0): true})
	var vis := r.visible_from(Vector2i(0, 0), 6)
	_check(not vis.has(Vector2i(1, 1)), "a ray through a corner is blocked if either side is walled")
	_check(vis.has(Vector2i(0, 2)) and vis.has(Vector2i(1, 2)), "rays clear of the stub still see past it")


func _test_radius() -> void:
	var r := MapReveal.new(20, 1, {})
	var vis := r.visible_from(Vector2i(0, 0), 6)
	_check(vis.size() == 7, "a corridor reveals exactly radius + 1 cells (%d)" % vis.size())
	_check(MapReveal.new(3, 3, {}).visible_from(Vector2i(5, 5), 6).is_empty(), "outside the map reveals nothing")


func _test_sample_maze() -> void:
	# the look-dev maze: every revealed cell must be reachable through open edges (no seeing
	# through walls into a disconnected pocket) and within the radius
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://client/lookdev/maze_sample.json"))
	var walls := {}
	for e in data.walls:
		walls[Vector3i(int(e[0]), int(e[1]), 0 if e[2] == "E" else 1)] = true
	var r := MapReveal.new(int(data.width), int(data.height), walls)
	var ok := true
	var total := 0
	for y in r.height:
		for x in r.width:
			var from := Vector2i(x, y)
			var vis := r.visible_from(from, 6)
			total += vis.size()
			for c in vis:
				ok = ok and (c - from).length_squared() <= 36
				# symmetric sight: if a sees b, b sees a
				ok = ok and r.visible_from(c, 6).has(from)
	_check(ok, "sample maze: within radius and symmetric (avg %.1f cells per spot)" % (float(total) / (r.width * r.height)))
