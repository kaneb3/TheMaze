"""Helpers for the first-person lantern-hand viewmodel (HandWork scene in art/characters.blend).

exec(open(r"<repo>/art/scripts/fp_viewmodel.py").read(), g); g["place"](twist_extra, cam_rel)
"""

import math
from math import asin, cos, pi, radians, sin

import bpy
from mathutils import Matrix, Quaternion, Vector
from mathutils.bvhtree import BVHTree

CAM_REL = Vector((0.28, -0.39, 0.068))     # game camera relative to the grip (Blender axes)
ELBOW_FROM_CAM = Vector((-0.30, 0.05, -0.36))  # elbow sits just outside the bottom-left corner
RING_RADIUS = 0.025
LANTERN_SCALE = 0.5


def grip_point(rig):
    P = lambda n: rig.matrix_world @ rig.pose.bones[n].head
    T = lambda n: rig.matrix_world @ rig.pose.bones[n].tail
    mid = lambda n: (P(n) + T(n)) / 2
    return (mid("index.02") + mid("ring.02")) * 0.3 + (P("index.01") + P("ring.01")) * 0.2 + Vector((0, 0.004, 0))


def place(twist_extra=0.0, cam_rel=CAM_REL):
    """Orient the arm so the forearm runs from the grip towards the elbow and the back of the hand faces
    the camera (plus `twist_extra` degrees of roll about the forearm). Returns the roll used."""
    root = bpy.data.objects["FPArm2"]
    rig = bpy.data.objects["HandRig"]
    root.matrix_world = Matrix.Identity(4)
    bpy.context.view_layer.update()
    g = grip_point(rig)
    f = (cam_rel + ELBOW_FROM_CAM).normalized()
    c = cam_rel.normalized()

    def frame(deg):
        x = Quaternion(f, radians(deg)) @ Vector((-1, 0, 0))
        x = (x - x.dot(f) * f).normalized()
        return x, f.cross(x)

    best = max(range(-180, 181, 3), key=lambda d: (-frame(d)[1]).dot(c) + 0.35 * (-frame(d)[1]).dot(Vector((0, 0, 1))))
    deg = best + twist_extra
    x, y = frame(deg)
    R = Matrix((x, y, f)).transposed().to_4x4()
    root.matrix_world = Matrix.Translation(-(R @ g)) @ R
    bpy.context.view_layer.update()
    bar = (R.to_3x3() @ Vector((1, 0, 0))).normalized()
    ring = bpy.data.objects.get("FP2Ring")
    if ring:
        ring.rotation_mode = 'QUATERNION'
        ring.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(bar.cross(Vector((0, 0, 1))).normalized())
    bpy.data.objects["FP2Cam"].location = cam_rel
    return deg


def build_ring(collection, material):
    """One clear dark-iron carrying ring, hooked by the fingers at the grip point (origin)."""
    old = bpy.data.objects.get("FP2Ring")
    if old:
        bpy.data.objects.remove(old, do_unlink=True)
    cu = bpy.data.curves.new("FP2Ring", 'CURVE')
    cu.dimensions = '3D'
    cu.bevel_depth = 0.0034
    cu.bevel_resolution = 4
    sp = cu.splines.new('POLY')
    n = 48
    sp.points.add(n - 1)
    for i, p in enumerate(sp.points):
        a = 2 * pi * i / n
        p.co = (RING_RADIUS * cos(a), RING_RADIUS * sin(a), 0, 1)
    sp.use_cyclic_u = True
    ring = bpy.data.objects.new("FP2Ring", cu)
    collection.objects.link(ring)
    cu.materials.append(material)
    ring.location = (0, 0, -RING_RADIUS + 0.003)
    return ring


# ---------------------------------------------------------------------------------------------
# Carrying hoop (replaces the round FP2Ring, 2026-10-09). The fist's finger curl forms a straight
# tunnel along the knuckle line (measured by slicing GloveHand: centre y=-0.0095, z=+0.001, 5-9 mm
# clearance from index to little finger). A round ring can't lie in a straight tunnel, so the hoop
# is pear-shaped: a straight top bar hidden in the fist, leaving past the thumb and the little
# finger, curving down to the eye the lantern hangs from. In-game it hinges about the bar.

HOOP_BAR = Vector((0.0, -0.0095, 0.001))  # bar centre line (grip space)
HOOP_WIRE = 0.003  # wire radius (6 mm rod: ship-lantern hoops are 4-6 mm; thicker reads as a toy)
# uL/uR: bar ends (little-finger / index side); rcL/rcR: corner radii; ue: eye position along the
# bar; H: eye depth below the bar; rb: eye curve radius; tilt: rest hinge angle (deg).
# Hand-forged outline (control points, u along the bar, v down): the wire starts bending down as it
# leaves the grip, bows slightly outward past the thumb / little finger and tapers into the eye.
HOOP = dict(points=[(-0.050, 0.0), (-0.02, 0.0), (0.01, 0.0), (0.044, 0.0),
                    (0.060, -0.006), (0.068, -0.030), (0.062, -0.052),
                    (0.031, -0.067), (0.016, -0.086), (0.001, -0.067),
                    (-0.064, -0.050), (-0.070, -0.027), (-0.061, -0.006)],
            ue=0.016, H=0.086, tilt=0.0)
# Worn wooden grip sleeve on the bar: it fills the finger tunnel so the fist closes on something,
# and stands ~1 cm proud of the index finger with a turned, rounded end and a thin ferrule band.
GRIP = dict(u0=-0.054, u1=0.047, knob_from=0.037, knob_r=0.0088)  # flared knob end outside the fist


def _hull(pts):
    pts = sorted(set(pts))

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

    lo, up = [], []
    for p in pts:
        while len(lo) >= 2 and cross(lo[-2], lo[-1], p) <= 0:
            lo.pop()
        lo.append(p)
    for p in reversed(pts):
        while len(up) >= 2 and cross(up[-2], up[-1], p) <= 0:
            up.pop()
        up.append(p)
    return lo[:-1] + up[:-1]


def hoop_outline(uL, uR, rcL, rcR, ue, H, rb, sR=0.0, n=160, **_):
    """Wire centre line in the hoop plane (u along the bar, v down is negative): the convex hull of
    two corner circles touching the bar, an optional index-side shoulder (the leg drops straight
    to depth sR, clear of the thumb) and the bottom eye circle, resampled evenly."""
    pts = []
    circles = [((uL + rcL, -rcL), rcL), ((uR - rcR, -rcR), rcR), ((ue, -H + rb), rb)]
    if sR > 0:
        circles.append(((uR - rcR, -sR), rcR))
    for (cx, cy), r in circles:
        for i in range(720):
            a = 2 * math.pi * i / 720
            pts.append((round(cx + r * math.cos(a), 7), round(cy + r * math.sin(a), 7)))
    h = _hull(pts)
    h.append(h[0])
    L = [0.0]
    for a, b in zip(h, h[1:]):
        L.append(L[-1] + math.dist(a, b))
    out, j = [], 0
    for k in range(n):
        s = L[-1] * k / n
        while L[j + 1] < s:
            j += 1
        t = (s - L[j]) / (L[j + 1] - L[j])
        a, b = h[j], h[j + 1]
        out.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
    return out


def hoop_spline(points, n=160, **_):
    """Hand-forged outline: a closed centripetal Catmull-Rom curve through control points (u, v),
    resampled evenly. Points run around the hoop; the bar's points keep the top straight."""
    P = [Vector((u, v, 0.0)) for u, v in points]
    m = len(P)
    dense = []
    for i in range(m):
        p0, p1, p2, p3 = P[i - 1], P[i], P[(i + 1) % m], P[(i + 2) % m]
        t0 = 0.0
        t1 = t0 + max((p1 - p0).length ** 0.5, 1e-6)
        t2 = t1 + max((p2 - p1).length ** 0.5, 1e-6)
        t3 = t2 + max((p3 - p2).length ** 0.5, 1e-6)
        for k in range(40):
            t = t1 + (t2 - t1) * k / 40
            a1 = p0 * ((t1 - t) / (t1 - t0)) + p1 * ((t - t0) / (t1 - t0))
            a2 = p1 * ((t2 - t) / (t2 - t1)) + p2 * ((t - t1) / (t2 - t1))
            a3 = p2 * ((t3 - t) / (t3 - t2)) + p3 * ((t - t2) / (t3 - t2))
            b1 = a1 * ((t2 - t) / (t2 - t0)) + a2 * ((t - t0) / (t2 - t0))
            b2 = a2 * ((t3 - t) / (t3 - t1)) + a3 * ((t - t1) / (t3 - t1))
            c = b1 * ((t2 - t) / (t2 - t1)) + b2 * ((t - t1) / (t2 - t1))
            dense.append((c.x, c.y))
    dense.append(dense[0])
    L = [0.0]
    for a, b in zip(dense, dense[1:]):
        L.append(L[-1] + math.dist(a, b))
    out, j = [], 0
    for k in range(n):
        s_ = L[-1] * k / n
        while L[j + 1] < s_:
            j += 1
        t = (s_ - L[j]) / max(L[j + 1] - L[j], 1e-12)
        a, b = dense[j], dense[j + 1]
        out.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
    return out


def outline(params):
    return hoop_spline(**params) if "points" in params else hoop_outline(**params)


def build_hoop(collection, material, params=HOOP):
    """FP2Hoop curve at the bar, tilted to its rest hinge angle. Returns (hoop, eye_world)."""
    old = bpy.data.objects.get("FP2Hoop")
    if old:
        bpy.data.objects.remove(old, do_unlink=True)
    cu = bpy.data.curves.new("FP2Hoop", 'CURVE')
    cu.dimensions = '3D'
    cu.bevel_depth = HOOP_WIRE
    cu.bevel_resolution = 4
    pts = outline(params)
    sp = cu.splines.new('POLY')
    sp.points.add(len(pts) - 1)
    for p, (u, v) in zip(sp.points, pts):
        p.co = (u, 0.0, v, 1.0)
    sp.use_cyclic_u = True
    cu.materials.append(material)
    hoop = bpy.data.objects.new("FP2Hoop", cu)
    collection.objects.link(hoop)
    hoop.location = HOOP_BAR
    hoop.rotation_euler = (radians(-params["tilt"]), 0.0, 0.0)
    bpy.context.view_layer.update()
    eye = hoop.matrix_world @ Vector((params["ue"], 0.0, -params["H"]))
    return hoop, eye


def hoop_clearance(params=HOOP, glove="GloveHand"):
    """Smallest gap (m) between the visible hoop wire (below the bar) and the posed glove surface;
    negative means the wire cuts into the hand."""
    dg = bpy.context.evaluated_depsgraph_get()
    g = bpy.data.objects[glove]
    ge = g.evaluated_get(dg)
    me = ge.to_mesh()
    verts = [g.matrix_world @ v.co for v in me.vertices]
    bvh = BVHTree.FromPolygons(verts, [tuple(p.vertices) for p in me.polygons])
    ge.to_mesh_clear()

    def inside(p):
        hits = 0
        for d in (Vector((0.0, 0.0, 1.0)), Vector((0.3, 0.2, 0.93)).normalized()):
            c, o = 0, p.copy()
            for _ in range(20):
                hit = bvh.ray_cast(o, d)
                if hit[0] is None:
                    break
                c, o = c + 1, hit[0] + d * 1e-5
            hits += c % 2
        return hits == 2

    R = Matrix.Rotation(radians(-params["tilt"]), 3, 'X')
    worst = 1.0
    for u, v in outline(params):
        if v >= -0.004:
            continue  # the bar itself sits inside the closed fist
        p = HOOP_BAR + R @ Vector((u, 0.0, v))
        d = bvh.find_nearest(p)[3]
        worst = min(worst, (-d if inside(p) else d) - HOOP_WIRE)
    return worst


def _tube(bm, pts, radius_fn, seg=16):
    """Rings of `seg` verts around a straight run of points along X; returns the bmesh rings."""
    import bmesh  # noqa: F401  (bmesh is only importable inside Blender)
    rings = []
    for i, x in enumerate(pts):
        r = radius_fn(i, x)
        rings.append([bm.verts.new((x, r * math.cos(2 * pi * k / seg), r * math.sin(2 * pi * k / seg))) for k in range(seg)])
    for a, b in zip(rings, rings[1:]):
        for k in range(seg):
            bm.faces.new((a[k], a[(k + 1) % seg], b[(k + 1) % seg], b[k]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    return rings


def grip_profile(grip=GRIP, glove="GloveHand", n=24):
    """Grip radius along the bar, swelled to fill the measured finger tunnel (+1 mm so the fingers
    press into it), clamped to a believable 5.5-8.5 mm and smoothed."""
    dg = bpy.context.evaluated_depsgraph_get()
    g = bpy.data.objects[glove]
    ge = g.evaluated_get(dg)
    gm = ge.to_mesh()
    bvh = BVHTree.FromPolygons([g.matrix_world @ v.co for v in gm.vertices], [tuple(p.vertices) for p in gm.polygons])
    ge.to_mesh_clear()
    xs = [grip["u0"] + (grip["u1"] - grip["u0"]) * i / (n - 1) for i in range(n)]
    raw = [min(0.0085, max(0.0055, bvh.find_nearest(HOOP_BAR + Vector((x, 0.0, 0.0)))[3] + 0.001)) for x in xs]
    return [sum(raw[max(0, i - 2):i + 3]) / len(raw[max(0, i - 2):i + 3]) for i in range(n)]


def build_grip(collection, wood, iron, grip=GRIP):
    """A wooden sleeve on the hoop's bar, shaped to the fist (grip_profile), plus thin iron ferrules
    at its ends. Built in the hoop's local frame (bar along X), parented to FP2Hoop."""
    import bmesh
    for name in ("FP2Grip", "FP2Ferrules"):
        old = bpy.data.objects.get(name)
        if old:
            bpy.data.objects.remove(old, do_unlink=True)
    u0, u1 = grip["u0"], grip["u1"]
    n = 24
    xs = [u0 + (u1 - u0) * i / (n - 1) for i in range(n)]
    prof = grip_profile(grip, n=n)
    if grip.get("knob_r"):  # flare to a turned knob once clear of the index finger
        k0 = grip["knob_from"]
        for i, x in enumerate(xs):
            if x > k0:
                t = min(1.0, (x - k0) / max(u1 - k0 - 0.002, 1e-6))
                prof[i] = prof[i] + (grip["knob_r"] - prof[i]) * (t * t * (3 - 2 * t))
    # turned, rounded ends: a quarter-round dome down to the rod at each end
    dome = [sin(a) for a in (0.0, 0.4, 0.8, 1.15, 1.45)]
    rad = [max(HOOP_WIRE + 0.0004, prof[0] * cos(asin(d))) for d in reversed(dome[1:])] + prof         + [max(HOOP_WIRE + 0.0004, prof[-1] * cos(asin(d))) for d in dome[1:]]
    xs = [u0 - 0.004 * d for d in reversed(dome[1:])] + xs + [u1 + 0.004 * d for d in dome[1:]]
    bm = bmesh.new()
    _tube(bm, xs, lambda i, x: rad[i], seg=20)
    me = bpy.data.meshes.new("FP2Grip")
    bm.to_mesh(me)
    bm.free()
    me.materials.append(wood)
    for poly in me.polygons:
        poly.use_smooth = True
    grip_ob = bpy.data.objects.new("FP2Grip", me)
    bm = bmesh.new()
    for x0, rr in ((u0 + 0.004, prof[1]), (u1 - 0.0065, prof[-2])):  # thin bands set back from the ends
        _tube(bm, [x0, x0 + 0.0022], lambda i, x, rr=rr: rr + 0.0006, seg=20)
    me = bpy.data.meshes.new("FP2Ferrules")
    bm.to_mesh(me)
    bm.free()
    me.materials.append(iron)
    for poly in me.polygons:
        poly.use_smooth = True
    fer_ob = bpy.data.objects.new("FP2Ferrules", me)
    hoop = bpy.data.objects["FP2Hoop"]
    for ob in (grip_ob, fer_ob):
        collection.objects.link(ob)
        ob.parent = hoop
    return grip_ob, fer_ob


def bake_contact_ao(obj_names, glove="GloveHand", reach=0.012, floor=0.22):
    """Vertex-colour contact shading: wire and grip darken as they near or enter the glove, so the
    bar fades into the fist instead of glowing evenly (glTF COLOR_0, multiplied into albedo)."""
    dg = bpy.context.evaluated_depsgraph_get()
    g = bpy.data.objects[glove]
    ge = g.evaluated_get(dg)
    gm = ge.to_mesh()
    verts = [g.matrix_world @ v.co for v in gm.vertices]
    bvh = BVHTree.FromPolygons(verts, [tuple(p.vertices) for p in gm.polygons])
    ge.to_mesh_clear()
    for name in obj_names:
        ob = bpy.data.objects[name]
        me = ob.data
        attr = me.color_attributes.get("Col") or me.color_attributes.new("Col", 'FLOAT_COLOR', 'POINT')
        me.color_attributes.active_color = attr
        for i, v in enumerate(me.vertices):
            p = ob.matrix_world @ v.co
            loc, nrm, _, d = bvh.find_nearest(p)
            inside = (p - loc).dot(nrm) < 0
            t = 0.0 if inside else min(1.0, d / reach)
            k = floor + (1.0 - floor) * (t * t * (3 - 2 * t))
            attr.data[i].color = (k, k, k, 1.0)
