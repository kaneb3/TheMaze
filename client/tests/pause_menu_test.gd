extends SceneTree
## The Esc menu's flow, and how it gates the first-person controller:
##
##   godot --headless --path . --script res://client/tests/pause_menu_test.gd
##
## Esc opens it; Esc on a sub-page goes back to the main page; Esc on the main page closes it.
## While it's open the player doesn't walk; Settings.invert_y flips vertical look.
## Never writes the player's settings file. Exits 1 on failure.

var _fails := 0
var _menu: PauseMenu
var _player: CharacterBody3D


func _initialize() -> void:
	var world := Node3D.new()
	get_root().add_child(world)
	_player = CharacterBody3D.new()
	_player.set_script(load("res://client/player/fp_controller.gd"))
	world.add_child(_player)
	_menu = PauseMenu.new()
	world.add_child(_menu)
	_run.call_deferred()


func _run() -> void:
	var invert_was := Settings.invert_y
	await process_frame

	_esc()
	await process_frame
	_check(PauseMenu.is_open, "Esc opens the menu")
	_check(_menu._page == "main", "it opens on the main page")
	_menu._show_page("options")
	_esc()
	await process_frame
	_check(PauseMenu.is_open and _menu._page == "main", "Esc on Options goes back to the main page")
	_esc()
	await process_frame
	_check(not PauseMenu.is_open, "Esc on the main page closes it")

	# look: mouse down (+y) pitches the view down; inverted, it pitches up
	Settings.invert_y = false
	var down := _pitch_after_mouse(Vector2(0.0, 40.0))
	_check(down < 0.0, "mouse down looks down (pitch %.3f)" % down)
	Settings.invert_y = true
	var up := _pitch_after_mouse(Vector2(0.0, 40.0))
	_check(up > 0.0, "inverted: mouse down looks up (pitch %.3f)" % up)
	Settings.invert_y = false

	# W held: you stand still while the menu is up, and walk once it's closed
	_key(KEY_W, true)
	_menu.open()
	for i in 20:
		await physics_frame
	var held := Vector2(_player.velocity.x, _player.velocity.z).length()
	_check(held < 0.01, "menu open: W doesn't move you (speed %.2f)" % held)
	_menu.close()
	for i in 20:
		await physics_frame
	var walking := Vector2(_player.velocity.x, _player.velocity.z).length()
	_check(walking > 0.5, "menu closed: W walks (speed %.2f)" % walking)
	_key(KEY_W, false)

	Settings.invert_y = invert_was
	print("pause menu: %s" % ("OK" if _fails == 0 else "%d FAILED" % _fails))
	quit(1 if _fails > 0 else 0)


func _esc() -> void:
	var e := InputEventKey.new()
	e.keycode = KEY_ESCAPE
	e.physical_keycode = KEY_ESCAPE
	e.pressed = true
	_menu._unhandled_input(e)


## Feed one mouse movement to the controller and report the head's pitch.
func _pitch_after_mouse(rel: Vector2) -> float:
	var head: Node3D = _player.get_node("Head")
	head.rotation.x = 0.0
	_player._look(rel)
	return head.rotation.x


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
