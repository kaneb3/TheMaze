extends CharacterBody3D
## First-person controller with a hand-held lantern (look-dev version; the real one gets server
## prediction/reconciliation in S3). WASD + mouse, F toggles the lantern, Esc frees the mouse.

@export var walk_speed := 2.5  # spec §7 walkSpeed
@export var debug_fast_multiplier := 2.5  # Shift, look-dev only (the game has no sprint)
@export var mouse_sensitivity := 0.0022
@export var lantern_energy := 2.4

const EYE_HEIGHT := 1.65
const LANTERN_SCALE := 0.62
const LANTERN_CHAIN := 0.49
const LANTERN_FLAME := 0.098

var _head: Node3D
var _camera: Camera3D
var _rig: Node3D
var _lantern: Node3D
var _arm: Node3D
var _light: OmniLight3D
var _bob := 0.0
var _sway := Vector2.ZERO
var _sway_vel := Vector2.ZERO
var _look_delta := Vector2.ZERO


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

	# The hand holds the chain; the lantern hangs below it, lower right of view.
	_rig = Node3D.new()
	_rig.name = "LanternRig"
	_rig.position = Vector3(0.30, -0.10, -0.62)
	_camera.add_child(_rig)
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

	# The gloved arm holds the chain at the rig's pivot; the lantern swings beneath the fist.
	_arm = (load("res://client/assets/ring1/fp_arm.glb") as PackedScene).instantiate()
	_arm.position = _rig.position
	_camera.add_child(_arm)
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
		_look_delta += rel
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

	# Head bob and a lantern that swings on its chain.
	var moving := Vector2(velocity.x, velocity.z).length()
	_bob += delta * moving * 3.2
	_head.position.y = EYE_HEIGHT + sin(_bob) * 0.025 * minf(moving, 1.0)
	var target := Vector2(-_look_delta.x * 0.004 + sin(_bob * 0.5) * 0.05 * minf(moving, 1.0), -input.y * 0.06)
	_look_delta = Vector2.ZERO
	_sway_vel += (target - _sway) * 40.0 * delta - _sway_vel * 6.0 * delta
	_sway += _sway_vel * delta
	_rig.rotation = Vector3(_sway.y, 0.0, _sway.x)
