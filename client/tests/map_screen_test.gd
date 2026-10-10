extends SceneTree
## The hand-held map's controls and how it gates the first-person controller:
##
##   godot --headless --path . --script res://client/tests/map_screen_test.gd
##
## Tab brings it up (it pops out open, its creases settle, and the ink spreads in); Tab puts it away. Esc
## with the map up puts the map away and does NOT open the PauseMenu; the next Esc does. Tab does nothing while the menu is
## open. Reading slows the walk and stops sprinting. Reveals reach the ink. Exits 1 on failure.

var _fails := 0
var _menu: PauseMenu
var _player: CharacterBody3D
var _map: MapScreen


func _initialize() -> void:
	var world := Node3D.new()
	get_root().add_child(world)
	var floor := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200.0, 1.0, 200.0)
	shape.shape = box
	shape.position.y = -0.5
	floor.add_child(shape)
	world.add_child(floor)
	_player = CharacterBody3D.new()
	_player.set_script(load("res://client/player/fp_controller.gd"))
	world.add_child(_player)
	_menu = PauseMenu.new()  # added after the player, as look_dev does: it sees unhandled Esc first
	world.add_child(_menu)
	_run.call_deferred()


func _run() -> void:
	await process_frame
	_map = _player.map
	_check(_map != null and not _map.is_reading() and not _map.visible, "the map starts put away")

	# data: reveals reach the ink, once each
	_map.configure(MapReveal.new(4, 4, {}), Vector3.ZERO, 4.0)
	var cells: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0)]
	_map.add_revealed(cells)
	_map.add_revealed(cells)
	_check(_map.ink.revealed.size() == 2, "revealed cells reach the ink (%d)" % _map.ink.revealed.size())

	_press(KEY_TAB)
	await process_frame
	_check(_map.is_reading(), "Tab raises the map")
	await create_timer(MapScreen.RAISE_S + 2.2).timeout
	_check(_map._paper.max_bend() < deg_to_rad(3.0), "it comes out open and its creases settle (%.1f deg)" % rad_to_deg(_map._paper.max_bend()))
	_check(_map._spread > 0.0 and _map._fade == 1.0, "the ink spreads in (%.2f m)" % _map._spread)
	_check(_map.lift() > 0.99, "fully up: lift() = %.2f" % _map.lift())

	# reading: a slow walk, and Shift doesn't sprint
	_key(KEY_W, true)
	_key(KEY_SHIFT, true)
	for i in 90:
		await physics_frame
	var reading := Vector2(_player.velocity.x, _player.velocity.z).length()
	_check(reading > 0.5 and reading < Locomotion.WALK_SPEED * MapScreen.WALK_MULT + 0.05,
		"reading: a slow walk, no sprint (%.2f m/s)" % reading)
	_key(KEY_SHIFT, false)
	_key(KEY_W, false)

	# Esc puts the map away first; the menu stays shut
	_press(KEY_ESCAPE)
	await process_frame
	_check(not _map._want_open, "Esc puts the map away")
	_check(not PauseMenu.is_open, "...without opening the menu")
	await create_timer(1.6).timeout
	_check(not _map.is_reading() and not _map.visible, "it drops out of view")
	_press(KEY_ESCAPE)
	await process_frame
	_check(PauseMenu.is_open, "the next Esc opens the menu")
	_press(KEY_TAB)
	await process_frame
	_check(not _map._want_open, "Tab does nothing while the menu is open")
	_menu.close()
	await process_frame

	# Tab toggles both ways
	_press(KEY_TAB)
	await process_frame
	_press(KEY_TAB)
	await process_frame
	_check(not _map._want_open, "Tab again puts it away")

	print("map screen: %s" % ("OK" if _fails == 0 else "%d FAILED" % _fails))
	quit(1 if _fails > 0 else 0)


## A key press through the real input path (_input, then _unhandled_input), so the order between
## the map and the PauseMenu is what the game sees.
func _press(code: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = true
	get_root().push_input(e)


func _key(code: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = down
	Input.parse_input_event(e)


func _check(ok: bool, what: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		_fails += 1
