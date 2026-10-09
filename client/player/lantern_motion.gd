class_name LanternMotion
extends RefCounted
## Weighty first-person lantern motion: an inertial arm carrying a hand-damped pendulum.
##
## Model (from research into carried-pendulum physics and viewmodel practice):
## - Body velocity is smoothed (half-life 0.12 s); its rate of change is the body acceleration, so
##   starts/stops push the arm without one-frame kicks.
## - The arm is two damped springs in camera space: translation (1.6 Hz, zeta 0.8; 2.2 Hz, 0.9 when
##   running) and rotation/look lag (2.1 Hz, zeta 0.7). Inertia shifts the arm's target opposite
##   to acceleration; the arm sags a little under the weight.
## - The lantern (effective length 0.31 m, ~0.9 Hz) hangs world-vertical. It is driven by the arm's
##   *computed* acceleration (low-passed at 4 Hz) through a coupling < 1 (the arm absorbs some), with
##   damping zeta 0.35 walking / 0.55 running (a hand actively steadies it) and soft caps.
## - Effective gravity varies with vertical acceleration: heavy at footfall, near-weightless in a
##   running stride's flight phase. The hand counter-moves towards the swing (~80 ms delay).
## - Running blends in a braced pose (hand up, in and closer) with a real stride cadence
##   (f_step = 1.43 + 0.29 v), a footfall dip and a chain "clunk".
## All motion is integrated at a fixed sub-step for frame-rate independence.

const G := 9.8
const PEND_L := 0.31
const WALK_T := Vector2(1.6, 0.8)  # translation spring: frequency (Hz), damping ratio
const RUN_T := Vector2(2.2, 0.9)
const ROT := Vector2(2.1, 0.7)
const PEND_ZETA := Vector2(0.42, 0.58)  # walk, run
const TURN_COUPLING := 0.35  # the arm braces against fast view turns (games turn far faster than bodies)
const COUPLING := Vector2(0.6, 0.4)  # walk, run
const CAP_FWD := 0.30
const CAP_SIDE := 0.22
const TWIST := Vector2(0.6, 0.3)
const TWIST_GAIN := 0.3
const TWIST_CAP := 0.26  # ~15 deg
const RUN_POSE := Vector3(0.05, 0.06, 0.03)  # towards the midline, up, closer to the body
const SAG := 0.02
const INERTIA_GAIN := 0.3
const DRIVE_LOWPASS_HZ := 4.0
const VEL_HALF_LIFE := 0.12
const RUN_BLEND_HALF_LIFE := 0.25

# outputs
var hand_offset := Vector3.ZERO  # camera-local
var hand_rotation := Vector3.ZERO  # euler, camera-local
var swing := Vector2.ZERO  # displayed pendulum angles (x: fore-aft, y: sideways), radians
var swing_velocity := Vector2.ZERO
var twist := 0.0
var stretch := 0.0  # extra hang length from chain/ring load (metres)
var head_bob := 0.0
var run_weight := 0.0
var move_amount := 0.0

var _hand_rest := Vector3.ZERO
var _v_smooth := Vector3.ZERO
var _a_body := Vector3.ZERO
var _t_vel := Vector3.ZERO
var _t_acc := Vector3.ZERO
var _r_vel := Vector3.ZERO
var _look_rate := Vector2.ZERO
var _yaw_rate_prev := 0.0
var _yaw_acc := 0.0
var _drive := Vector3.ZERO
var _theta := Vector2.ZERO
var _theta_late := Vector2.ZERO
var _twist_vel := 0.0
var _stretch_vel := 0.0
var _step_phase := 0.0
var _time := 0.0


func _init(hand_rest: Vector3) -> void:
	_hand_rest = hand_rest


## Advance by one fixed sub-step.
## body_velocity: world m/s. cam_basis: camera global basis. yaw: body yaw (rad).
## look_rate: (yaw, pitch) view rotation rate in rad/s (positive yaw = turning left).
func step(dt: float, body_velocity: Vector3, cam_basis: Basis, yaw: float, look_rate: Vector2) -> void:
	_time += dt
	var yaw_basis := Basis(Vector3.UP, yaw)

	# Body: smoothed velocity and its acceleration.
	var v_new := _v_smooth + (body_velocity - _v_smooth) * (1.0 - pow(0.5, dt / VEL_HALF_LIFE))
	_a_body = (v_new - _v_smooth) / dt
	_v_smooth = v_new
	var speed := Vector2(_v_smooth.x, _v_smooth.z).length()
	run_weight += (smoothstep(3.0, 5.0, speed) - run_weight) * (1.0 - pow(0.5, dt / RUN_BLEND_HALF_LIFE))
	move_amount += (clampf(speed / 2.5, 0.0, 1.0) - move_amount) * (1.0 - exp(-8.0 * dt))

	# Stride: one footfall per TAU of phase.
	if speed > 0.15:
		_step_phase += TAU * (1.43 + 0.29 * speed) * dt
	var stride := _step_phase * 0.5
	var bob_v := lerpf(0.010, 0.024, run_weight) * move_amount
	var bob_h := lerpf(0.006, 0.010, run_weight) * move_amount
	var bob := Vector3(sin(stride) * bob_h, (absf(sin(stride)) - 0.5) * bob_v, 0.0)
	head_bob = (absf(sin(stride)) - 0.5) * lerpf(0.016, 0.03, run_weight) * move_amount

	# View rotation rate (low-passed) and yaw acceleration.
	_look_rate += (look_rate - _look_rate) * (1.0 - exp(-TAU * 10.0 * dt))
	var yaw_acc_raw := (_look_rate.x - _yaw_rate_prev) / dt
	_yaw_rate_prev = _look_rate.x
	_yaw_acc += (yaw_acc_raw - _yaw_acc) * (1.0 - exp(-TAU * 6.0 * dt))

	# Arm translation spring (camera-local).
	var cam_inv := cam_basis.inverse()
	var f_t := lerpf(WALK_T.x, RUN_T.x, run_weight)
	var z_t := lerpf(WALK_T.y, RUN_T.y, run_weight)
	var w_t := TAU * f_t
	var inertia := -(cam_inv * _a_body) * INERTIA_GAIN / (w_t * w_t)
	var turn_lag := Vector3(clampf(_look_rate.x * 0.012, -0.03, 0.03), clampf(_look_rate.y * 0.008, -0.02, 0.02), 0.0)
	var counter_world := yaw_basis * Vector3(0.4 * PEND_L * sin(_theta_late.y), 0.0, -0.4 * PEND_L * sin(_theta_late.x))
	var breathe := Vector3(sin(_time * 0.53) * 0.002, sin(_time * 1.35) * 0.003, 0.0)
	var run_pose := RUN_POSE * run_weight
	var target := run_pose + bob + breathe + Vector3(0.0, -SAG, 0.0) + inertia + turn_lag + cam_inv * counter_world
	_t_acc = (target - hand_offset) * (w_t * w_t) - _t_vel * (2.0 * z_t * w_t)
	_t_vel += _t_acc * dt
	hand_offset += _t_vel * dt

	# Arm rotation spring: look lag, stride roll and a wrist roll towards the swing.
	var w_r := TAU * ROT.x
	var rot_target := Vector3(
		clampf(-_look_rate.y * 0.02, -0.08, 0.08) + sin(_time * 1.35) * 0.008 + swing.x * 0.15,
		clampf(-_look_rate.x * 0.025, -0.12, 0.12),
		sin(stride) * 0.03 * move_amount + swing.y * 0.15)
	var r_acc := (rot_target - hand_rotation) * (w_r * w_r) - _r_vel * (2.0 * ROT.y * w_r)
	_r_vel += r_acc * dt
	hand_rotation += _r_vel * dt

	# Pivot acceleration in world space: body + arm spring + rotation about the eye when turning.
	var r_h := yaw_basis * Vector3(_hand_rest.x, 0.0, _hand_rest.z)
	var a_turn := (Vector3(0.0, _yaw_acc, 0.0).cross(r_h) - r_h * (_look_rate.x * _look_rate.x)) * TURN_COUPLING
	var a_pivot := _a_body + cam_basis * _t_acc + a_turn
	_drive += (a_pivot - _drive) * (1.0 - exp(-TAU * DRIVE_LOWPASS_HZ * dt))

	# Hand-damped pendulum with variable effective gravity.
	var g_eff := clampf(G + _drive.y, 0.2 * G, 2.2 * G)
	var a_local := yaw_basis.inverse() * _drive
	var coupling := lerpf(COUPLING.x, COUPLING.y, run_weight)
	var c := 2.0 * lerpf(PEND_ZETA.x, PEND_ZETA.y, run_weight) * sqrt(G / PEND_L)
	var drive := Vector2(a_local.z, -a_local.x) * coupling / PEND_L
	var th_acc := Vector2(
		-(g_eff / PEND_L) * sin(_theta.x) - c * swing_velocity.x + drive.x * cos(_theta.x),
		-(g_eff / PEND_L) * sin(_theta.y) - c * swing_velocity.y + drive.y * cos(_theta.y))
	swing_velocity += th_acc * dt
	_theta += swing_velocity * dt
	_theta_late += (_theta - _theta_late) * (1.0 - exp(-dt / 0.08))
	swing = Vector2(CAP_FWD * tanh(_theta.x / CAP_FWD), CAP_SIDE * tanh(_theta.y / CAP_SIDE))

	# Twist about the chain when turning.
	var w_tw := TAU * TWIST.x
	var tw_acc := -w_tw * w_tw * twist - 2.0 * TWIST.y * w_tw * _twist_vel - TWIST_GAIN * _yaw_acc
	_twist_vel += tw_acc * dt
	twist = clampf(twist + _twist_vel * dt, -TWIST_CAP, TWIST_CAP)

	# Ring/chain stretch under load: a small "clunk" after a running stride's flight phase.
	var w_s := TAU * 7.0
	var s_acc := ((g_eff / G - 1.0) * 0.004 - stretch) * w_s * w_s - _stretch_vel * 2.0 * 0.3 * w_s
	_stretch_vel += s_acc * dt
	stretch += _stretch_vel * dt
