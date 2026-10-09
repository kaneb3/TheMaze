extends CharacterBody3D
## First-person controller with a hand-held lantern (look-dev version; the real one gets server
## prediction/reconciliation in S3). WASD + mouse, Shift sprints, F toggles the lantern, Esc frees
## the mouse.
##
## Three layers, tested in client/tests/movement_test.gd (+ wall_slide_test.gd against real physics):
## - Locomotion: the gameplay integrator (fixed tick, server-mirrorable). Quick, crisp control.
## - HeadMotion: cosmetic camera driven by the stride (bob, footsteps, gaze, roll, nod, FOV).
## - LanternMotion: the inertial arm and hand-damped lantern pendulum, locked to the same stride.
## The body moves on physics ticks; the camera is interpolated between ticks so it never judders.

@export var mouse_sensitivity := 0.0022
@export_range(0.0, 1.0) var bob_scale := 1.0  # accessibility: head bob and nod
@export_range(0.0, 1.0) var roll_scale := 1.0  # accessibility: strafe/step roll
@export_range(0.0, 1.0) var fov_scale := 1.0  # accessibility: sprint FOV kick
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
const SUBSTEP := 1.0 / 240.0
const BASE_FOV := 72.0

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
var _loco := Locomotion.new()
var _view := HeadMotion.new()
var _sub_accum := 0.0
var _steps: AudioStreamPlayer
var _steps_heard := 0
var _walls := PackedVector2Array()  # walls touched on the last physics tick (for wall sliding)
var _phys_prev := Vector3.ZERO  # body position at the previous / latest physics tick
var _phys_cur := Vector3.ZERO

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
	_camera.fov = BASE_FOV
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
	# Footsteps (Kenney Impact Sounds, CC0): random variant without repeats, varied pitch/volume.
	var steps := AudioStreamRandomizer.new()
	steps.playback_mode = AudioStreamRandomizer.PLAYBACK_RANDOM_NO_REPEATS
	steps.random_pitch = 1.08
	steps.random_volume_offset_db = 1.5
	for i in 5:
		steps.add_stream(-1, load("res://client/assets/audio/footsteps/footstep_concrete_%03d.ogg" % i))
	_steps = AudioStreamPlayer.new()
	_steps.name = "Footsteps"
	_steps.stream = steps
	_steps.max_polyphony = 3
	add_child(_steps)
	_view.bob_scale = bob_scale
	_view.roll_scale = roll_scale
	_view.fov_scale = fov_scale
	_phys_prev = global_position
	_phys_cur = global_position


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
	var sprint := Input.is_physical_key_pressed(KEY_SHIFT)
	if _autopilot:
		var a := _autopilot_step(delta)
		input = a[0]
		sprint = a[1]
	_phys_prev = global_position
	_loco.step(delta, input, rotation.y, sprint, 1.0, _walls)
	velocity.x = _loco.vx
	velocity.z = _loco.vz
	if not is_on_floor():
		velocity.y -= 9.8 * delta
	move_and_slide()
	_loco.set_velocity(velocity.x, velocity.z)  # walls absorb momentum
	_walls = Locomotion.wall_normals(self)
	_phys_cur = global_position


## Call after teleporting the body (fast travel, server correction) so the camera doesn't streak.
func reset_interpolation() -> void:
	_phys_prev = global_position
	_phys_cur = global_position


func _process(delta: float) -> void:
	delta = minf(delta, 0.1)
	_time += delta
	# view rotation rate this frame (rad/s, positive yaw = turning left)
	var look_rate := Vector2(-_look_accum.x, -_look_accum.y) * mouse_sensitivity / maxf(delta, 0.001)
	_look_accum = Vector2.ZERO
	# Camera: interpolate the body between physics ticks, then add the stride-driven head motion.
	# The bob is a body motion, so it is applied in the level (yaw) frame, not the mouse-pitched one.
	var f := Engine.get_physics_interpolation_fraction()
	_view.update(delta, velocity, global_rotation.y, _loco.sprinting)
	_head.global_position = _phys_prev.lerp(_phys_cur, f) + Vector3(0.0, EYE_HEIGHT, 0.0) \
		+ Basis(Vector3.UP, global_rotation.y) * _view.offset
	_camera.rotation = Vector3(_view.pitch, 0.0, _view.roll)
	_camera.fov = BASE_FOV + _view.fov_add
	_play_footsteps(delta)

	_sub_accum += delta
	while _sub_accum >= SUBSTEP:
		_sub_accum -= SUBSTEP
		_motion.step(SUBSTEP, velocity, _camera.global_basis, global_rotation.y, look_rate,
			_view.stride_phase, _view.gait, _view.amount)

	_hand.position = HAND_POS + _motion.hand_offset
	_hand.rotation = _motion.hand_rotation
	var yaw_basis := Basis(Vector3.UP, global_rotation.y)
	_rig.global_basis = yaw_basis * Basis(Vector3.UP, _motion.twist) * Basis.from_euler(Vector3(_motion.swing.x, 0.0, _motion.swing.y))
	_lantern.position.y = LANTERN_HANG - _motion.stretch
	_light.position.y = _lantern.position.y + LANTERN_FLAME * LANTERN_SCALE

	_animate_grip(delta, Vector2(velocity.x, velocity.z).length())
	if _log_path != "":
		var v_side := velocity.dot(global_basis.x)
		_log.append("%.3f,%.3f,%.2f,%.2f,%.4f,%.4f,%.3f,%.4f,%.3f,%d" % [_time, Vector2(velocity.x, velocity.z).length(),
			rad_to_deg(_motion.swing.x), rad_to_deg(_motion.swing.y), _hand.position.x - HAND_POS.x,
			_hand.position.y - HAND_POS.y, v_side, _view.offset.y, rad_to_deg(_view.roll), _view.footsteps])


## One sound per footfall, locked to the camera's stride. Running lands harder; a stop ends with
## the quiet closing step of the trailing foot.
func _play_footsteps(_delta: float) -> void:
	if _view.footsteps == _steps_heard:
		return
	_steps_heard = _view.footsteps
	if _view.soft_step:
		_steps.volume_db = -19.0
		_steps.pitch_scale = 1.08
	else:
		_steps.volume_db = lerpf(-13.0, -7.0, _view.gait) + (0.0 if _view.last_foot == 0 else -1.0)
		_steps.pitch_scale = lerpf(1.0, 0.92, _view.gait)
	_steps.play()


## Look-dev autopilot: idle 1 s, walk 3 s, stop 2 s, quick 90 deg turn, idle 2 s, sprint 3 s, stop 3 s,
## mouse scanning 3 s, idle 2 s, strafe right 1.5 s, reverse left 1.5 s, stop.
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
	if t >= 19.4 and t < 20.9: input.x = 1.0
	if t >= 20.9 and t < 22.4: input.x = -1.0
	if t >= 24.4 and _log_path != "":
		var f := FileAccess.open(_log_path, FileAccess.WRITE)
		f.store_line("t,speed,swing_fwd_deg,swing_side_deg,hand_dx,hand_dy,v_side,cam_y,roll_deg,footsteps")
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
	# critically damped spring so the fingers ease rather than snap (sub-stepped: stable on hitches)
	var k := 60.0
	var n := ceili(delta / (1.0 / 240.0))
	for i in n:
		_grip_vel += (k * (target - _grip) - 2.0 * sqrt(k) * _grip_vel) * delta / n
		_grip += _grip_vel * delta / n
	if _squeeze_idx >= 0:
		_hand_mesh.set_blend_shape_value(_squeeze_idx, clampf(_grip, 0.0, 1.0))
	if _relax_idx >= 0:
		_hand_mesh.set_blend_shape_value(_relax_idx, clampf(-_grip, 0.0, 1.0))
