extends SceneTree
## Wall sliding against the real physics engine (Jolt), wired exactly like fp_controller:
## Locomotion.step -> move_and_slide -> velocity fed back -> wall normals for the next tick.
##
##   godot --headless --path . --script res://client/tests/wall_slide_test.gd
##
## You should glide along a wall at speed x cos(angle), never stick, never go faster than the
## target, and stop dead when pushing straight in. Exits 1 on failure.

const CASES := [[30.0, false], [45.0, false], [60.0, false], [80.0, false], [90.0, false], [20.0, true], [45.0, true]]
const RUN_TICKS := 90  # 1.5 s
const MEASURE_TICKS := 20  # average the last 1/3 s

var _body: CharacterBody3D
var _loco: Locomotion
var _walls := PackedVector2Array()
var _case := -1
var _tick := 0
var _sum := 0.0
var _max := 0.0
var _fails := 0


func _initialize() -> void:
	var root3d := Node3D.new()
	get_root().add_child(root3d)
	_box(root3d, Vector3(0, -0.5, 0), Vector3(200, 1, 200))  # floor
	_box(root3d, Vector3(0, 3.5, -1.5), Vector3(200, 7, 1))  # wall face at z = -1, normal +Z
	_body = CharacterBody3D.new()
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	shape.shape = cap
	shape.position.y = 0.9
	_body.add_child(shape)
	root3d.add_child(_body)
	_next_case()


func _box(parent: Node3D, pos: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = pos
	parent.add_child(body)


func _next_case() -> void:
	_case += 1
	if _case >= CASES.size():
		return
	var ang := deg_to_rad(float(CASES[_case][0]))
	_body.position = Vector3(0, 0.05, -1.0 + 0.4 + 0.02)
	_body.rotation.y = PI / 2.0 - ang  # forward runs at `ang` to the wall, into it
	_body.velocity = Vector3.ZERO
	_loco = Locomotion.new()
	_walls = PackedVector2Array()
	_tick = 0
	_sum = 0.0
	_max = 0.0


func _physics_process(delta: float) -> bool:
	if _case >= CASES.size():
		print("\n%s: %d check(s) failed" % ["FAIL" if _fails else "PASS", _fails])
		quit(1 if _fails else 0)
		return true
	var sprint: bool = CASES[_case][1]
	_loco.step(delta, Vector2(0, -1), _body.rotation.y, sprint, 1.0, _walls)
	_body.velocity.x = _loco.vx
	_body.velocity.z = _loco.vz
	if not _body.is_on_floor():
		_body.velocity.y -= 9.8 * delta
	_body.move_and_slide()
	_loco.set_velocity(_body.velocity.x, _body.velocity.z)
	_walls = Locomotion.wall_normals(_body)
	var sp := Vector2(_body.velocity.x, _body.velocity.z).length()
	_max = maxf(_max, sp)
	_tick += 1
	if _tick > RUN_TICKS - MEASURE_TICKS:
		_sum += sp
	if _tick >= RUN_TICKS:
		var ang := float(CASES[_case][0])
		var target := 4.5 if sprint else 2.5
		var ideal := target * cos(deg_to_rad(ang))
		var avg := _sum / MEASURE_TICKS
		var ok := absf(avg - ideal) <= maxf(0.05 * ideal, 0.03) and _max <= target + 0.01
		if not ok:
			_fails += 1
		print("%s  %-6s into wall at %2d deg: slide %.3f m/s (ideal %.3f), max %.3f" % [
			"ok  " if ok else "FAIL", "sprint" if sprint else "walk", int(ang), avg, ideal, _max])
		_next_case()
	return false
