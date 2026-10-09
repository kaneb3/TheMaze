extends CharacterBody3D
## First-person controller with a hand-held lantern (look-dev version; the real one gets server
## prediction/reconciliation in S3). WASD + mouse, F toggles the lantern, Esc frees the mouse.
##
## Motion is a weighty physical model (LanternMotion): an inertial arm carrying a hand-damped
## pendulum, with a real stride cadence and a braced run pose. See lantern_motion.gd.

@export var walk_speed := 2.5  # spec §7 walkSpeed
@export var debug_fast_multiplier := 2.5  # Shift, look-dev only (the game has no sprint)
@export var mouse_sensitivity := 0.0022
@export var lantern_energy := 2.4

const EYE_HEIGHT := 1.65
# Left hand, lower-left of view (Amnesia / Pathologic framing). Values come from the Blender layout in
# art/characters.blend (HandWork scene, art/scripts/fp_viewmodel.py): the arm model's origin is the grip.
const HAND_POS := Vector3(-0.28, -0.04, -0.39)  # the grip, relative to the eye
const LANTERN_SCALE := 0.5
const LANTERN_HANG := -0.2907  # lantern origin below the grip (through the carrying ring)
const LANTERN_FLAME := 0.098
const RING_RADIUS := 0.045
const RING_NORMAL := Vector3(0.3388, 0.0, 0.9409)  # ring plane faces mostly towards the eye
const VIEWMODEL_LAYER := 1 << 2  # render layer 3: lit by the viewmodel fill only
const ACCEL := 4.5  # m/s^2: start/stop ramps (people accelerate ~1-4 m/s^2; instant changes kick the lantern)
const SUBSTEP := 1.0 / 240.0

var _head: Node3D
var _camera: Camera3D
var _hand: Node3D  # rides on the camera; the arm and the lantern pivot hang off it
var _rig: Node3D  # lantern pivot at the fist; oriented in world space (gravity-down)
var _lantern: Node3D
var _arm: Node3D
var _light: OmniLight3D

var _time := 0.0
var _look_accum := Vector2.ZERO  # mouse pixels since the last frame
var _motion: LanternMotion
var _sub_accum := 0.0

# Living grip (blend shapes on the hand): >0 squeezes, <0 relaxes.
var _hand_mesh: MeshInstance3D
var _squeeze_idx := -1
var _relax_idx := -1
var _grip := 0.0
var _grip_vel := 0.0
var _still_time := 0.0
var _regrip_timer := 5.0
var _regrip_pulse := 0.0
var _prev_walk := 0.0
var _forced_grip := INF  # look-dev: --grip=<-1..1> pins the grip for screenshots
var _autopilot := false  # look-dev: --autopilot runs a fixed walk/stop/turn/sprint sequence
var _log_path := ""      # look-dev: --log=<csv> records the lantern swing per frame
var _log: PackedStringArray = []
var _auto_t := 0.0
var _auto_yaw_done := 0.0
var _rng := RandomNumberGenerator.new()


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
	_motion = LanternMotion.new(HAND_POS)

	_arm = Node3D.new()
	_arm.name = "Arm"
	_hand.add_child(_arm)
	for part in ["fp_hand", "fp_gear", "fp_sleeve"]:
		_arm.add_child((load("res://client/assets/ring1/%s.glb" % part) as PackedScene).instantiate())
	for node in _arm.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh.get_blend_shape_count() > 0:
			_hand_mesh = mi
			_squeeze_idx = mi.find_blend_shape_by_name("squeeze")
			_relax_idx = mi.find_blend_shape_by_name("relax")

	_rig = Node3D.new()
	_rig.name = "LanternRig"
	_hand.add_child(_rig)
	# One dark-iron carrying ring hooked by the fingers; the lantern hangs from it.
	var ring := MeshInstance3D.new()
	ring.name = "CarryRing"
	var torus := TorusMesh.new()
	torus.inner_radius = RING_RADIUS - 0.0038
	torus.outer_radius = RING_RADIUS + 0.0038
	torus.rings = 48
	torus.ring_segments = 10
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.09, 0.075, 0.06)
	iron.metallic = 1.0
	iron.roughness = 0.32
	torus.material = iron
	ring.mesh = torus
	ring.position = Vector3(0.0, -RING_RADIUS + 0.004, 0.0)
	ring.quaternion = Quaternion(Vector3.UP, RING_NORMAL.normalized())  # torus axis -> ring normal (plane stands vertical)
	_rig.add_child(ring)
	_lantern = (load("res://client/assets/ring1/fp_lantern.glb") as PackedScene).instantiate()
	_lantern.scale = Vector3.ONE * LANTERN_SCALE
	_lantern.position = Vector3(0.0, LANTERN_HANG, 0.0)
	_lantern.rotation.y = deg_to_rad(25.0)
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
	fill.omni_range = 1.0  # also lights the glove, ring and cuff from below
	fill.light_energy = 0.6
	fill.light_color = Color(1.0, 0.6, 0.3)
	# The flame hangs ~27 cm below the fist, so the lantern light can warm the glove's underside
	# directly; the arm just must not cast shadows over the view.
	for node in _arm.find_children("*", "MeshInstance3D", true, false) + [ring]:
		var mi := node as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.layers |= VIEWMODEL_LAYER

	# Viewmodel fill: a soft warm light that touches only the arm (standard first-person practice) so
	# the glove's leather, seams and knuckles stay readable without brightening the world.
	var vm_fill := OmniLight3D.new()
	vm_fill.name = "ViewmodelFill"
	vm_fill.light_color = Color(1.0, 0.8, 0.62)
	vm_fill.light_energy = 0.4
	vm_fill.omni_range = 0.9
	vm_fill.light_cull_mask = VIEWMODEL_LAYER
	vm_fill.shadow_enabled = false
	vm_fill.light_volumetric_fog_energy = 0.0
	vm_fill.position = Vector3(0.12, 0.22, 0.05)  # above and to the right of the fist
	_hand.add_child(vm_fill)

	var screenshot_run := false
	for arg in OS.get_cmdline_user_args():
		screenshot_run = screenshot_run or arg.begins_with("--shot=")
		if arg.begins_with("--grip="):
			_forced_grip = float(arg.substr(7))
		if arg == "--autopilot":
			_autopilot = true
		if arg.begins_with("--log="):
			_log_path = arg.substr(6)
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
	var fast := Input.is_physical_key_pressed(KEY_SHIFT)
	if _autopilot:
		var a := _autopilot_step(delta)
		input = a[0]
		fast = a[1]
	var speed := walk_speed * (debug_fast_multiplier if fast else 1.0)
	var dir := (transform.basis * Vector3(input.x, 0.0, input.y)).normalized()
	var planar := Vector2(velocity.x, velocity.z).move_toward(Vector2(dir.x, dir.z) * speed, ACCEL * delta)
	velocity.x = planar.x
	velocity.z = planar.y
	if not is_on_floor():
		velocity.y -= 9.8 * delta
	move_and_slide()


func _process(delta: float) -> void:
	delta = minf(delta, 0.1)
	_time += delta
	# view rotation rate this frame (rad/s, positive yaw = turning left)
	var look_rate := Vector2(-_look_accum.x, -_look_accum.y) * mouse_sensitivity / maxf(delta, 0.001)
	_look_accum = Vector2.ZERO
	_sub_accum += delta
	while _sub_accum >= SUBSTEP:
		_sub_accum -= SUBSTEP
		_motion.step(SUBSTEP, velocity, _camera.global_basis, global_rotation.y, look_rate)

	_head.position.y = EYE_HEIGHT + _motion.head_bob
	_hand.position = HAND_POS + _motion.hand_offset
	_hand.rotation = _motion.hand_rotation
	var yaw_basis := Basis(Vector3.UP, global_rotation.y)
	_rig.global_basis = yaw_basis * Basis(Vector3.UP, _motion.twist) * Basis.from_euler(Vector3(_motion.swing.x, 0.0, _motion.swing.y))
	_lantern.position.y = LANTERN_HANG - _motion.stretch
	_light.position.y = _lantern.position.y + LANTERN_FLAME * LANTERN_SCALE

	_animate_grip(delta, Vector2(velocity.x, velocity.z).length())
	if _log_path != "":
		_log.append("%.3f,%.3f,%.2f,%.2f,%.4f,%.4f" % [_time, Vector2(velocity.x, velocity.z).length(), rad_to_deg(_motion.swing.x),
			rad_to_deg(_motion.swing.y), _hand.position.x - HAND_POS.x, _hand.position.y - HAND_POS.y])


## Look-dev autopilot: idle 1 s, walk 3 s, stop 2 s, quick 90 deg turn, idle 2 s, sprint 3 s, stop 3 s.
func _autopilot_step(delta: float) -> Array:
	_auto_t += delta
	var t := _auto_t
	var input := Vector2.ZERO
	var fast := false
	if t > 1.0 and t < 4.0: input.y = -1.0
	if t >= 6.0 and t < 6.4:
		var step := deg_to_rad(90.0) * delta / 0.4
		rotate_y(-step)
		_look_accum.x += step / mouse_sensitivity
	if t >= 8.4 and t < 11.4:
		input.y = -1.0
		fast = true
	if t >= 14.4 and t < 17.4:
		# hand-held mouse look: irregular small sweeps with jitter, like a player scanning a corridor
		var rate := sin(t * 2.3) * 2.2 + sin(t * 7.1) * 0.9 + (_rng.randf() - 0.5) * 3.0  # rad/s
		var step := rate * delta
		rotate_y(-step)
		_look_accum.x += step / mouse_sensitivity
	if t >= 19.4 and _log_path != "":
		var f := FileAccess.open(_log_path, FileAccess.WRITE)
		f.store_line("t,speed,swing_fwd_deg,swing_side_deg,hand_dx,hand_dy")
		for line in _log: f.store_line(line)
		f.close()
		_log_path = ""
		get_tree().quit()
	return [input, fast]


## The fingers are never frozen: occasional re-grips, tightening when the lantern swings hard or
## you start/stop, and a slow relax (index finger lifting) when standing still.
func _animate_grip(delta: float, ground_speed: float) -> void:
	if _hand_mesh == null:
		return
	_still_time = _still_time + delta if ground_speed < 0.1 else 0.0
	_regrip_timer -= delta
	if _regrip_timer <= 0.0:
		_regrip_pulse = 1.0
		_regrip_timer = _rng.randf_range(4.0, 10.0)
	_regrip_pulse = maxf(0.0, _regrip_pulse - delta * 1.8)
	var pulse := sin(_regrip_pulse * PI) * 0.75  # rises and falls over ~0.55 s
	var swing_tension := clampf(_motion.swing_velocity.length() * 0.6, 0.0, 0.8)
	var relax := -clampf((_still_time - 2.0) * 0.25, 0.0, 0.6)
	var start_stop := clampf(absf(_motion.move_amount - _prev_walk) / maxf(delta, 0.001) * 0.12, 0.0, 0.4)
	_prev_walk = _motion.move_amount
	var target := clampf(relax + swing_tension + pulse + start_stop, -1.0, 1.0)
	if _forced_grip != INF:
		target = _forced_grip
	# critically damped spring so the fingers ease rather than snap
	var k := 60.0
	_grip_vel += (k * (target - _grip) - 2.0 * sqrt(k) * _grip_vel) * delta
	_grip += _grip_vel * delta
	if _squeeze_idx >= 0:
		_hand_mesh.set_blend_shape_value(_squeeze_idx, clampf(_grip, 0.0, 1.0))
	if _relax_idx >= 0:
		_hand_mesh.set_blend_shape_value(_relax_idx, clampf(-_grip, 0.0, 1.0))
