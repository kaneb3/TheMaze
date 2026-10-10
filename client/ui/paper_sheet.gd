class_name PaperSheet
extends RefCounted
## Moves the hand-held map's paper live, from how it actually moves through the air: PaperHinges on
## map.glb's crease bones (art/scripts/fp_map.py), updated from the held corner outwards so the lag
## travels to the free edge.
##
## Readability first (user, 2026-10-10):
##  - The big creases only feel the air while the map is coming out or going away (`forcing` 1 -> 0
##    once it is up): it blows back as it is whipped up, follows through softly and settles, and then
##    holds still to be read, whatever you do.
##  - Walking and turning stir only the top-left corner, a few millimetres (`corner_lift()`, applied as
##    a smooth displacement in map_parchment.gdshader so the sheet stays one continuous piece).
##  - A horizontal fold bends by ONE angle across the whole width (the three columns' row and curl
##    bones move together): per-column angles sheared the columns past each other at the vertical
##    creases and the sheet read as three overlapping strips.
##
## Per hinge, each frame: a point on the panel it swings, carried rigidly by the parent bone (its own
## swing excluded; PaperHinge adds that), gives the frame's velocity and acceleration in world space;
## only their components along the panel's normal bend it. The authored open shape (map.glb's "rest"
## pose) is what the hinges settle back to.

# name, bones moved together, probe point on the moved panel and hinge axis (skeleton space: x right,
# y up, z towards the eye; the sheet is 0.40 x 0.30 m centred on the origin), then f Hz, zeta, beta,
# gamma, lever m, limit deg (bending back; folding forward over the face is held to 20 deg).
const LINKS := [
	["colR", ["colR"], Vector3(-0.0667, 0.0, 0.0), Vector3.UP, 1.3, 0.45, 2.5, 18.0, 0.133, 25.0],
	["colL", ["colL"], Vector3(-0.1333, 0.0, 0.0), Vector3.UP, 0.8, 0.45, 3.5, 20.0, 0.067, 40.0],
	["row", ["rowR", "rowC", "rowL"], Vector3(0.0, 0.075, 0.0), Vector3.RIGHT, 0.9, 0.45, 3.0, 18.0, 0.075, 35.0],
	["curl", ["curlR", "curlC", "curlL"], Vector3(0.0, 0.1125, 0.0), Vector3.RIGHT, 1.6, 0.45, 3.5, 18.0, 0.037, 25.0],
]
# The top-left corner: a small, quick flap, the only part that answers walking and turning.
# (drag and inertia scaled well down from the creases': a walk bows it ~2-3 mm, not pinned at the cap)
const CORNER := ["curlL", Vector3(-0.17, 0.13, 0.0), 1.8, 0.5, 1.0, 2.0, 0.05]
const CORNER_MAX := 0.005  # m: how far the corner may lift or drop (kept small: the map must stay readable)
const CORNER_FLUTTER := 0.0015  # m: a little irregular flutter on top, only when air is moving past
const ACCEL_LOWPASS_HZ := 15.0  # finite-differenced acceleration is noisy; paper doesn't feel >15 Hz
# The pop-up is a fast whip: at full physical strength the far column folded right over the map's
# face as it arrived. Readability first: the air's push at 60%.
const AIR := 0.6

var _skel: Skeleton3D
var _links: Array = []  # dicts
var _corner: Dictionary
var _corner_lift := 0.0
var _time := 0.0
var _noise := FastNoiseLite.new()


## Call once the skeleton holds the authored open ("rest") pose: that pose is what the creases settle to.
func _init(skeleton: Skeleton3D) -> void:
	_skel = skeleton
	_noise.frequency = 1.0
	for row in LINKS:
		var bones: Array = []
		for name in row[1]:
			var b := _skel.find_bone(name)
			if b >= 0:
				var g := _skel.get_bone_global_pose(b)
				bones.append({"bone": b, "base_rot": _skel.get_bone_pose_rotation(b),
					"axis": (g.basis.inverse() * (row[3] as Vector3)).normalized()})
		if bones.is_empty():
			continue
		var link := _probe(bones[0].bone, row[2])
		link["bones"] = bones
		link["hinge"] = PaperHinge.new(row[4], row[5], row[6] * AIR, row[7] * AIR, row[8], row[9])
		_links.append(link)
	var cb := _skel.find_bone(CORNER[0])
	if cb >= 0:
		_corner = _probe(cb, CORNER[1])
		_corner["hinge"] = PaperHinge.new(CORNER[2], CORNER[3], CORNER[4], CORNER[5], CORNER[6], 30.0, 30.0)


## Kinematic probe: a point on the panel a bone swings, followed through the bone's parent with the
## bone at its rest angle (so the hinge's own swing isn't counted twice).
func _probe(bone: int, point: Vector3) -> Dictionary:
	var g := _skel.get_bone_global_pose(bone)
	return {"bone": bone, "parent": _skel.get_bone_parent(bone), "base_local": _skel.get_bone_pose(bone),
		"point": g.affine_inverse() * point, "normal": (g.basis.inverse() * Vector3.BACK).normalized(),
		"q1": Vector3.ZERO, "q2": Vector3.ZERO, "af": Vector3.ZERO, "fresh": true}


## Forget the motion history (call when the map appears, so the first frame isn't read as a jump).
func reset() -> void:
	for l in _links:
		l.fresh = true
		l.af = Vector3.ZERO
		(l.hinge as PaperHinge).reset()
		for b in l.bones:
			_skel.set_bone_pose_rotation(b.bone, b.base_rot)
	if not _corner.is_empty():
		_corner.fresh = true
		_corner.af = Vector3.ZERO
		(_corner.hinge as PaperHinge).reset()
	_corner_lift = 0.0


## Advance by dt. forcing (0..1): how much the air moves the big creases (1 while the map is coming
## out or going away, 0 once it is up to be read; the corner always feels it).
func update(dt: float, forcing := 1.0) -> void:
	if dt <= 0.0:
		return
	_time += dt
	for l in _links:
		var k: Vector2 = _kinematics(l, dt)
		var h: PaperHinge = l.hinge
		h.step(dt, k.x * forcing, k.y * forcing)
		for b in l.bones:
			_skel.set_bone_pose_rotation(b.bone, (b.base_rot as Quaternion) * Quaternion(b.axis, h.theta))
	if not _corner.is_empty():
		var k: Vector2 = _kinematics(_corner, dt)
		var h: PaperHinge = _corner.hinge
		h.step(dt, k.x, k.y)
		var air := smoothstep(0.3, 1.5, absf(k.y) + absf(_corner.v_inplane))
		var flutter := _noise.get_noise_1d(_time * 2.7) * CORNER_FLUTTER * air
		_corner_lift = clampf(h.theta * h.lever + flutter, -CORNER_MAX, CORNER_MAX)


## The probe's frame acceleration and velocity along the panel's normal: Vector2(a_n, w_n).
func _kinematics(l: Dictionary, dt: float) -> Vector2:
	var parent_world: Transform3D = _skel.global_transform * _skel.get_bone_global_pose(l.parent)
	var frame: Transform3D = parent_world * (l.base_local as Transform3D)
	var q: Vector3 = frame * (l.point as Vector3)
	var n: Vector3 = (frame.basis * (l.normal as Vector3)).normalized()
	if l.fresh:
		l.q1 = q
		l.q2 = q
		l.fresh = false
	var v: Vector3 = (q - l.q1) / dt
	var a: Vector3 = (q - 2.0 * l.q1 + l.q2) / (dt * dt)
	l.af = (l.af as Vector3).lerp(a, 1.0 - exp(-dt * TAU * ACCEL_LOWPASS_HZ))
	l.q2 = l.q1
	l.q1 = q
	l["v_inplane"] = (v - n * v.dot(n)).length()
	return Vector2((l.af as Vector3).dot(n), v.dot(n))


## How far the top-left corner is lifted towards the eye (m, negative = back): map_parchment's corner_lift.
func corner_lift() -> float:
	return _corner_lift


## The largest crease deflection right now (rad): for tests and debugging.
func max_bend() -> float:
	var m := 0.0
	for l in _links:
		m = maxf(m, absf((l.hinge as PaperHinge).theta))
	return m
