class_name PaperHinge
extends RefCounted
## One crease of the hand-held map, moving like paper in air rather than a spring (research brief,
## 2026-10-10). A 30-40 cm sheet of ~160 g/m2 parchment has natural frequencies of only ~0.3-1 Hz,
## the air it drags along outweighs it ("added mass"), and drag damps it hard (zeta ~0.3-0.5, more
## for big swings). So when the hand whips it up it blows back into a swept shape, and when the hand
## stops it gives one soft follow-through and a slow return: no ringing. (A light 4-6 Hz spring that
## rings after the stop is exactly what read as jelly.)
##
##   theta'' = w0^2 (rest - theta) - 2 zeta w0 theta' - beta a_n - gamma w |w|
##
## theta: the hinge angle away from its authored rest (+ folds the free part towards the eye).
## a_n: the acceleration of the panel's frame along the panel's normal (+ towards the eye), from the
## hand moving it (inertia: the free part lags). w: the panel's normal velocity through the air
## (frame motion + its own swing), so drag fades as a panel turns edge-on (reconfiguration). In-plane
## motion barely bends paper (skin friction < 1% of pressure drag) and is ignored. Creases have
## memory: folding further the way the crease already goes is easier (0.6x stiffness).

var freq := 1.0  # Hz
var zeta := 0.35
var beta := 3.0  # rad/s^2 per m/s^2 of normal acceleration
var gamma := 18.0  # 1/m: quadratic drag
var lever := 0.1  # m: hinge to the moving panel's centroid
var limit := 0.8  # rad, bending back (away from the eye)
var limit_fwd := 0.35  # rad, folding forward over the map's face (kept small: it would hide the map)
var crease_memory := 0.6  # stiffness factor when folding further the crease's own way (theta > 0)
# A plate swinging back and forth keeps moving into its own wake: its drag coefficient is ~3-10
# (Keulegan-Carpenter data), not the ~1.2 of a plate in a steady stream, so its own swing is damped
# several times harder than the frame's motion through the air.
var self_drag := 4.0
# Walking (~1.4 m/s) the oncoming air presses the free edges towards the reader: a real bow, but it
# would pin them at limit_fwd. Past soft_fwd the crease stiffens (wall_k x its spring), so a steady
# walk bows it ~12 deg and gusts still give past that.
var soft_fwd := deg_to_rad(8.0)
var wall_k := 6.0

var theta := 0.0
var rate := 0.0


func _init(f := 1.0, z := 0.35, b := 3.0, g := 18.0, r := 0.1, lim_deg := 45.0, fwd_deg := 20.0) -> void:
	freq = f
	zeta = z
	beta = b
	gamma = g
	lever = r
	limit = deg_to_rad(lim_deg)
	limit_fwd = deg_to_rad(minf(fwd_deg, lim_deg))


## Advance by dt with the frame's normal acceleration a_n and normal air speed w_frame (m/s, the
## panel's frame only; its own swing is added here). Substeps internally at <= 1/240 s.
func step(dt: float, a_n: float, w_frame: float) -> void:
	var n := maxi(1, ceili(dt * 240.0))
	var h := dt / n
	var w0 := TAU * freq
	for i in n:
		var k := w0 * w0 * (crease_memory if theta > 0.0 else 1.0)
		# the panel is turned theta from its frame: only the part of the frame's motion along its own
		# normal pushes it, so as it swings edge-on the push fades (paper streamlines)
		var c := cos(theta)
		var wf := w_frame * c
		var w := wf + lever * rate
		# frame-driven drag explicit; the panel's own swing through the air as implicit damping
		var force := -k * theta - beta * a_n * c - gamma * wf * absf(w)
		if theta > soft_fwd:
			force -= wall_k * w0 * w0 * (theta - soft_fwd)
		var damp := 2.0 * zeta * w0 + gamma * self_drag * absf(w) * lever
		rate = (rate + h * force) / (1.0 + h * damp)
		theta += rate * h
		if theta < -limit or theta > limit_fwd:
			theta = clampf(theta, -limit, limit_fwd)
			rate = 0.0


func reset() -> void:
	theta = 0.0
	rate = 0.0
