"""Helpers for the first-person lantern-hand viewmodel (HandWork scene in art/characters.blend).

exec(open(r"<repo>/art/scripts/fp_viewmodel.py").read(), g); g["place"](twist_extra, cam_rel)
"""

from math import cos, pi, radians, sin

import bpy
from mathutils import Matrix, Quaternion, Vector

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
