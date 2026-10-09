class_name Locomotion
extends RefCounted
## Ground movement for the player: responsive like a person, never "on ice".
##
## This is the gameplay integrator, the part the server must reproduce exactly (spec §7). It runs
## once per fixed physics tick and uses only + - * / sqrt min max on scalar floats, so a TypeScript
## mirror gives the same answer. Everything cosmetic (head bob, roll, the lantern) lives elsewhere
## and is derived from this state.
##
## Model (research: Source/Unreal ground movement, grounded-game player feedback, gait data):
## - Brake = velocity-proportional drag + a constant floor: dv/dt = -(k|v| + D). Stops are quick
##   and end crisply (no exponential tail = no drift).
## - Velocity is split along/across the wish direction. The sideways part is always braked, so
##   releasing A/D or turning the view never leaves you sliding.
## - Pushing against your own momentum (A -> D) brakes *and* accelerates, so a reversal crosses
##   zero in ~0.08 s, like a person planting a foot.
## - Weight lives in the sprint: walk speed arrives in ~0.2 s, a sprint builds over ~0.55 s and
##   sheds its excess speed at a runner's braking rate (~11 m/s^2), so a sprint stop carries you
##   ~0.8 m. Real people take ~1 s to start and ~0.6 s to stop even when walking, but at those
##   timings a game reads as input lag ("drift"), so walking control stays quick and the human
##   cues (stride, footsteps, gaze, lantern) come from the camera and arm instead.
## - Strafe 0.8x, backpedal 0.7x (people sidestep far slower, but a maze needs usable strafing);
##   sprint only when moving mostly forward, limited by stamina.

const WALK_SPEED := 2.5  # m/s (spec walkSpeed)
const SPRINT_MULT := 1.8  # 4.5 m/s
const STRAFE_MULT := 0.8
const BACK_MULT := 0.7
const ACCEL_PUSH := 18.0  # m/s^2 from standing (push-off), easing to...
const ACCEL_WALK := 7.0  # ...this as you reach walk speed: half speed in ~80 ms, full in ~0.22 s
const ACCEL_SPRINT := 4.5  # m/s^2 from walk to sprint speed (runners: 3-7)
const DRAG := 7.0  # 1/s, velocity-proportional braking
const BRAKE := 5.0  # m/s^2, constant braking floor
const RUN_BRAKE := 11.0  # m/s^2, shedding speed above walk speed (runners peak at 6-9+)
const SPRINT_MIN_FORWARD := 0.7  # forward share of the wish direction needed to sprint (~45 deg)
const STAMINA_MAX := 6.0  # seconds of sprint
const STAMINA_REGEN_DELAY := 1.0
const STAMINA_REGEN_RATE := 0.75  # stamina seconds per second (full in 8 s)
const STAMINA_RESUME := 1.5  # once exhausted, sprint is unavailable until this much is back
const WALL_MEMORY_TICKS := 4  # contacts flicker tick to tick (the body rests a hair off the wall)

var vx := 0.0  # world planar velocity
var vz := 0.0
var stamina := STAMINA_MAX
var exhausted := false
var sprinting := false
var _regen_wait := 0.0
var _wall_n := PackedVector2Array()  # recently touched walls and the ticks each is remembered for
var _wall_ttl := PackedInt32Array()


## One fixed tick. input: x = right, y = back (WASD, each -1..1; analogue tilt < 1 walks slower).
## yaw: body yaw in radians. speed_mult: darkness / cart multipliers (spec §7). walls: horizontal
## normals (pointing away from the wall) of the walls touched on the previous tick.
func step(dt: float, input: Vector2, yaw: float, sprint_held: bool, speed_mult := 1.0,
		walls := PackedVector2Array()) -> void:
	var walk_cap := WALK_SPEED * speed_mult  # anything faster is running and sheds at RUN_BRAKE
	walls = _remember_walls(walls)
	var ix := input.x
	var iy := input.y
	var ilen := sqrt(ix * ix + iy * iy)
	if ilen < 0.001:
		_brake_all(dt, walk_cap)
		_update_stamina(dt, false)
		return
	var mag := minf(ilen, 1.0)
	ix /= ilen
	iy /= ilen
	var fwd := -iy  # forward share of the wish direction, -1..1
	# Direction speed: 1.0 forward, 0.8 sideways, 0.7 backwards, blended by the squared components.
	var dir_mult := (STRAFE_MULT + (1.0 - STRAFE_MULT) * fwd * fwd) if fwd >= 0.0 \
		else (STRAFE_MULT + (BACK_MULT - STRAFE_MULT) * fwd * fwd)
	sprinting = sprint_held and fwd >= SPRINT_MIN_FORWARD and not exhausted and stamina > 0.0
	var walk_target := WALK_SPEED * dir_mult * speed_mult * mag
	var target := walk_target * (SPRINT_MULT if sprinting else 1.0)

	# World wish direction: local (x right, z back) rotated by yaw.
	var c := cos(yaw)
	var s := sin(yaw)
	var wx := ix * c + iy * s
	var wz := -ix * s + iy * c
	# Walls: clip the wish against touched walls (Quake-style) so you glide along them at
	# speed x cos(angle) instead of sticking; pushing straight in just stops you.
	for n in walls:
		var d := wx * n.x + wz * n.y
		if d < 0.0:
			wx -= n.x * d
			wz -= n.y * d
	var wlen := sqrt(wx * wx + wz * wz)
	if wlen < 0.01:
		_brake_all(dt, walk_cap)
		_update_stamina(dt, false)
		return
	if wlen < 1.0:
		wx /= wlen
		wz /= wlen
		walk_target *= wlen
		target *= wlen

	var sp0 := sqrt(vx * vx + vz * vz)
	var p := vx * wx + vz * wz  # speed along the wish direction
	var px := vx - p * wx  # the sideways remainder
	var pz := vz - p * wz
	var plen := sqrt(px * px + pz * pz)
	if plen > 0.0:
		var k := _brake_speed(plen, dt, walk_cap) / plen
		px *= k
		pz *= k
	if p < -walk_cap - 0.001:
		# Reversing out of a sprint: plant and shed speed like a runner, not a 5 g wall.
		p = minf(-walk_cap, p + dt * (RUN_BRAKE + ACCEL_SPRINT))
	elif p < 0.0:
		p = minf(0.0, p + dt * (DRAG * -p + BRAKE + ACCEL_PUSH))
	elif p > target:
		p = maxf(target, _brake_speed(p, dt, walk_cap))
	else:
		var accel := ACCEL_SPRINT
		if p < walk_target:
			accel = ACCEL_PUSH - (ACCEL_PUSH - ACCEL_WALK) * p / walk_target
		p = minf(target, p + accel * dt)
	vx = p * wx + px
	vz = p * wz + pz
	# The sideways part only ever brakes: never end faster than the target or the previous speed.
	var sp1 := sqrt(vx * vx + vz * vz)
	var cap := maxf(target, sp0)
	if sp1 > cap:
		vx *= cap / sp1
		vz *= cap / sp1
	_update_stamina(dt, sprinting and p > walk_target * 1.05)


## Feed back the velocity after collision so momentum never pushes into walls.
func set_velocity(x: float, z: float) -> void:
	vx = x
	vz = z


func speed() -> float:
	return sqrt(vx * vx + vz * vz)


## Merge this tick's wall contacts into a short memory. A remembered wall only clips motion *into*
## it, so keeping it a few ticks is harmless, and it stops flickering contacts from making wall
## slides stutter between clipped and unclipped.
func _remember_walls(walls: PackedVector2Array) -> PackedVector2Array:
	for i in range(_wall_ttl.size() - 1, -1, -1):
		_wall_ttl[i] -= 1
		if _wall_ttl[i] <= 0:
			_wall_n.remove_at(i)
			_wall_ttl.remove_at(i)
	for n in walls:
		var found := false
		for i in _wall_n.size():
			if _wall_n[i].dot(n) > 0.999:
				_wall_n[i] = n
				_wall_ttl[i] = WALL_MEMORY_TICKS
				found = true
		if not found:
			_wall_n.append(n)
			_wall_ttl.append(WALL_MEMORY_TICKS)
	return _wall_n


## Horizontal normals of the walls a body touched in its last move_and_slide (for `walls`).
static func wall_normals(body: CharacterBody3D) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in body.get_slide_collision_count():
		var n := body.get_slide_collision(i).get_normal()
		if absf(n.y) < 0.7:
			out.append(Vector2(n.x, n.z).normalized())
	return out


func _brake_all(dt: float, walk_cap: float) -> void:
	sprinting = false
	var sp := sqrt(vx * vx + vz * vz)
	if sp <= 0.0:
		return
	var k := _brake_speed(sp, dt, walk_cap) / sp
	vx *= k
	vz *= k


## Speed after braking for one tick: a runner's constant deceleration down to walk speed, then
## drag plus a constant floor, which reaches exactly zero (no creeping tail).
func _brake_speed(sp: float, dt: float, walk_cap: float) -> float:
	if sp > walk_cap + 0.001:  # margin: engine velocities are 32-bit (2.5 comes back as 2.5000002)
		return maxf(walk_cap, sp - RUN_BRAKE * dt)
	return maxf(0.0, sp - dt * (DRAG * sp + BRAKE))


func _update_stamina(dt: float, draining: bool) -> void:
	if draining:
		stamina = maxf(0.0, stamina - dt)
		_regen_wait = STAMINA_REGEN_DELAY
		if stamina <= 0.0:
			exhausted = true
		return
	if _regen_wait > 0.0:
		_regen_wait -= dt
		return
	stamina = minf(STAMINA_MAX, stamina + STAMINA_REGEN_RATE * dt)
	if exhausted and stamina >= STAMINA_RESUME:
		exhausted = false
