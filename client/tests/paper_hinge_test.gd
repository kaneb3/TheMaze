extends SceneTree
## Headless checks that a map crease (PaperHinge) moves like paper in air, not jelly:
##
##   godot --headless --path . --script res://client/tests/paper_hinge_test.gd
##
## A 0.25 s whip of 0.5 m along the sheet's normal (the pop-up into reading position, minimum-jerk
## path: ~3.7 m/s and ~46 m/s^2 peak) must blow the panel back during the move, give at most one soft
## follow-through after the stop (no ringing), and settle within ~1.5 s. Motion in the sheet's own
## plane must not bend it. It must stay sane at a 20 fps frame rate. Exits 1 on failure.

const FAR := [0.8, 0.45, 3.5, 20.0, 0.067, 70.0]  # the far column: the biggest, slowest swing
const GRIP := [1.3, 0.45, 2.5, 18.0, 0.133, 25.0]  # the crease next to the held column

var _fails := 0


func _initialize() -> void:
	for p in [FAR, GRIP]:
		_whip(p, 1.0 / 60.0, "60 fps")
	_whip(FAR, 1.0 / 20.0, "20 fps")
	_in_plane()
	print("")
	print("paper hinge: %s" % ("FAIL (%d)" % _fails if _fails else "all passed"))
	quit(1 if _fails else 0)


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails += 1


func _make(p: Array) -> PaperHinge:
	return PaperHinge.new(p[0], p[1], p[2], p[3], p[4], p[5])


## Minimum-jerk move of `dist` m in `dur` s: velocity and acceleration at time t.
func _mj(t: float, dist: float, dur: float) -> Vector2:
	if t <= 0.0 or t >= dur:
		return Vector2.ZERO
	var s := t / dur
	var v := dist / dur * (30.0 * s * s - 60.0 * s * s * s + 30.0 * pow(s, 4.0))
	var a := dist / (dur * dur) * (60.0 * s - 180.0 * s * s + 120.0 * s * s * s)
	return Vector2(v, a)


func _whip(p: Array, dt: float, label: String) -> void:
	var h := _make(p)
	var dur := 0.25
	var t := 0.0
	var peak_lag := 0.0
	var trace: Array[float] = []
	while t < 3.0:
		var va := _mj(t, 0.5, dur)
		h.step(dt, va.y, va.x)  # moving towards the eye along the normal
		t += dt
		if t <= dur + 0.05:
			peak_lag = minf(peak_lag, h.theta)
		else:
			trace.append(h.theta)
	var name := "f=%.1f Hz (%s)" % [p[0], label]
	_check(peak_lag < deg_to_rad(-5.0), "%s: blows back during the whip (%.1f deg)" % [name, rad_to_deg(peak_lag)])
	_check(is_finite(h.theta) and h.theta >= -deg_to_rad(p[5]) - 1e-4 and h.theta <= h.limit_fwd + 1e-4,
		"%s: stays finite and within its limits" % name)
	# after the stop: count the visible swings past rest (> 1.5 deg; a sub-degree settle is invisible)
	var swings := 0
	var over := 0.0
	var ext := 0.0
	for i in trace.size():
		if i > 0 and signf(trace[i]) != signf(trace[i - 1]):
			if absf(ext) > deg_to_rad(1.5) and signf(ext) > 0.0 or (swings > 0 and absf(ext) > deg_to_rad(1.5)):
				swings += 1
			ext = 0.0
		if absf(trace[i]) > absf(ext):
			ext = trace[i]
		over = maxf(over, trace[i])
	if absf(ext) > deg_to_rad(1.5) and signf(ext) > 0.0:
		swings += 1
	_check(swings <= 1, "%s: at most one visible follow-through, no ringing (%d)" % [name, swings])
	_check(over <= absf(peak_lag) * 0.45, "%s: the follow-through is soft (%.1f deg vs %.1f lag)" % [name, rad_to_deg(over), rad_to_deg(-peak_lag)])
	var settle := -1.0
	for i in trace.size():
		if absf(trace[i]) > deg_to_rad(1.0):
			settle = (i + 1) * dt
	_check(settle < 1.6, "%s: settles within ~1.5 s of the stop (%.2f s)" % [name, settle])


func _in_plane() -> void:
	# sliding the sheet along its own plane: no normal velocity or acceleration reaches the hinge
	var h := _make(FAR)
	for i in 120:
		h.step(1.0 / 60.0, 0.0, 0.0)
	_check(absf(h.theta) < 1e-6, "motion in the sheet's own plane doesn't bend it")
