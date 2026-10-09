extends CharacterBody3D
## First-person controller with a hand-held lantern (look-dev version; the real one gets server
## prediction/reconciliation in S3). WASD + mouse, F toggles the lantern, Esc frees the mouse.
##
## The arm is animated procedurally so it never feels static: it trails the view when you turn,
## bobs in a figure-of-eight as you walk, breathes when idle, and the lantern hangs world-vertical
## from the fist as a damped pendulum driven by how the hand actually moves.

@export var walk_speed := 2.5  # spec §7 walkSpeed
@export var debug_fast_multiplier := 2.5  # Shift, look-dev only (the game has no sprint)
@export var mouse_sensitivity := 0.0022
@export var lantern_energy := 2.4

const EYE_HEIGHT := 1.65
const HAND_POS := Vector3(0.22, -0.02, -0.46)  # the fist, relative to the eye
const LANTERN_SCALE := 0.5
const LANTERN_CHAIN := 0.49
const LANTERN_FLAME := 0.098
const PENDULUM_LENGTH := 0.24  # pivot to the lantern's centre of mass
const PENDULUM_DAMPING := 1.8
const PENDULUM_LIMIT := 0.7

var _head: Node3D
var _camera: Camera3D
var _hand: Node3D  # rides on the camera; the arm and the lantern pivot hang off it
var _rig: Node3D  # lantern pivot at the fist; oriented in world space (gravity-down)
var _lantern: Node3D
var _arm: Node3D
var _light: OmniLight3D

var _time := 0.0
var _step_phase := 0.0
var _walk_amount := 0.0
var _look_accum := Vector2.ZERO
var _lag := Vector2.ZERO
var _swing := Vector2.ZERO  # x: forward/back (about local X), y: sideways (about local Z)
var _swing_vel := Vector2.ZERO
var _pivot_prev := Vector3.ZERO
var _pivot_vel := Vector3.ZERO
var _first_frame := true


func _ready() -> void:
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	var shape := CollisionShape3D.new()
	shape.shape = cap
	shape.position.y = 0.9
	add_child(shape)

	_head = Node3D.new()
	_head.name = "Head"
	_head.position.y = EYE_HEIGHT
	add_child(_head)
	_camera = Camera3D.new()
	_camera.name = "Camera3D"
	_camera.fov = 72.0
	_camera.near = 0.03
	_head.add_child(_camera)
	_camera.current = true

	_hand = Node3D.new()
	_hand.name = "Hand"
	_hand.position = HAND_POS
	_camera.add_child(_hand)

	_arm = (load("res://client/assets/ring1/fp_arm.glb") as PackedScene).instantiate()
	_hand.add_child(_arm)

	_rig = Node3D.new()
	_rig.name = "LanternRig"
	_hand.add_child(_rig)
	_lantern = (load("res://client/assets/ring1/lantern.glb") as PackedScene).instantiate()
	_lantern.scale = Vector3.ONE * LANTERN_SCALE
	_lantern.position = Vector3(0.0, -LANTERN_CHAIN * LANTERN_SCALE, 0.0)
	_rig.add_child(_lantern)

	_light = OmniLight3D.new()
	_light.name = "LanternLight"
	_light.light_color = Color(1.0, 0.68, 0.42)
	_light.light_energy = lantern_energy
	_light.omni_range = 11.0
	_light.omni_attenuation = 1.25
	_light.shadow_enabled = true
	_light.shadow_bias = 0.04
	_light.shadow_normal_bias = 1.5
	_light.light_volumetric_fog_energy = 0.12
	_light.light_size = 0.06
	_light.position = _lantern.position + Vector3(0.0, LANTERN_FLAME * LANTERN_SCALE, 0.0)
	_rig.add_child(_light)
	var fill := LanternLighting.rig(_lantern, _light, Vector3(0.0, LANTERN_FLAME, 0.0))
	fill.omni_range = 1.0  # also lights the glove from below
	fill.light_energy = 0.45
	for node in _arm.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		mi.layers = LanternLighting.LANTERN_LAYER  # lit by the soft fill, not blasted by the lantern
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var screenshot_run := false
	for arg in OS.get_cmdline_user_args():
		screenshot_run = screenshot_run or arg.begins_with("--shot=")
	if not screenshot_run:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var rel: Vector2 = event.relative
		rotate_y(-rel.x * mouse_sensitivity)
		_head.rotate_x(-rel.y * mouse_sensitivity)
		_head.rotation.x = clampf(_head.rotation.x, -1.45, 1.45)
		_look_accum += rel
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_ESCAPE:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			KEY_F:
				_light.visible = not _light.visible
				for mi in _lantern.find_children("Flame*", "MeshInstance3D", true, false):
					mi.visible = _light.visible


func _physics_process(delta: float) -> void:
	var input := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W): input.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S): input.y += 1.0
	if Input.is_physical_key_pressed(KEY_A): input.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D): input.x += 1.0
	var speed := walk_speed * (debug_fast_multiplier if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0)
	var dir := (transform.basis * Vector3(input.x, 0.0, input.y)).normalized()
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	if not is_on_floor():
		velocity.y -= 9.8 * delta
	move_and_slide()


func _process(delta: float) -> void:
	delta = minf(delta, 0.05)
	_time += delta
	var ground_speed := Vector2(velocity.x, velocity.z).length()

	# Walking: steps advance with distance; the amount eases in and out.
	_walk_amount = lerpf(_walk_amount, clampf(ground_speed / walk_speed, 0.0, 1.6), 1.0 - exp(-8.0 * delta))
	_step_phase += delta * ground_speed * 2.4
	var step := sin(_step_phase)
	_head.position.y = EYE_HEIGHT + absf(step) * 0.03 * _walk_amount - 0.015 * _walk_amount

	# Turning: the hand trails the view a little, then catches up.
	var look_rate := _look_accum / maxf(delta, 0.001)
	_look_accum = Vector2.ZERO
	var lag_target := (-look_rate * 0.000045).limit_length(0.09)
	_lag = _lag.lerp(lag_target, 1.0 - exp(-9.0 * delta))

	# Idle breathing, always present but subtle.
	var breathe := sin(_time * 1.35)
	var drift := Vector2(sin(_time * 0.53), sin(_time * 0.71 + 1.3))

	_hand.position = HAND_POS + Vector3(
		sin(_step_phase * 0.5) * 0.016 * _walk_amount + _lag.x * 0.35 + drift.x * 0.003,
		-absf(sin(_step_phase * 0.5)) * 0.014 * _walk_amount + _lag.y * 0.25 + breathe * 0.004,
		0.012 * _walk_amount)
	_hand.rotation = Vector3(
		_lag.y * 0.9 + breathe * 0.012 + step * 0.015 * _walk_amount,
		_lag.x * 1.1 + drift.y * 0.01,
		_lag.x * 0.5 + sin(_step_phase * 0.5) * 0.04 * _walk_amount)

	_swing_lantern(delta)


## The lantern hangs world-vertical from the fist and swings as a damped pendulum, driven by the
## fist's real acceleration (walking, stopping, turning, bobbing all feed it).
func _swing_lantern(delta: float) -> void:
	var pivot := _hand.global_position
	if _first_frame:
		_pivot_prev = pivot
		_first_frame = false
	var vel := (pivot - _pivot_prev) / delta
	var accel := (vel - _pivot_vel) / delta
	_pivot_prev = pivot
	_pivot_vel = vel
	var yaw_basis := Basis(Vector3.UP, global_rotation.y)
	var a := yaw_basis.inverse() * accel.limit_length(40.0)  # in the player's facing frame

	# theta'' = -(g/L) sin(theta) - c theta' + (pivot acceleration)/L
	var g_over_l := 9.8 / PENDULUM_LENGTH
	var drive := Vector2(a.z, -a.x) / PENDULUM_LENGTH
	_swing_vel += (-g_over_l * Vector2(sin(_swing.x), sin(_swing.y)) - PENDULUM_DAMPING * _swing_vel + drive) * delta
	_swing += _swing_vel * delta
	_swing = _swing.clamp(Vector2(-PENDULUM_LIMIT, -PENDULUM_LIMIT), Vector2(PENDULUM_LIMIT, PENDULUM_LIMIT))
	_rig.global_basis = yaw_basis * Basis.from_euler(Vector3(_swing.x, 0.0, _swing.y))
