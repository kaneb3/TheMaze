class_name HeadMotion
extends RefCounted
## Cosmetic camera motion derived from the locomotion state: stride-locked bob, footsteps,
## strafe roll, a small nod when you start or stop, and a sprint FOV ease. Never feeds back into
## movement, and every effect has an accessibility scale (0 = off).
##
## - The stride phase advances with distance travelled (pi per step), never with wall-clock time,
##   so bob, footsteps and the lantern stay locked together. Step length grows with speed
##   (cadence and step-length data from gait studies).
## - Footfalls are the low points of a |sin| bob (the body vaults over the stance leg, and in a
##   run the flight arcs meet at contact). Lateral sway is one cycle per two steps.
## - People stabilise their gaze: the head pitches *against* its vertical bob to keep the eyes on a
##   point a few metres ahead, so the far view stays steady while the near floor moves.
## - When you stop, the bob eases back to neutral in ~0.15 s instead of freezing mid-stride.

# Step length: walking follows L = 0.68 (v/1.3)^0.42 (Grieve; fits measured 114-139 steps/min),
# stretched 10% because game walking (2.5 m/s) is faster than people walk; a brisk 2.5 m/s walk
# then steps at ~2.55 Hz (measured head-bob frequency tops out at ~2.5 Hz). Running steps at
# ~175/min (2.9 Hz): L = v / 2.92.
const STEP_STRETCH := 1.1
const RUN_CADENCE := 2.92  # steps/s
const BOB_V_WALK := 0.018  # m, vertical bob peak to trough (people: 4-5 cm; games keep 1-2.5 cm)
const BOB_V_RUN := 0.038  # (people: 7-10 cm; games 2.5-4.5 cm)
const BOB_L_WALK := 0.010  # m, lateral sway peak to trough, one cycle per two steps
const BOB_L_RUN := 0.012
const GAZE_DIST := 3.0  # m, the point ahead the eyes hold steady
const ROLL_STRAFE := 1.0  # deg at full sideways walk speed
const ROLL_STRIDE := 0.25  # deg, residual head roll with each step (gaze stabilised)
const NOD_GAIN := 0.06  # deg per m/s^2 of forward acceleration
const NOD_MAX := 0.8  # deg
const FOV_KICK := 4.0  # deg at full sprint
const MIN_STEP_SPEED := 0.4  # m/s, below this no new footsteps

var bob_scale := 1.0
var roll_scale := 1.0
var fov_scale := 1.0

# outputs (camera-local)
var offset := Vector3.ZERO
var roll := 0.0  # radians, about the view axis
var pitch := 0.0  # radians, added to the view pitch
var fov_add := 0.0  # degrees
var stride_phase := 0.7 * PI  # radians, pi per step (starts ~0.3 of a step before a footfall)
var gait := 0.0  # 0 walk .. 1 run
var amount := 0.0  # 0 standing .. 1 full stride
var footsteps := 0  # total footfalls so far (watch for changes to play a step sound)
var last_foot := 0  # 0 left, 1 right (the head sways over the stance foot)
var soft_step := false  # the latest footfall was the quiet closing step of a stop

var _v := Vector2.ZERO  # smoothed planar velocity (body frame: x right, y forward)
var _a_fwd := 0.0
var _nod := 0.0
var _nod_v := 0.0
var _standing := true


## dt: frame time. vel: world velocity. yaw: body yaw. sprinting: locomotion sprint state.
func update(dt: float, vel: Vector3, yaw: float, sprinting: bool) -> void:
	# Velocity in the body frame (x right, y forward), lightly smoothed for derivatives.
	var c := cos(yaw)
	var s := sin(yaw)
	var local := Vector2(vel.x * c - vel.z * s, -(vel.x * s + vel.z * c))
	var a := 1.0 - exp(-dt / 0.04)
	var v_new := _v + (local - _v) * a
	var a_fwd_raw := (v_new.y - _v.y) / maxf(dt, 1e-4)
	_v = v_new
	_a_fwd += (a_fwd_raw - _a_fwd) * (1.0 - exp(-dt / 0.05))
	var speed := local.length()

	gait += (smoothstep(2.7, 4.3, speed) - gait) * (1.0 - exp(-dt / 0.2))
	var target_amount := clampf(speed / 2.25, 0.0, 1.0) if speed > MIN_STEP_SPEED else 0.0
	amount += (target_amount - amount) * (1.0 - exp(-dt / (0.1 if target_amount > amount else 0.05)))

	# Stride phase from distance.
	if speed > MIN_STEP_SPEED:
		_standing = false
		var walk_len := 0.68 * pow(speed / 1.3, 0.42) * STEP_STRETCH
		var step_len := lerpf(walk_len, speed / RUN_CADENCE, gait)
		var before := floori(stride_phase / PI)
		stride_phase += PI * speed * dt / step_len
		var after := floori(stride_phase / PI)
		if after != before:
			footsteps += after - before
			last_foot = (after + 1) % 2
			soft_step = false
	elif not _standing and amount < 0.25:
		# Stopping: the trailing foot comes alongside with a quiet closing step (unless a footfall
		# just happened), and the next walk starts with its first step landing ~0.3 of a step in.
		_standing = true
		if fposmod(stride_phase, PI) > 0.3 * PI:
			footsteps += 1
			last_foot = 1 - last_foot
			soft_step = true
		stride_phase = (floorf(stride_phase / PI) + 0.7) * PI

	var amp_v := lerpf(BOB_V_WALK, BOB_V_RUN, gait) * amount * bob_scale
	var amp_l := lerpf(BOB_L_WALK, BOB_L_RUN, gait) * amount * bob_scale
	var sp := sin(stride_phase)
	offset = Vector3(sp * amp_l * 0.5, (absf(sp) - 0.637) * amp_v, 0.0)
	var gaze_pitch := -offset.y / GAZE_DIST

	# Strafe roll (lean into the sideways motion) plus a tiny per-step roll.
	var roll_target := deg_to_rad(-ROLL_STRAFE * clampf(_v.x / 2.25, -1.5, 1.5)) * roll_scale
	roll_target += deg_to_rad(ROLL_STRIDE) * sp * amount * roll_scale
	roll += (roll_target - roll) * (1.0 - exp(-dt / 0.06))

	# Nod: a critically damped spring pushed by forward acceleration (stop -> nod down, settle).
	var nod_target := clampf(_a_fwd * NOD_GAIN, -NOD_MAX, NOD_MAX) * bob_scale
	# Sub-stepped so a long frame (hitch, low fps) can't make the spring unstable.
	var w := TAU * 3.0
	var n := ceili(dt / (1.0 / 240.0))
	var h := dt / n
	for i in n:
		_nod_v += ((nod_target - _nod) * w * w - 2.0 * w * _nod_v) * h
		_nod += _nod_v * h
	pitch = deg_to_rad(_nod) + gaze_pitch

	var fov_target := FOV_KICK * gait * (1.0 if sprinting else 0.0) * fov_scale
	fov_add += (fov_target - fov_add) * (1.0 - exp(-dt / 0.12))
