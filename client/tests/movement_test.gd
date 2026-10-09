extends SceneTree
## Headless movement tests: drives Locomotion and HeadMotion with scripted inputs and checks the
## results against targets from gait research and well-regarded first-person games.
##
##   godot --headless --path . --script res://client/tests/movement_test.gd [-- --csv=<dir>] [--update-golden]
##
## Exits 1 if any check fails. With --csv, writes per-scenario traces for review/plotting.
## shared/golden/movement-v1.json is the reference trace the server's TypeScript mirror must
## reproduce; --update-golden rewrites it (only when the model is changed on purpose).

const TICK := 1.0 / 60.0  # physics tick (and the server movement tick)
const GOLDEN := "res://shared/golden/movement-v1.json"

var _fails := 0
var _rows: PackedStringArray = []
var _csv_dir := ""
var _update_golden := false


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--csv="):
			_csv_dir = arg.substr(6)
		_update_golden = _update_golden or arg == "--update-golden"
	_test_locomotion()
	_test_walls()
	_test_golden()
	_test_head_motion()
	_test_lantern()
	print("")
	for r in _rows:
		print(r)
	print("\n%s: %d check(s) failed" % ["FAIL" if _fails else "PASS", _fails])
	quit(1 if _fails else 0)


func _check(name: String, value: float, lo: float, hi: float, unit := "") -> void:
	var ok := value >= lo and value <= hi
	if not ok:
		_fails += 1
	_rows.append("%s  %-52s %9.3f %-5s  target [%s, %s]" % ["ok  " if ok else "FAIL", name, value, unit, str(lo), str(hi)])


# ---------------------------------------------------------------------------------------------
# Locomotion (gameplay integrator)

## Runs a list of [duration_s, input, sprint, yaw_rate_rad_s, speed_mult] segments and returns the
## per-tick trace: [t, vx, vz, x, z, yaw, stamina, sprinting]. `wall` (unit normal, pointing into the
## open side) adds a wall plane through the start point with move_and_slide-style clipping.
func _run(segments: Array, loco: Locomotion = null, yaw0 := 0.0, speed_mult := 1.0, name := "",
		wall := Vector2.ZERO) -> Array:
	if loco == null:
		loco = Locomotion.new()
	var trace := []
	var t := 0.0
	var x := 0.0
	var z := 0.0
	var yaw := yaw0
	for seg in segments:
		var n := roundi(float(seg[0]) / TICK)
		for i in n:
			yaw += (float(seg[3]) if seg.size() > 3 else 0.0) * TICK
			var mult := float(seg[4]) if seg.size() > 4 else speed_mult
			var walls := PackedVector2Array()
			if wall != Vector2.ZERO and x * wall.x + z * wall.y < 1e-6:
				walls.append(wall)
			loco.step(TICK, seg[1], yaw, seg[2], mult, walls)
			# Round-trip through a 32-bit Vector3 like the controller's move_and_slide feedback.
			var v32 := Vector3(loco.vx, 0.0, loco.vz)
			x += v32.x * TICK
			z += v32.z * TICK
			if wall != Vector2.ZERO:
				var d := x * wall.x + z * wall.y
				if d < 0.0:  # slide: remove the penetration and the velocity into the wall
					x -= wall.x * d
					z -= wall.y * d
				var vn := v32.x * wall.x + v32.z * wall.y
				if vn < 0.0 and d <= 1e-6:
					v32.x -= wall.x * vn
					v32.z -= wall.y * vn
			loco.set_velocity(v32.x, v32.z)
			t += TICK
			trace.append([t, loco.vx, loco.vz, x, z, yaw, loco.stamina, int(loco.sprinting)])
	if _csv_dir != "" and name != "":
		var f := FileAccess.open(_csv_dir.path_join("loco_%s.csv" % name), FileAccess.WRITE)
		f.store_line("t,vx,vz,x,z,yaw,stamina,sprinting")
		for r in trace:
			f.store_line("%.4f,%.5f,%.5f,%.5f,%.5f,%.4f,%.3f,%d" % r)
	return trace


func _speed(r: Array) -> float:
	return Vector2(r[1], r[2]).length()


## First time (s) after `from` at which f(row) is true; INF if never.
func _first(trace: Array, from: float, f: Callable) -> float:
	for r in trace:
		if r[0] > from + 1e-6 and f.call(r):
			return r[0] - from
	return INF


func _at(trace: Array, t: float) -> Array:
	for r in trace:
		if r[0] >= t - 1e-6:
			return r
	return trace[-1]


func _test_locomotion() -> void:
	var W := Vector2(0, -1)
	var S := Vector2(0, 1)
	var A := Vector2(-1, 0)
	var D := Vector2(1, 0)
	var NONE := Vector2.ZERO

	# Starting: reacts on the very next tick, most of the change inside ~100 ms (latency research).
	var tr := _run([[1.0, W, false]], null, 0.0, 1.0, "start_walk")
	_check("walk start: first motion", _first(tr, 0.0, func(r): return _speed(r) > 0.01), 0.0, TICK + 1e-4, "s")
	_check("walk start: 50% speed", _first(tr, 0.0, func(r): return _speed(r) >= 1.25), 0.0, 0.1, "s")
	_check("walk start: 90% speed", _first(tr, 0.0, func(r): return _speed(r) >= 2.25), 0.15, 0.3, "s")
	_check("walk: steady forward speed", _speed(tr[-1]), 2.45, 2.55, "m/s")

	# Stopping: crisp, short, and truly zero afterwards (no drift tail).
	tr = _run([[1.0, W, false], [1.0, NONE, false]], null, 0.0, 1.0, "stop_walk")
	var t_stop := _first(tr, 1.0, func(r): return _speed(r) < 0.001)
	_check("walk release: time to standstill", t_stop, 0.15, 0.26, "s")
	_check("walk release: stopping distance", absf(_at(tr, 2.0)[4] - _at(tr, 1.0)[4]), 0.1, 0.3, "m")
	_check("walk release: speed 0.3 s later", _speed(_at(tr, 1.3)), 0.0, 0.0, "m/s")

	# Stops must work at any heading (rounding at a heading once left the body stuck at 2.5 m/s).
	for yaw0 in [PI, 2.0, -0.7]:
		tr = _run([[1.0, W, false], [1.0, NONE, false]], null, yaw0)
		_check("walk release at yaw %.1f: stopped" % yaw0, _speed(tr[-1]), 0.0, 0.0, "m/s")
		tr = _run([[1.5, W, true], [1.0, NONE, false]], null, yaw0)
		_check("sprint release at yaw %.1f: stopped" % yaw0, _speed(tr[-1]), 0.0, 0.0, "m/s")

	# Strafing: the reported problem. Start, release and reverse must all be quick.
	tr = _run([[1.0, D, false], [1.0, NONE, false]], null, 0.0, 1.0, "strafe_stop")
	_check("strafe start: 90% speed", _first(tr, 0.0, func(r): return _speed(r) >= 0.9 * 2.0), 0.1, 0.3, "s")
	_check("strafe: steady speed (0.8x)", _speed(_at(tr, 1.0)), 1.95, 2.05, "m/s")
	_check("strafe release: time to standstill", _first(tr, 1.0, func(r): return _speed(r) < 0.001), 0.1, 0.25, "s")
	_check("strafe release: sideways drift", absf(tr[-1][3] - _at(tr, 1.0)[3]), 0.05, 0.3, "m")

	tr = _run([[1.0, A, false], [1.0, D, false]], null, 0.0, 1.0, "strafe_reverse")
	_check("strafe reversal A->D: zero crossing", _first(tr, 1.0, func(r): return r[1] >= 0.0), 0.05, 0.12, "s")
	_check("strafe reversal A->D: 90% new speed", _first(tr, 1.0, func(r): return r[1] >= 0.9 * 2.0), 0.1, 0.35, "s")
	_check("strafe reversal: overshoot past target", maxf(0.0, tr.map(func(r): return r[1]).max() - 2.0), 0.0, 0.001, "m/s")

	tr = _run([[1.0, W, false], [1.0, S, false]], null, 0.0, 1.0, "fwd_back")
	_check("W->S reversal: zero crossing", _first(tr, 1.0, func(r): return r[2] >= 0.0), 0.05, 0.15, "s")
	_check("backpedal: steady speed (0.7x)", _speed(tr[-1]), 1.7, 1.8, "m/s")

	tr = _run([[1.0, Vector2(1, -1), false]])
	_check("diagonal forward-right: speed", _speed(tr[-1]), 2.15, 2.35, "m/s")

	# Taps: a single-frame tap barely moves you; a 100 ms tap is a visible shuffle.
	tr = _run([[TICK, D, false], [1.0, NONE, false]])
	_check("1-tick tap: distance", absf(tr[-1][3]), 0.0, 0.03, "m")
	tr = _run([[0.1, D, false], [1.0, NONE, false]])
	_check("100 ms tap: distance", absf(tr[-1][3]), 0.08, 0.3, "m")

	# Sprint: the weight lives here. Walk speed still arrives fast; full sprint builds up.
	tr = _run([[1.5, W, true], [1.0, NONE, false]], null, 0.0, 1.0, "sprint")
	_check("sprint start: reaches walk speed", _first(tr, 0.0, func(r): return _speed(r) >= 2.5), 0.1, 0.25, "s")
	_check("sprint start: 90% of 4.5 m/s", _first(tr, 0.0, func(r): return _speed(r) >= 0.9 * 4.5), 0.45, 0.8, "s")
	_check("sprint: steady speed", _speed(_at(tr, 1.5)), 4.4, 4.6, "m/s")
	_check("sprint release: time to standstill", _first(tr, 1.5, func(r): return _speed(r) < 0.001), 0.3, 0.5, "s")
	_check("sprint release: stopping distance", absf(tr[-1][4] - _at(tr, 1.5)[4]), 0.5, 1.1, "m")
	tr = _run([[1.5, W, true], [1.0, W, false]])
	_check("sprint -> walk: settles at walk speed", _first(tr, 1.5, func(r): return _speed(r) <= 2.51), 0.1, 0.3, "s")
	tr = _run([[1.5, D, true]])
	_check("sprint sideways: not allowed (strafe speed)", _speed(tr[-1]), 1.95, 2.05, "m/s")
	tr = _run([[1.5, Vector2(0.5, -1), true]])
	_check("sprint at ~27 deg off forward: allowed", _speed(tr[-1]), 4.2, 4.6, "m/s")

	# Turning: the old velocity must not carry you sideways (no sliding on turns).
	tr = _run([[1.0, W, false], [0.2, W, false, -PI / 2 / 0.2], [0.6, W, false]], null, 0.0, 1.0, "turn")
	var r_end: Array = tr[-1]
	var fwd := Vector2(-sin(float(r_end[5])), -cos(float(r_end[5])))
	var r15 := _at(tr, 1.5)
	_check("90 deg turn while walking: sideways speed 0.3 s later", absf(float(r15[1]) * fwd.y - float(r15[2]) * fwd.x), 0.0, 0.02, "m/s")
	_check("90 deg turn while walking: never faster than walk", tr.map(func(r): return _speed(r)).max(), 0.0, 2.501, "m/s")

	# Sprint then S: plant and shed speed like a runner (not a 5 g stop that beats releasing W).
	tr = _run([[1.5, W, true], [1.0, S, false]], null, 0.0, 1.0, "sprint_back")
	var peak := 0.0
	for i in range(1, tr.size()):
		if _speed(tr[i - 1]) > 2.55 and tr[i][2] < 0.0:  # the running part; below walk speed it's a normal reversal
			peak = maxf(peak, (_speed(tr[i - 1]) - _speed(tr[i])) / TICK)
	_check("sprint -> S: peak deceleration while above walk speed", peak, 10.0, 17.0, "m/s2")
	_check("sprint -> S: time to reverse", _first(tr, 1.5, func(r): return r[2] >= 0.0), 0.15, 0.3, "s")

	# Walking into darkness (0.5x): slows like a runner easing off, not a lurch.
	tr = _run([[1.0, W, false], [1.0, W, false, 0.0, 0.5]])
	peak = 0.0
	for i in range(1, tr.size()):
		peak = maxf(peak, (_speed(tr[i - 1]) - _speed(tr[i])) / TICK)
	_check("entering darkness: peak deceleration", peak, 0.0, 12.0, "m/s2")
	_check("entering darkness: settles at 1.25 m/s", _speed(tr[-1]), 1.24, 1.26, "m/s")

	# Analogue: a half-tilted stick walks at half speed.
	tr = _run([[1.0, Vector2(0, -0.5), false]])
	_check("analogue half tilt: speed", _speed(tr[-1]), 1.2, 1.3, "m/s")

	# Stamina: ~6 s of sprint, then walk speed (never a crawl), sprint returns after a rest.
	var loco := Locomotion.new()
	tr = _run([[9.0, W, true]], loco, 0.0, 1.0, "stamina")
	_check("stamina: sprint duration", _first(tr, 0.0, func(r): return r[6] <= 0.0), 5.5, 6.6, "s")
	_check("stamina: exhausted speed = walk", _speed(tr[-1]), 2.45, 2.55, "m/s")
	tr = _run([[3.0, NONE, false], [1.0, W, true]], loco)
	_check("stamina: sprint again after 3 s rest", _speed(tr[-1]), 4.4, 4.6, "m/s")

	# Darkness multiplier (spec §7) scales speed, not responsiveness.
	tr = _run([[1.0, W, false]], null, 0.0, 0.5)
	_check("darkness 0.5x: speed", _speed(tr[-1]), 1.2, 1.3, "m/s")



## Wall sliding: you glide along a wall at speed x cos(angle) (never stick, never exceed the target).
func _test_walls() -> void:
	for case in [[30.0, false], [45.0, false], [60.0, false], [80.0, false], [20.0, true], [45.0, true]]:
		var ang := deg_to_rad(float(case[0]))
		var sprint: bool = case[1]
		# Wish is forward (-Z); the wall runs at `ang` to it and its normal faces back at the player.
		var n := Vector2(-cos(ang), sin(ang))
		var tr := _run([[1.5, Vector2(0, -1), sprint]], null, 0.0, 1.0, "", n)
		var ideal := (4.5 if sprint else 2.5) * cos(ang)
		var label := "%s into wall at %d deg: slide speed / ideal" % ["sprint" if sprint else "walk", int(case[0])]
		_check(label, _speed(tr[-1]) / ideal, 0.97, 1.001)
	# A corner (two walls) pushed into diagonally: stop, don't jitter.
	var loco := Locomotion.new()
	for i in 30:
		loco.step(TICK, Vector2(-1, -1), 0.0, false, 1.0, PackedVector2Array([Vector2(1, 0), Vector2(0, 1)]))
		var v := Vector2(loco.vx, loco.vz)
		loco.set_velocity(maxf(v.x, 0.0), maxf(v.y, 0.0))
	_check("pushing into a corner: speed", loco.speed(), 0.0, 0.0, "m/s")
	# Walking away from a wall you touched last tick is not hindered.
	var tr2 := _run([[0.5, Vector2(0, 1), false]], null, 0.0, 1.0, "", Vector2(0, 1))
	_check("walking away from a wall: speed", _speed(tr2[-1]), 1.7, 1.8, "m/s")


## Golden trace: the reference the server's TypeScript mirror must reproduce exactly (spec §7).
func _test_golden() -> void:
	var W := Vector2(0, -1)
	var segs := [[0.5, W, false], [0.7, W, true, 0.8], [0.3, Vector2(-1, 0), false, 1.3],
		[0.4, Vector2(1, -1), false, -2.0], [0.3, Vector2(0, 1), false], [0.5, W, true, 0.0, 0.5],
		[0.5, Vector2.ZERO, false]]
	var tr := _run(segs, null, 0.37)
	var rows := []
	for i in range(0, tr.size(), 6):
		var r: Array = tr[i]
		rows.append(["%.6f" % r[1], "%.6f" % r[2], "%.6f" % r[3], "%.6f" % r[4], "%.4f" % r[6]])
	var doc := {"version": 1, "tick_hz": 60, "yaw0": 0.37, "segments": str(segs), "every_n_ticks": 6,
		"columns": ["vx", "vz", "x", "z", "stamina"], "rows": rows}
	var path := ProjectSettings.globalize_path(GOLDEN)
	if _update_golden:
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(JSON.stringify(doc, "  ") + "\n")
		print("wrote ", path)
	var g = JSON.parse_string(FileAccess.get_file_as_string(path))
	_check("golden trace matches shared/golden/movement-v1.json",
		1.0 if g is Dictionary and str(g.rows) == str(rows) else 0.0, 1.0, 1.0)


# ---------------------------------------------------------------------------------------------
# HeadMotion (cosmetic camera)

## Drives HeadMotion at a given frame rate with a constant velocity profile [[duration, speed, side]].
func _run_head(fps: float, profile: Array, name := "") -> Dictionary:
	var hm := HeadMotion.new()
	var dt := 1.0 / fps
	var t := 0.0
	var out := {"t": [], "y": [], "x": [], "roll": [], "pitch": [], "steps": [], "fov": [], "foot": []}
	var lines: PackedStringArray = ["t,speed,off_x,off_y,roll_deg,pitch_deg,footsteps"]
	for seg in profile:
		var n := roundi(float(seg[0]) * fps)
		for i in n:
			t += dt
			var v := Vector3(float(seg[2]), 0.0, -float(seg[1]))  # yaw 0: forward is -Z
			hm.update(dt, v, 0.0, seg.size() > 3 and seg[3])
			out.t.append(t)
			out.y.append(hm.offset.y)
			out.x.append(hm.offset.x)
			out.roll.append(rad_to_deg(hm.roll))
			out.pitch.append(rad_to_deg(hm.pitch))
			out.steps.append(hm.footsteps)
			out.fov.append(hm.fov_add)
			out.foot.append(hm.last_foot)
			lines.append("%.4f,%.3f,%.5f,%.5f,%.3f,%.3f,%d" % [t, Vector2(v.x, v.z).length(), hm.offset.x, hm.offset.y, rad_to_deg(hm.roll), rad_to_deg(hm.pitch), hm.footsteps])
	if _csv_dir != "" and name != "":
		var f := FileAccess.open(_csv_dir.path_join("head_%s.csv" % name), FileAccess.WRITE)
		f.store_string("\n".join(lines))
	return out


## HeadMotion driven by real Locomotion velocities (60 Hz ticks) at `fps`; segments [dur, input].
## hitch_at: one 100 ms frame at that time.
func _run_head_loco(fps: float, segments: Array, hitch_at := -1.0) -> Dictionary:
	var hm := HeadMotion.new()
	var loco := Locomotion.new()
	var out := {"t": [], "pitch": [], "steps": [], "soft": []}
	var t := 0.0
	var acc := 0.0
	var hitched := false
	for seg in segments:
		var end_t := t + float(seg[0])
		while t < end_t - 1e-9:
			var dt := 1.0 / fps
			if hitch_at >= 0.0 and not hitched and t >= hitch_at:
				dt = 0.1
				hitched = true
			t += dt
			acc += dt
			while acc >= TICK:
				acc -= TICK
				loco.step(TICK, seg[1], 0.0, false)
			hm.update(dt, Vector3(loco.vx, 0.0, loco.vz), 0.0, false)
			out.t.append(t)
			out.pitch.append(rad_to_deg(hm.pitch))
			out.steps.append(hm.footsteps)
			out.soft.append(hm.soft_step)
	return out


func _first_step_after(out: Dictionary, from: float) -> float:
	for i in range(1, out.t.size()):
		if out.t[i] > from and out.steps[i] != out.steps[i - 1]:
			return out.t[i] - from
	return INF


func _window(out: Dictionary, key: String, a: float, b: float) -> Array:
	var r := []
	for i in out.t.size():
		if out.t[i] >= a and out.t[i] < b:
			r.append(out[key][i])
	return r


## Footfalls per second from the times of footstep events inside [a, b).
func _step_rate(out: Dictionary, a: float, b: float) -> float:
	var times: Array[float] = []
	for i in range(1, out.t.size()):
		if out.t[i] >= a and out.t[i] < b and out.steps[i] != out.steps[i - 1]:
			times.append(out.t[i])
	return (times.size() - 1) / (times[-1] - times[0]) if times.size() > 1 else 0.0


func _range(vals: Array) -> float:
	return vals.max() - vals.min() if vals.size() else 0.0


func _test_head_motion() -> void:
	var walk := _run_head(144.0, [[4.0, 2.5, 0.0], [1.0, 0.0, 0.0]], "walk")
	var steps_walk := _step_rate(walk, 1.5, 4.0)
	_check("walk 2.5 m/s: step rate", steps_walk, 2.3, 2.75, "st/s")
	_check("walk: vertical bob (peak-trough)", _range(_window(walk, "y", 2.0, 4.0)) * 100.0, 1.2, 2.5, "cm")
	_check("walk: lateral sway (peak-trough)", _range(_window(walk, "x", 2.0, 4.0)) * 100.0, 0.4, 1.5, "cm")
	_check("walk: per-step roll (peak-trough)", _range(_window(walk, "roll", 2.0, 4.0)), 0.1, 0.8, "deg")
	_check("walk: gaze-stabilising pitch (peak-trough)", _range(_window(walk, "pitch", 2.0, 4.0)), 0.1, 0.8, "deg")
	var ys := _window(walk, "y", 2.0, 4.0)
	var ps := _window(walk, "pitch", 2.0, 4.0)
	var corr := 0.0
	for i in ys.size():
		corr += ys[i] * ps[i]
	_check("walk: head pitches against its bob (gaze held)", -signf(corr), 1.0, 1.0)
	var settle: float = _window(walk, "y", 4.2, 5.0).map(func(v): return absf(v)).max()
	_check("stop: bob back to neutral within 0.2 s", settle * 1000.0, 0.0, 1.0, "mm")
	_check("stop: nods down (min pitch after stop)", _window(walk, "pitch", 4.0, 4.6).min(), -1.0, -0.3, "deg")
	_check("stop: no footsteps after standstill", float(walk.steps[-1] - _window(walk, "steps", 4.2, 4.21)[0]), 0.0, 0.0)

	var run := _run_head(144.0, [[4.0, 4.5, 0.0, true]], "run")
	var steps_run := _step_rate(run, 1.5, 4.0)
	_check("run 4.5 m/s: step rate", steps_run, 2.75, 3.1, "st/s")
	_check("run: vertical bob (peak-trough)", _range(_window(run, "y", 2.0, 4.0)) * 100.0, 3.0, 4.5, "cm")
	_check("run: sprint FOV kick", run.fov[-1], 3.0, 5.0, "deg")

	var strafe := _run_head(144.0, [[2.0, 0.0, 2.0]], "strafe")
	_check("strafe right: camera leans right (roll < 0)", -signf(_window(strafe, "roll", 1.0, 2.0)[0]), 1.0, 1.0)
	_check("strafe: roll into the motion", absf(_window(strafe, "roll", 1.0, 2.0).reduce(func(a, b): return a + b, 0.0) / _window(strafe, "roll", 1.0, 2.0).size()), 0.5, 1.5, "deg")
	_check("strafe: max roll", _window(strafe, "roll", 0.0, 2.0).map(func(v): return absf(v)).max(), 0.0, 2.0, "deg")

	var idle := _run_head(144.0, [[2.0, 0.0, 0.0]])
	_check("idle: camera perfectly still", _range(idle.y) + _range(idle.roll) + _range(idle.pitch), 0.0, 0.0)

	# Footfalls are the low points of the bob.
	var worst := 0.0
	var amp := _range(_window(walk, "y", 2.0, 4.0))
	for i in range(1, walk.t.size()):
		if walk.t[i] > 1.5 and walk.t[i] < 4.0 and walk.steps[i] != walk.steps[i - 1]:
			worst = maxf(worst, (walk.y[i] - _window(walk, "y", 2.0, 4.0).min()) / amp)
	_check("footstep at bob low point (0 = exactly)", worst, 0.0, 0.08)

	# The head sways over the stance foot.
	var side_ok := 1.0
	for i in range(1, walk.t.size()):
		if walk.t[i] > 1.5 and walk.t[i] < 3.8 and walk.steps[i] != walk.steps[i - 1]:
			var j := mini(i + roundi(0.17 * 144.0), walk.t.size() - 1)  # ~mid-stance
			var foot: int = walk.foot[i]
			if signf(walk.x[j]) != (-1.0 if foot == 0 else 1.0):
				side_ok = 0.0
	_check("head sways over the stance foot (L=-x, R=+x)", side_ok, 1.0, 1.0)

	# Starting and stopping with real locomotion: first step lands soon, a stop closes quietly.
	var go := _run_head_loco(144.0, [[1.0, Vector2.ZERO], [1.5, Vector2(0, -1)], [1.0, Vector2.ZERO]])
	_check("start: first footfall after pressing W", _first_step_after(go, 1.0), 0.15, 0.4, "s")
	var soft_after := 0
	for i in range(1, go.t.size()):
		if go.t[i] > 2.5 and go.steps[i] != go.steps[i - 1] and go.soft[i]:
			soft_after += 1
	_check("stop: one quiet closing step", float(soft_after), 0.0, 1.0)

	# Low frame rates and a 100 ms hitch must not destabilise the springs.
	for fps in [15.0, 20.0]:
		var slow := _run_head_loco(fps, [[1.5, Vector2(0, -1)], [1.0, Vector2.ZERO]])
		_check("%d fps: max |pitch| (stable)" % int(fps), slow.pitch.map(func(v): return absf(v)).max(), 0.0, 1.2, "deg")
	var hitch := _run_head_loco(144.0, [[1.5, Vector2(0, -1)], [1.0, Vector2.ZERO]], 1.52)
	_check("100 ms hitch during a stop: max |pitch|", hitch.pitch.map(func(v): return absf(v)).max(), 0.0, 1.2, "deg")

	# Frame-rate independence.
	var walk30 := _run_head(30.0, [[4.0, 2.5, 0.0], [1.0, 0.0, 0.0]])
	_check("30 vs 144 fps: bob amplitude ratio", _range(_window(walk30, "y", 2.0, 4.0)) / amp, 0.95, 1.05)
	_check("30 vs 144 fps: footsteps", float(walk30.steps[-1] - walk.steps[-1]), -1.0, 1.0)


# ---------------------------------------------------------------------------------------------
# LanternMotion (the weight): wired exactly like fp_controller (240 Hz sub-steps per frame)

func _run_lantern(fps: float, segments: Array, hitch_at := -1.0) -> Dictionary:
	var loco := Locomotion.new()
	var hm := HeadMotion.new()
	var lm := LanternMotion.new(Vector3(-0.28, -0.04, -0.39))
	var out := {"t": [], "fwd": [], "side": []}
	var t := 0.0
	var acc := 0.0
	var sub := 0.0
	var hitched := false
	for seg in segments:
		var end_t := t + float(seg[0])
		while t < end_t - 1e-9:
			var dt := 1.0 / fps
			if hitch_at >= 0.0 and not hitched and t >= hitch_at:
				dt = 0.1
				hitched = true
			t += dt
			acc += dt
			while acc >= TICK:
				acc -= TICK
				loco.step(TICK, seg[1], 0.0, seg[2])
			var v := Vector3(loco.vx, 0.0, loco.vz)
			hm.update(dt, v, 0.0, loco.sprinting)
			sub += dt
			while sub >= 1.0 / 240.0:
				sub -= 1.0 / 240.0
				lm.step(1.0 / 240.0, v, Basis.IDENTITY, 0.0, Vector2.ZERO, hm.stride_phase, hm.gait, hm.amount)
			out.t.append(t)
			out.fwd.append(rad_to_deg(lm.swing.x))
			out.side.append(rad_to_deg(lm.swing.y))
	return out


func _settle(out: Dictionary, from: float, limit_deg: float) -> float:
	var last := from
	for i in out.t.size():
		if out.t[i] >= from and (absf(out.fwd[i]) >= limit_deg or absf(out.side[i]) >= limit_deg):
			last = out.t[i]
	return last - from


func _test_lantern() -> void:
	var W := Vector2(0, -1)
	var idle := _run_lantern(144.0, [[2.0, Vector2.ZERO, false]])
	_check("lantern idle: hangs still (breathing only)", _range(idle.fwd) + _range(idle.side), 0.0, 0.1, "deg")
	var walk := _run_lantern(144.0, [[3.0, W, false], [3.0, Vector2.ZERO, false]])
	_check("lantern walking: gentle sway (max fwd)", _window(walk, "fwd", 1.5, 3.0).map(func(v): return absf(v)).max(), 0.5, 5.0, "deg")
	_check("lantern walk stop: swings forward (max)", _window(walk, "fwd", 3.0, 4.5).map(func(v): return absf(v)).max(), 5.0, 13.0, "deg")
	_check("lantern walk stop: settles under 2 deg", _settle(walk, 3.0, 2.0), 0.4, 1.5, "s")
	var run := _run_lantern(144.0, [[3.0, W, true], [3.0, Vector2.ZERO, false]])
	_check("lantern sprint stop: swing (max)", _window(run, "fwd", 3.0, 4.5).map(func(v): return absf(v)).max(), 7.0, 16.0, "deg")
	_check("lantern sprint stop: settles under 2 deg", _settle(run, 3.0, 2.0), 0.5, 1.8, "s")
	var strafe := _run_lantern(144.0, [[1.5, Vector2(-1, 0), false], [1.5, Vector2(1, 0), false], [2.0, Vector2.ZERO, false]])
	_check("lantern strafe reversal: side swing (max)", strafe.side.map(func(v): return absf(v)).max(), 4.0, 15.0, "deg")
	var hitch := _run_lantern(144.0, [[2.0, W, false], [2.0, Vector2.ZERO, false]], 2.05)
	var finite := 1.0
	for v in hitch.fwd + hitch.side:
		if is_nan(v) or absf(v) > 20.0:
			finite = 0.0
	_check("lantern 100 ms hitch: stays sane", finite, 1.0, 1.0)
	var slow := _run_lantern(20.0, [[2.0, W, false], [2.0, Vector2.ZERO, false]])
	_check("lantern at 20 fps: stop swing (max)", slow.fwd.map(func(v): return absf(v)).max(), 5.0, 14.0, "deg")
