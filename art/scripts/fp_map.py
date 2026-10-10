"""The hand-held map (spec §11.4): an old parchment in the spirit of the Marauder's Map.

Built in its own scene (MapWork), saved to art/map.blend and exported to client/assets/map/map.glb
(the sheet, its crease rig and the open "rest" pose) and map_hand.glb (the right hand holding it).

    g = {"__name__": "fp_map"}
    exec(open(r"<repo>/art/scripts/fp_map.py").read(), g)
    g["build_everything_v10"](r"<repo>")   # sheet + solved hand (slow: ~3 min of solving)
    g["rebuild_map_v11"](r"<repo>")        # sheet + flutter only, keeping the current hand

The sheet is 40 x 30 cm and was once folded in 3 x 2 panels: its creases stay soft hinges. Blender
axes: the sheet lies in the XZ plane and its inked face looks down -Y (towards the viewer; glTF turns
-Y into Godot's +Z, so it faces the camera). Panels: columns L/C/R (x), rows B/T (z). Each crease is
a hinge bone (rotation about local Y) and the top row has curl bones halfway up; the bottom-right
panel B2 is the root, where the right hand holds it.

Motion (2026-10-10): the map comes out already open (an earlier version unfolded from a folded
bundle). Only the open rest shape is exported (a one-frame "rest" action: the creases' memory and
the far corner's sag); the game moves the crease hinges live from the hand's motion through the air
(client/ui/paper_hinge.gd). Some fold-era constants (layer offsets T, the hinge axes' Y offsets)
remain but no longer matter.
"""

import math
import os

import bmesh
import bpy
from mathutils import Matrix, Quaternion, Vector

W, H = 0.40, 0.30  # open sheet (m)
PW, PH = W / 3, H / 2  # one panel
T = 0.0008  # layer spacing in the folded bundle
CREASE = 0.0025  # half-width of the soft weight blend across a crease
FPS = 60
SCENE = "MapWork"
TEX_W, TEX_H = 2048, 1536  # 4:3 like the sheet

# open-state "fold memory": the creases never lie quite flat again (radians)
REST = dict(colR=0.1, colL=0.08, row=0.12)


# ---------------------------------------------------------------------------------------------
# scene

def _scene():
    sc = bpy.data.scenes.get(SCENE) or bpy.data.scenes.new(SCENE)
    sc.render.fps = FPS
    sc.unit_settings.system = 'METRIC'
    coll = bpy.data.collections.get("Map")
    if coll is None:
        coll = bpy.data.collections.new("Map")
        sc.collection.children.link(coll)
    return sc, coll


def _replace(name, data, coll):
    old = bpy.data.objects.get(name)
    if old:
        bpy.data.objects.remove(old, do_unlink=True)
    ob = bpy.data.objects.new(name, data)
    coll.objects.link(ob)
    return ob


# ---------------------------------------------------------------------------------------------
# geometry

def _axis(lo, hi, step, creases):
    """Coordinates from lo to hi: `step` apart, refined to 1 mm around each crease."""
    pts = set()
    n = int(round((hi - lo) / step))
    for i in range(n + 1):
        pts.add(round(lo + (hi - lo) * i / n, 6))
    for c in creases:
        for d in (-0.008, -0.005, -0.003, -0.002, -0.001, 0.0, 0.001, 0.002, 0.003, 0.005, 0.008):
            pts.add(round(c + d, 6))
    return sorted(p for p in pts if lo <= p <= hi)


def build_sheet(coll):
    xs = _axis(-W / 2, W / 2, 0.006, (-PW / 2, PW / 2))
    zs = _axis(-H / 2, H / 2, 0.006, (0.0,))
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    grid = [[bm.verts.new((x, 0.0, z)) for x in xs] for z in zs]
    for j in range(len(zs) - 1):
        for i in range(len(xs) - 1):
            # winding so the face normal is -Y (the inked side faces the viewer)
            f = bm.faces.new((grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]))
            for loop in f.loops:
                co = loop.vert.co
                loop[uv].uv = ((co.x + W / 2) / W, (co.z + H / 2) / H)
    bm.normal_update()
    me = bpy.data.meshes.new("MapSheet")
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = True
    return _replace("MapSheet", me, coll)


# ---------------------------------------------------------------------------------------------
# rig

BONES = {
    # name: (head, tail, parent) -- hinge bones lie along their crease (rotation about local Y)
    "root": ((W / 2, 0, -H / 2), (W / 2, 0, -H / 2 + 0.05), None),
    "colR": ((PW / 2, -2.5 * T, -H / 2), (PW / 2, -2.5 * T, H / 2), "root"),
    "colL": ((-PW / 2, -1.5 * T, -H / 2), (-PW / 2, -1.5 * T, H / 2), "colR"),
    "rowR": ((PW / 2, -0.5 * T, 0), (W / 2, -0.5 * T, 0), "root"),
    "rowC": ((-PW / 2, -0.5 * T, 0), (PW / 2, -0.5 * T, 0), "colR"),
    "rowL": ((-W / 2, -0.5 * T, 0), (-PW / 2, -0.5 * T, 0), "colL"),
    "curlR": ((PW / 2, 0, H / 4), (W / 2, 0, H / 4), "rowR"),
    "curlC": ((-PW / 2, 0, H / 4), (PW / 2, 0, H / 4), "rowC"),
    "curlL": ((-W / 2, 0, H / 4), (-PW / 2, 0, H / 4), "rowL"),
}


def _ss(e0, e1, x):
    t = min(1.0, max(0.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


def build_rig(sheet, coll):
    arm = bpy.data.armatures.new("MapRig")
    rig = _replace("MapRig", arm, coll)
    bpy.context.window.scene = bpy.data.scenes[SCENE]
    bpy.context.view_layer.objects.active = rig
    for o in bpy.context.view_layer.objects:
        o.select_set(o == rig)
    bpy.ops.object.mode_set(mode='EDIT')
    for name, (h, t, parent) in BONES.items():
        b = arm.edit_bones.new(name)
        b.head, b.tail = Vector(h), Vector(t)
        b.roll = 0.0
        if parent:
            b.parent = arm.edit_bones[parent]
    bpy.ops.object.mode_set(mode='OBJECT')
    for pb in rig.pose.bones:
        pb.rotation_mode = 'XYZ'

    sheet.parent = rig
    sheet.vertex_groups.clear()
    groups = {n: sheet.vertex_groups.new(name=n) for n in BONES}
    mod = sheet.modifiers.get("Armature") or sheet.modifiers.new("Armature", 'ARMATURE')
    mod.object = rig
    for v in sheet.data.vertices:
        x, z = v.co.x, v.co.z
        left = _ss(-CREASE, CREASE, -PW / 2 - x)  # left of the left crease
        not_right = _ss(-CREASE, CREASE, PW / 2 - x)  # left of the right crease
        top = _ss(-CREASE, CREASE, z)
        curl = _ss(H / 4 - 0.035, H / 4 + 0.035, z)  # broad blend: the paper bends, it doesn't hinge
        cols = (("root", "rowR", "curlR", 1 - not_right),
                ("colR", "rowC", "curlC", not_right * (1 - left)),
                ("colL", "rowL", "curlL", left))
        w = {}
        for col, row, cb, f in cols:
            w[col] = w.get(col, 0) + f * (1 - top)
            w[row] = w.get(row, 0) + f * top * (1 - curl)
            w[cb] = w.get(cb, 0) + f * top * curl
        for name, wt in w.items():
            if wt > 1e-4:
                groups[name].add([v.index], wt, 'REPLACE')
    return rig


# ---------------------------------------------------------------------------------------------
# animation

def _spring(t, omega, zeta):
    """Step response of a damped spring (0 -> 1, zero start velocity); t in seconds."""
    if t <= 0:
        return 0.0
    wd = omega * math.sqrt(1 - zeta * zeta)
    return 1 - math.exp(-zeta * omega * t) * (math.cos(wd * t) + zeta / math.sqrt(1 - zeta * zeta) * math.sin(wd * t))


# The open sheet's rest shape (2026-10-10): the map comes out already open (the user's call) and its
# motion is no longer baked here. The game drives the crease hinges live from the hand's motion
# through the air (client/ui/paper_hinge.gd, map_screen.gd): an earlier baked 4-6 Hz flutter read as
# jelly. This exports a one-frame "rest" action: the creases' memory and the far corner's sag.
# One angle across the whole width: a horizontal fold can't bend differently in each column (paper is one
# piece); per-column curls sheared the columns past each other at the vertical creases and the sheet
# read as three overlapping strips (user, 2026-10-10). The far corner's sag lives in the shader now.
REST_CURL = dict(curlL=0.1, curlC=0.1, curlR=0.1)


def rest_angles():
    row = REST["row"]
    return {"colR": REST["colR"], "colL": REST["colL"], "rowR": row, "rowC": row, "rowL": row, **REST_CURL}


def build_animation(rig, frames=0):
    rig.animation_data_create()
    for name in ("unfold", "flutter", "rest"):
        act = bpy.data.actions.get(name)
        if act:
            bpy.data.actions.remove(act)
    act = bpy.data.actions.new("rest")
    rig.animation_data.action = act
    pb = rig.pose.bones
    for name, ang in rest_angles().items():
        pb[name].rotation_euler = (0.0, ang, 0.0)
        pb[name].keyframe_insert("rotation_euler", frame=0)
    sc = bpy.data.scenes[SCENE]
    sc.frame_start, sc.frame_end = 0, 0
    return act


# ---------------------------------------------------------------------------------------------
# parchment textures (baked from nodes: mottled vellum, tide-line stains, foxing, darkened and
# nibbled edges, dirt in the creases, real paper fibre from ambientCG Paper001 / Paper003)

def _bake_plane(coll):
    me = bpy.data.meshes.new("MapBakePlane")
    s = W / 2
    me.from_pydata([(-s, -H / 2, 0), (s, -H / 2, 0), (s, H / 2, 0), (-s, H / 2, 0)], [], [(0, 1, 2, 3)])
    uv = me.uv_layers.new(name="UVMap")
    for i, c in enumerate([(0, 0), (1, 0), (1, 1), (0, 1)]):
        uv.data[i].uv = c
    return _replace("MapBakePlane", me, coll)


def _parchment_nodes(mat, tex_dir, seed, mode):
    """mode: 'albedo' (RGB + alpha in a separate pass), 'alpha', or 'normal'."""
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    N = nt.nodes.new
    L = nt.links.new
    out = N("ShaderNodeOutputMaterial")
    emit = N("ShaderNodeEmission")
    L(emit.outputs[0], out.inputs["Surface"])

    tc = N("ShaderNodeTexCoord")
    # metric position on the sheet (m), so feature sizes are physical
    pos = N("ShaderNodeVectorMath"); pos.operation = 'MULTIPLY'
    pos.inputs[1].default_value = (W, H, 1.0)
    L(tc.outputs["UV"], pos.inputs[0])
    seeded = N("ShaderNodeVectorMath"); seeded.operation = 'ADD'
    seeded.inputs[1].default_value = (seed * 3.17, seed * 1.93, seed * 0.71)
    L(pos.outputs[0], seeded.inputs[0])
    P = seeded.outputs[0]

    def noise(scale, detail=4.0, rough=0.55, dim='3D'):
        n = N("ShaderNodeTexNoise")
        n.inputs["Scale"].default_value = scale
        n.inputs["Detail"].default_value = detail
        n.inputs["Roughness"].default_value = rough
        L(P, n.inputs["Vector"])
        return n.outputs["Fac"]

    def math_(op, a, b=None, clamp=False):
        m = N("ShaderNodeMath"); m.operation = op; m.use_clamp = clamp
        for i, v in enumerate((a, b)):
            if v is None:
                continue
            if isinstance(v, (int, float)):
                m.inputs[i].default_value = v
            else:
                L(v, m.inputs[i])
        return m.outputs[0]

    def ramp(fac, stops):
        r = N("ShaderNodeValToRGB")
        cr = r.color_ramp
        cr.elements[0].position, cr.elements[0].color = stops[0][0], (*stops[0][1], 1)
        cr.elements[1].position, cr.elements[1].color = stops[-1][0], (*stops[-1][1], 1)
        for p, c in stops[1:-1]:
            e = cr.elements.new(p)
            e.color = (*c, 1)
        L(fac, r.inputs["Fac"])
        return r.outputs["Color"]

    def image(name, scale, non_color=False):
        img = bpy.data.images.load(os.path.join(tex_dir, name), check_existing=True)
        if non_color:
            img.colorspace_settings.name = 'Non-Color'
        t = N("ShaderNodeTexImage"); t.image = img
        sc = N("ShaderNodeVectorMath"); sc.operation = 'MULTIPLY'
        sc.inputs[1].default_value = (scale, scale, 1.0)
        L(P, sc.inputs[0])
        L(sc.outputs[0], t.inputs["Vector"])
        return t

    # distance to the sheet edge (m), wobbled so the wear is irregular
    sep = N("ShaderNodeSeparateXYZ"); L(pos.outputs[0], sep.inputs[0])
    ex = math_('MINIMUM', sep.outputs[0], math_('SUBTRACT', W, sep.outputs[0]))
    ey = math_('MINIMUM', sep.outputs[1], math_('SUBTRACT', H, sep.outputs[1]))
    edge = math_('MINIMUM', ex, ey)
    edge_w = math_('ADD', edge, math_('MULTIPLY', math_('SUBTRACT', noise(60.0, 6.0, 0.6), 0.5), 0.012))

    # crease lines: distance to the nearest crease (m)
    cx1 = math_('ABSOLUTE', math_('SUBTRACT', sep.outputs[0], W / 3))
    cx2 = math_('ABSOLUTE', math_('SUBTRACT', sep.outputs[0], 2 * W / 3))
    cz = math_('ABSOLUTE', math_('SUBTRACT', sep.outputs[1], H / 2))
    crease_d = math_('MINIMUM', math_('MINIMUM', cx1, cx2), cz)

    if mode == 'normal':
        # height: crumpled paper (Paper003) + the creases pressed in + fibre tooth (Paper001)
        crumple = image("Paper003_2K/Paper003_2K-JPG_Displacement.jpg", 2.2, True)
        tooth = image("Paper001/Paper001_1K-JPG_Displacement.jpg", 5.0, True)
        h = math_('MULTIPLY', crumple.outputs["Color"], 0.7)
        h = math_('ADD', h, math_('MULTIPLY', tooth.outputs["Color"], 0.08))
        groove = math_('SUBTRACT', 1.0, math_('DIVIDE', crease_d, 0.0035), clamp=True)
        h = math_('SUBTRACT', h, math_('MULTIPLY', math_('POWER', groove, 2.0), 0.5))
        bump = N("ShaderNodeBump")
        bump.inputs["Strength"].default_value = 1.0
        bump.inputs["Distance"].default_value = 0.0006
        L(h, bump.inputs["Height"])
        enc = N("ShaderNodeVectorMath"); enc.operation = 'MULTIPLY_ADD'
        enc.inputs[1].default_value = (0.5, 0.5, 0.5)
        enc.inputs[2].default_value = (0.5, 0.5, 0.5)
        L(bump.outputs["Normal"], enc.inputs[0])
        L(enc.outputs[0], emit.inputs["Color"])
        return

    if mode == 'alpha':
        # nibbled edges: a 0-2.5 mm ragged loss, a little more at the corners
        corner = math_('MINIMUM', math_('ADD', ex, ey), 1.0)
        bite = math_('ADD', math_('MULTIPLY', noise(220.0, 3.0, 0.7), 0.003),
                     math_('MULTIPLY', math_('SUBTRACT', 1.0, math_('DIVIDE', corner, 0.03), clamp=True), 0.004))
        a = math_('GREATER_THAN', edge, bite)
        L(a, emit.inputs["Color"])
        return

    # albedo -------------------------------------------------------------------------------------
    fibre = image("Paper001/Paper001_1K-JPG_Displacement.jpg", 4.0, True)  # the colour map is flat
    flecks = image("Paper002/Paper002_1K-JPG_Color.jpg", 3.0, True)  # thresholded as data
    crumple_c = image("Paper003_2K/Paper003_2K-JPG_Color.jpg", 2.2)
    # mottled vellum: warm cream with honey and grey-brown patches at 3-10 cm
    mott_n = math_('ADD', math_('MULTIPLY', noise(9.0, 5.0, 0.62), 0.75), math_('MULTIPLY', noise(31.0, 3.0, 0.5), 0.25))
    mott = ramp(mott_n, [(0.38, (0.60, 0.44, 0.24)), (0.47, (0.72, 0.57, 0.35)),
                         (0.53, (0.79, 0.66, 0.43)), (0.62, (0.85, 0.74, 0.52))])
    # fibre tooth (Paper001 height) and dark fibre flecks (Paper002) as a multiply
    tooth = ramp(fibre.outputs["Color"], [(0.48, (0.8, 0.77, 0.73)), (0.72, (1.0, 1.0, 1.0))])
    grain = N("ShaderNodeMix"); grain.data_type = 'RGBA'; grain.blend_type = 'MULTIPLY'
    grain.inputs["Factor"].default_value = 1.0
    L(mott, grain.inputs["A"]); L(tooth, grain.inputs["B"])
    fl = ramp(flecks.outputs["Color"], [(0.4, (0.5, 0.4, 0.3)), (0.62, (0.9, 0.88, 0.86)), (0.82, (1.0, 1.0, 1.0))])
    grain2 = N("ShaderNodeMix"); grain2.data_type = 'RGBA'; grain2.blend_type = 'MULTIPLY'
    grain2.inputs["Factor"].default_value = 1.0
    L(grain.outputs["Result"], grain2.inputs["A"]); L(fl, grain2.inputs["B"])
    crum = N("ShaderNodeMix"); crum.data_type = 'RGBA'; crum.blend_type = 'LINEAR_LIGHT'
    crum.inputs["Factor"].default_value = 0.22
    L(grain2.outputs["Result"], crum.inputs["A"]); L(crumple_c.outputs["Color"], crum.inputs["B"])
    col = crum.outputs["Result"]

    def darken(col, mask, tint, amount):
        m = N("ShaderNodeMix"); m.data_type = 'RGBA'; m.blend_type = 'MULTIPLY'
        L(math_('MULTIPLY', mask, amount), m.inputs["Factor"])
        L(col, m.inputs["A"]); m.inputs["B"].default_value = (*tint, 1)
        return m.outputs["Result"]

    # tide-line stains: thin dark rings where an old spill dried (iso-band of a slow noise)
    tide_n = noise(4.0, 3.0, 0.5)
    band = math_('SUBTRACT', 1.0, math_('DIVIDE', math_('ABSOLUTE', math_('SUBTRACT', tide_n, 0.56)), 0.008), clamp=True)
    inside = math_('GREATER_THAN', tide_n, 0.56)
    sparse = math_('DIVIDE', math_('SUBTRACT', noise(1.6, 2.0, 0.5), 0.42), 0.1, clamp=True)
    col = darken(col, math_('MULTIPLY', math_('ADD', band, math_('MULTIPLY', inside, 0.35)), sparse),
                 (0.62, 0.45, 0.28), 0.55)
    # foxing: small rust-brown spots, clustered
    vor = N("ShaderNodeTexVoronoi"); vor.inputs["Scale"].default_value = 140.0
    L(P, vor.inputs["Vector"])
    spot = math_('SUBTRACT', 1.0, math_('DIVIDE', vor.outputs["Distance"], 0.16), clamp=True)
    cluster = math_('GREATER_THAN', math_('ADD', noise(7.0, 2.0, 0.5), math_('MULTIPLY', vor.outputs["Color"], 0.0)), 0.6)
    col = darken(col, math_('MULTIPLY', spot, cluster), (0.55, 0.32, 0.16), 0.7)
    # dirt and wear along the creases (handled for years)
    # a thin dark line in the fold, broken where the fibres have worn pale, in a soft grubby halo
    crease_line = math_('SUBTRACT', 1.0, math_('DIVIDE', crease_d, 0.0012), clamp=True)
    crease_halo = math_('SUBTRACT', 1.0, math_('DIVIDE', crease_d, 0.006), clamp=True)
    patchy = math_('ADD', 0.25, noise(55.0, 4.0, 0.65))
    col = darken(col, math_('MULTIPLY', crease_halo, patchy), (0.6, 0.47, 0.32), 0.5)
    col = darken(col, math_('MULTIPLY', crease_line, patchy), (0.42, 0.30, 0.19), 0.8)
    # fibres scuffed pale along the ridge in places (soft, a lightening of the same paper)
    ridge = math_('SUBTRACT', 1.0, math_('DIVIDE', crease_d, 0.0028), clamp=True)
    worn = math_('MULTIPLY', ridge, math_('DIVIDE', math_('SUBTRACT', noise(70.0, 3.0, 0.55), 0.52), 0.12, clamp=True))
    wm = N("ShaderNodeMix"); wm.data_type = 'RGBA'; wm.blend_type = 'SCREEN'
    L(math_('MULTIPLY', worn, 0.8), wm.inputs["Factor"])
    L(col, wm.inputs["A"]); wm.inputs["B"].default_value = (0.3, 0.26, 0.2, 1)
    col = wm.outputs["Result"]
    # each panel aged a little differently (light and handling while folded)
    pid = math_('ADD', math_('FLOOR', math_('DIVIDE', sep.outputs[0], W / 3)),
                math_('MULTIPLY', math_('FLOOR', math_('DIVIDE', sep.outputs[1], H / 2)), 3.0))
    ptone = N("ShaderNodeTexWhiteNoise"); ptone.noise_dimensions = '1D'
    L(math_('ADD', pid, seed), ptone.inputs["W"])
    col = darken(col, ptone.outputs["Value"], (0.78, 0.68, 0.52), 0.6)
    # edges: browned and handled, darkest right at the rim
    rim = math_('SUBTRACT', 1.0, math_('DIVIDE', edge_w, 0.03), clamp=True)
    col = darken(col, math_('POWER', rim, 1.6), (0.36, 0.22, 0.11), 0.85)
    # a grubby thumb zone where the hand holds the bundle (bottom-right panel, right edge)
    grip_d = N("ShaderNodeVectorMath"); grip_d.operation = 'DISTANCE'
    grip_d.inputs[1].default_value = (W - 0.01, 0.06, 0.0)
    L(pos.outputs[0], grip_d.inputs[0])
    thumb = math_('SUBTRACT', 1.0, math_('DIVIDE', grip_d.outputs["Value"], 0.05), clamp=True)
    col = darken(col, math_('MULTIPLY', thumb, noise(30.0, 3.0, 0.6)), (0.55, 0.42, 0.30), 0.6)
    L(col, emit.inputs["Color"])


def bake_parchment(repo, tex_dir, coll):
    """Bake parchment_front / parchment_back (RGBA: albedo + nibbled-edge alpha) and parchment_n."""
    sc = bpy.data.scenes[SCENE]
    bpy.context.window.scene = sc
    sc.render.engine = 'CYCLES'
    sc.cycles.samples = 4
    sc.cycles.device = 'GPU' if bpy.context.preferences.addons.get("cycles") else 'CPU'
    for img in list(bpy.data.images):
        if img.name.startswith(("MapBake_", "parchment_")):
            bpy.data.images.remove(img)
    plane = _bake_plane(coll)
    out_dir = os.path.join(repo, "client", "assets", "map")
    os.makedirs(out_dir, exist_ok=True)
    mat = bpy.data.materials.get("MapBake") or bpy.data.materials.new("MapBake")
    plane.data.materials.clear()
    plane.data.materials.append(mat)
    for o in bpy.context.view_layer.objects:
        o.select_set(o == plane)
    bpy.context.view_layer.objects.active = plane

    def bake(mode, seed, colorspace='sRGB'):
        _parchment_nodes(mat, tex_dir, seed, mode)
        img = bpy.data.images.new(f"MapBake_{mode}_{seed}", TEX_W, TEX_H, alpha=False)
        img.colorspace_settings.name = colorspace
        tn = mat.node_tree.nodes.new("ShaderNodeTexImage")
        tn.image = img
        mat.node_tree.nodes.active = tn
        bpy.ops.object.bake(type='EMIT', margin=0)
        return img

    paths = {}
    for side, seed in (("front", 0.0), ("back", 7.0)):
        rgb = bake('albedo', seed)
        alpha = bake('alpha', seed, 'Non-Color')
        px = list(rgb.pixels)
        ap = alpha.pixels[:]
        px[3::4] = ap[0::4]
        res = bpy.data.images.new(f"parchment_{side}", TEX_W, TEX_H, alpha=True)
        res.pixels = px
        res.filepath_raw = os.path.join(out_dir, f"parchment_{side}.png")
        res.file_format = 'PNG'
        res.save()
        paths[side] = res.filepath_raw
    nrm = bake('normal', 0.0, 'Non-Color')
    nrm.filepath_raw = os.path.join(out_dir, "parchment_n.png")
    nrm.file_format = 'PNG'
    nrm.save()
    paths["normal"] = nrm.filepath_raw
    bpy.data.objects.remove(plane, do_unlink=True)
    return paths


# ---------------------------------------------------------------------------------------------
# preview material (Blender renders only; the game uses client/ui/map_parchment.gdshader)

def preview_material(repo):
    d = os.path.join(repo, "client", "assets", "map")
    mat = bpy.data.materials.get("M_Map") or bpy.data.materials.new("M_Map")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    N, L = nt.nodes.new, nt.links.new
    out = N("ShaderNodeOutputMaterial")
    bsdf = N("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Roughness"].default_value = 0.8
    L(bsdf.outputs[0], out.inputs["Surface"])
    geo = N("ShaderNodeNewGeometry")
    imgs = {}
    for k in ("front", "back"):
        t = N("ShaderNodeTexImage")
        t.image = bpy.data.images.load(os.path.join(d, f"parchment_{k}.png"), check_existing=True)
        imgs[k] = t
    mix = N("ShaderNodeMix"); mix.data_type = 'RGBA'
    L(geo.outputs["Backfacing"], mix.inputs["Factor"])
    L(imgs["front"].outputs["Color"], mix.inputs["A"]); L(imgs["back"].outputs["Color"], mix.inputs["B"])
    L(mix.outputs["Result"], bsdf.inputs["Base Color"])
    L(imgs["front"].outputs["Alpha"], bsdf.inputs["Alpha"])
    nm = N("ShaderNodeTexImage")
    nm.image = bpy.data.images.load(os.path.join(d, "parchment_n.png"), check_existing=True)
    nm.image.colorspace_settings.name = 'Non-Color'
    nmap = N("ShaderNodeNormalMap")
    L(nm.outputs["Color"], nmap.inputs["Color"]); L(nmap.outputs[0], bsdf.inputs["Normal"])
    return mat


# ---------------------------------------------------------------------------------------------
# export

def export(repo, rig, sheet):
    path = os.path.join(repo, "client", "assets", "map", "map.glb")
    sc = bpy.data.scenes[SCENE]
    bpy.context.window.scene = sc
    for o in bpy.context.view_layer.objects:
        o.select_set(o in (rig, sheet))
    bpy.context.view_layer.objects.active = rig
    bpy.ops.export_scene.gltf(filepath=path, use_selection=True, export_format='GLB',
                              export_animations=True, export_animation_mode='ACTIONS',
                              export_force_sampling=True, export_frame_range=False,
                              export_skins=True, export_def_bones=False, export_materials='PLACEHOLDER',
                              export_yup=True, export_apply=False)
    return path


def save_blend(repo):
    sc = bpy.data.scenes[SCENE]
    path = os.path.join(repo, "art", "map.blend")
    blocks = {sc} | set(sc.objects) | {a for a in bpy.data.actions if a.name == "rest"}
    bpy.data.libraries.write(path, blocks, fake_user=True, compress=True)
    return path


def build_all(repo, tex_dir, bake=True):
    sc, coll = _scene()
    bpy.context.window.scene = sc
    sheet = build_sheet(coll)
    rig = build_rig(sheet, coll)
    build_animation(rig)
    res = {"verts": len(sheet.data.vertices)}
    if bake:
        res["textures"] = bake_parchment(repo, tex_dir, coll)
    sheet.data.materials.clear()
    sheet.data.materials.append(preview_material(repo))
    return res


# ---------------------------------------------------------------------------------------------
# the right hand that holds it: a mirrored copy of the lantern arm (HandWork scene, FPArm2: CC0
# Blender Human Base Meshes hand in an oilskin glove, see art/scripts/fp_viewmodel.py), re-posed to
# pinch the sheet's right edge: fingers flat behind the paper, the thumb pressed on its face (IK).
# Exported posed and static, in the map's own frame (the held panel B2 never moves).

ARM_PARTS = ["GloveHand", "HandRig", "Sleeve2", "Gauntlet3", "GauntletRim3", "WristStrap3", "Buckle3", "StrapTail3"]
# game reading pose of the sheet relative to the eye (client/ui/map_screen.gd READ_POS / READ_ROT)
READ_POS = (0.06, -0.005, -0.41)
READ_ROT = (-0.24, -0.05, 0.02)
ELBOW_CAM = (0.46, -0.40, -0.22)  # the forearm enters from the bottom-right corner, ~35 deg off vertical
# hand placement in the map frame (Blender axes): grip on the right edge, lower half
GRIP = Vector((W / 2 - 0.012, 0.0, -0.075))
FINGER_CURL = {"index": (-0.15, -0.2, -0.1), "middle": (-0.55, -0.7, -0.35),
               "ring": (-0.75, -0.95, -0.5), "pinky": (-0.9, -1.05, -0.55)}


def _godot_to_blender(v):
    return Vector((v[0], -v[2], v[1]))


def cam_in_map():
    """Eye and elbow positions in the map's Blender frame, from the game's reading pose."""
    from mathutils import Euler, Matrix
    # Godot euler order YXZ: R = Ry * Rx * Rz (in Godot axes)
    rx, ry, rz = READ_ROT
    R = Matrix.Rotation(ry, 3, 'Y') @ Matrix.Rotation(rx, 3, 'X') @ Matrix.Rotation(rz, 3, 'Z')
    T = Matrix.Translation(Vector(READ_POS)) @ R.to_4x4()  # map -> eye (Godot axes)
    inv = T.inverted()
    eye = inv @ Vector((0, 0, 0))
    elbow = inv @ Vector(ELBOW_CAM)
    return _godot_to_blender(eye), _godot_to_blender(elbow)


def build_map_hand(coll_name="MapHand"):
    from mathutils import Matrix
    sc = bpy.data.scenes[SCENE]
    coll = bpy.data.collections.get(coll_name)
    if coll is None:
        coll = bpy.data.collections.new(coll_name)
        bpy.data.collections["Map"].children.link(coll)
    for o in list(coll.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    src_root = bpy.data.objects["FPArm2"]
    root = bpy.data.objects.new("MapHandRoot", None)
    coll.objects.link(root)
    copies = {}
    for name in ARM_PARTS:
        src = bpy.data.objects[name]
        o = src.copy()
        if name == "HandRig":
            o.data = src.data.copy()
        o.name = "MapHand_" + name
        coll.objects.link(o)
        o.parent = root
        o.matrix_parent_inverse = src.matrix_parent_inverse.copy()
        o.matrix_basis = src.matrix_basis.copy()
        copies[name] = o
    rig = copies["HandRig"]
    for o in copies.values():
        for m in getattr(o, "modifiers", []):
            if m.type == 'ARMATURE':
                m.object = rig
    soften_thumb(copies["GloveHand"])
    # pose: copy the lantern grip, then open the fingers so they lie flat behind the sheet
    for pb in rig.pose.bones:
        for c in list(pb.constraints):
            pb.constraints.remove(c)
    for f, curls in FINGER_CURL.items():
        for i, a in enumerate(curls):
            pb = rig.pose.bones[f"{f}.0{i + 1}"]
            pb.rotation_mode = 'QUATERNION'
            pb.rotation_quaternion = Matrix.Rotation(a, 4, 'Z').to_quaternion()
    for i in (1, 2, 3):
        rig.pose.bones[f"thumb.0{i}"].rotation_quaternion = (1, 0, 0, 0)
    return root, rig, copies


def soften_thumb(glove):
    """The glove was made for the lantern's hook grip. On the map's straightened thumb its joint
    creases (the material's `jointmask`) banded the thumb into segments and its skinning hollowed the
    thumb's base, so it read as a tube stuck onto the hand. Give this copy its own mesh with the
    thumb's creases at ~1/3, and a Corrective Smooth after the armature on the thumb and its base."""
    glove.data = glove.data.copy()
    glove.data.name = "MapHand_GloveMesh"
    tg = {g.index for g in glove.vertex_groups if g.name.startswith("thumb")}
    hand = glove.vertex_groups["hand"].index
    jm = glove.data.attributes["jointmask"]
    vg = glove.vertex_groups.get("thumb_corrective") or glove.vertex_groups.new(name="thumb_corrective")
    for v in glove.data.vertices:
        wt = sum(g.weight for g in v.groups if g.group in tg)
        wh = sum(g.weight for g in v.groups if g.group == hand)
        if wt > 0.05:
            jm.data[v.index].value *= 1.0 - 0.65 * min(1.0, wt * 1.5)
        w = min(1.0, wt * 1.5 + (0.6 * wh if wt > 0.02 else 0.0))
        if w > 0.01:
            vg.add([v.index], w, 'REPLACE')
    cs = glove.modifiers.get("ThumbCorrective") or glove.modifiers.new("ThumbCorrective", 'CORRECTIVE_SMOOTH')
    with bpy.context.temp_override(object=glove, active_object=glove):
        bpy.ops.object.modifier_move_to_index(modifier="ThumbCorrective", index=1)
    cs.factor, cs.iterations, cs.smooth_type, cs.rest_source = 1.0, 12, 'LENGTH_WEIGHTED', 'ORCO'
    cs.vertex_group = "thumb_corrective"


def place_map_hand(root, rig, lean=0.45, lift=0.25, depth=0.0015):
    """A pinch grip on the sheet's right edge: the edge sits in the web between thumb and index, the
    thumb lies on the face, the index runs up the back of the sheet and the other fingers curl behind
    it, palm facing into the sheet. `lean` tips the fingers left of vertical (rad); `lift` turns the
    hand about the palm normal so the forearm comes out towards the viewer (rad); `depth` is the gap
    between the paper and the index finger behind it (m). Mirrored in X to make it a right hand."""
    from mathutils import Matrix
    f = Vector((-math.sin(lean), 0.0, math.cos(lean)))  # fingers: up the edge, leaning in
    thumb_side = Vector((0.0, -1.0, 0.0))  # the thumb comes round to the viewer's side
    c2 = -f  # rig +Z (towards the wrist)
    c0 = thumb_side
    c1 = c2.cross(c0)  # rig +Y: the palm, facing into the sheet
    R = Matrix((c0, c1, c2)).transposed()
    R = Matrix.Rotation(lift, 3, c1) @ R  # forearm out towards the viewer, fingertips back
    M = R.to_4x4() @ Matrix.Diagonal((-1, 1, 1, 1))  # left hand -> right hand (thumb to +X)
    root.matrix_world = M
    bpy.context.view_layer.update()
    P = lambda n, tail=False: rig.matrix_world @ (rig.pose.bones[n].tail if tail else rig.pose.bones[n].head)
    web = (P("thumb.01", True) + P("index.01")) * 0.5
    # the edge in the web; the index finger's front just behind the paper
    shift = Vector((GRIP.x + 0.006 - web.x, 0.0, GRIP.z - web.z))
    finger_r = 0.0085
    front = min((P(n).y, P(n, True).y) for n in ("index.01", "index.02", "index.03"))
    shift.y = depth + finger_r - min(front)
    root.matrix_world = Matrix.Translation(shift) @ M
    bpy.context.view_layer.update()
    return f, web + shift


def clear_paper(root, rig, glove, depth=0.0015):
    """Push the hand back (+Y) until no glove vertex except the thumb's is in front of the paper,
    measured on the evaluated (posed, thickened, subdivided) glove, not on bone radii."""
    from mathutils import Matrix
    bpy.context.view_layer.update()
    segs = [(rig.matrix_world @ pb.head, rig.matrix_world @ pb.tail, pb.name.startswith("thumb"))
            for pb in rig.pose.bones if pb.name != "hand"]

    def is_thumb(p):
        best, bd = False, 1e9
        for a, b, th in segs:
            ab = b - a
            t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-9)))
            d = (a + ab * t - p).length
            if d < bd:
                best, bd = th, d
        return best

    ev = glove.evaluated_get(bpy.context.evaluated_depsgraph_get())
    me = ev.to_mesh()
    lo = min((glove.matrix_world @ v.co).y for v in me.vertices
             if (glove.matrix_world @ v.co).x < W / 2 + 0.002 and not is_thumb(glove.matrix_world @ v.co))
    ev.to_mesh_clear()
    root.matrix_world = Matrix.Translation(Vector((0.0, depth - lo, 0.0))) @ root.matrix_world
    bpy.context.view_layer.update()
    return depth - lo


def pose_thumb(rig, target):
    """IK the thumb so its tip presses on the paper's face at `target` (map frame)."""
    tgt = bpy.data.objects.get("MapHandThumbTarget") or bpy.data.objects.new("MapHandThumbTarget", None)
    if tgt.name not in bpy.data.collections["MapHand"].objects:
        bpy.data.collections["MapHand"].objects.link(tgt)
    tgt.location = target
    pb = rig.pose.bones["thumb.03"]
    for c in list(pb.constraints):
        pb.constraints.remove(c)
    ik = pb.constraints.new('IK')
    ik.target = tgt
    ik.chain_count = 3
    bpy.context.view_layer.update()
    # bake the IK result into the pose and drop the constraint
    mats = {n: rig.pose.bones[n].matrix.copy() for n in ("thumb.01", "thumb.02", "thumb.03")}
    pb.constraints.remove(ik)
    for n in ("thumb.01", "thumb.02", "thumb.03"):
        rig.pose.bones[n].matrix = mats[n]
        bpy.context.view_layer.update()
    return rig.matrix_world @ rig.pose.bones["thumb.03"].tail


def export_map_hand(repo):
    """Bake the posed hand's procedural materials to textures with art/scripts/bake_export.py (as the
    lantern arm was) and export client/assets/map/map_hand.glb, static, in the map's frame (the game
    parents it to the map). The copy is mirrored, so its evaluated meshes get their normals flipped."""
    b = {}
    exec(open(os.path.join(repo, "art", "scripts", "bake_export.py")).read(), b)
    b["OUT_DIR"] = os.path.join(repo, "client", "assets", "map")
    plain = b["_eval_mesh"]

    def eval_mirror_safe(ob, dg):
        me = plain(ob, dg)
        if ob.matrix_world.determinant() < 0:
            me.flip_normals()
        return me

    b["_eval_mesh"] = eval_mirror_safe
    return b["export_asset"]("map_hand", "MapHand", size=2048, skip=("MapHand_HandRig", "MapHandThumb", "MapHandRoot"))


def build_hand(repo):
    """The whole right-hand pipeline: copy, pose, seat on the paper, IK the thumb, bake and export."""
    sc = bpy.data.scenes[SCENE]
    bpy.context.window.scene = sc
    sc.frame_set(sc.frame_end)
    root, rig, copies = build_map_hand()
    f, web = place_map_hand(root, rig)
    push = clear_paper(root, rig, copies["GloveHand"])
    web = web + Vector((0.0, push, 0.0))
    pose_thumb(rig, web + f * 0.032 + Vector((-0.016, -0.011 - push, 0.0)))
    return export_map_hand(repo)


# ---------------------------------------------------------------------------------------------
# Hand v2 (2026-10-09): posed from reference joint angles instead of one curl axis + a thumb IK.
# HandRig bone axes (measured): fingers bend about their local Z (negative = towards the palm) and
# spread about local X (positive = towards the thumb); local Y runs along the bone (twist).

def pose_joints(rig, angles):
    """angles: {bone: (flex_deg, spread_deg, twist_deg)}; flex > 0 bends towards the palm."""
    from mathutils import Euler
    for name, (flex, spread, twist) in angles.items():
        pb = rig.pose.bones[name]
        pb.rotation_mode = 'QUATERNION'
        q = Matrix.Rotation(math.radians(spread), 4, 'X').to_quaternion() \
            @ Matrix.Rotation(math.radians(-flex), 4, 'Z').to_quaternion() \
            @ Matrix.Rotation(math.radians(twist), 4, 'Y').to_quaternion()
        pb.rotation_quaternion = q
    bpy.context.view_layer.update()


def glove_points(glove, rig, select):
    """Evaluated glove vertices (map frame) whose nearest bone satisfies `select(bone_name)`."""
    segs = [(rig.matrix_world @ pb.head, rig.matrix_world @ pb.tail, pb.name) for pb in rig.pose.bones]

    def nearest(p):
        best, bd = None, 1e9
        for a, b, n in segs:
            ab = b - a
            t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-9)))
            d = (a + ab * t - p).length
            if d < bd:
                best, bd = n, d
        return best

    ev = glove.evaluated_get(bpy.context.evaluated_depsgraph_get())
    me = ev.to_mesh()
    pts = [glove.matrix_world @ v.co for v in me.vertices]
    out = [p for p in pts if select(nearest(p))]
    ev.to_mesh_clear()
    return out


def grip_sheet(sheet, thumb, index_a, index_b, bow=0.0035, dent=0.0012):
    """Bake the grip into the sheet's rest shape (the held panel B2 never moves): the edge bows back
    around the index finger behind it, and the thumb presses a shallow dent. Both push the paper away
    from the viewer (+Y), so the folded layers in front never intersect them."""
    me = sheet.data
    seg = index_b - index_a
    for v in me.vertices:
        p = v.co
        if p.x < PW / 2 or p.z > 0.0:  # B2 only
            continue
        # distance to the index finger's line (in the sheet plane)
        q = Vector((p.x, 0.0, p.z))
        t = max(0.0, min(1.0, (q - index_a).dot(seg) / seg.length_squared))
        d_idx = (index_a + seg * t - q).length
        edge = _ss(W / 2 - 0.035, W / 2, p.x)  # strongest at the free edge, where nothing flattens it
        wrap = math.exp(-(d_idx / 0.03) ** 2)
        d_th = (Vector((p.x, 0.0, p.z)) - Vector((thumb.x, 0.0, thumb.z))).length
        press = math.exp(-(d_th / 0.012) ** 2)
        p.y += bow * wrap * (0.35 + 0.65 * edge) + dent * press
    me.update()


# Joint angles (flex, spread, twist) in degrees, from the reference brief (GRASP "parallel
# extension" / palmar pinch, Hume 1990, Bain 2015): index and middle lie fairly flat behind the
# sheet, ring and little curl progressively more; DIP ~ 2/3 PIP; spread fans index towards the thumb
# and ring / little away from it.
FINGERS_V2 = {
    "index.01": (40, 6, 0), "index.02": (24, 0, 0), "index.03": (16, 0, 0),
    "middle.01": (45, 0, 0), "middle.02": (30, 0, 0), "middle.03": (20, 0, 0),
    "ring.01": (55, -5, 0), "ring.02": (52, 0, 0), "ring.03": (34, 0, 0),
    "pinky.01": (62, -12, 0), "pinky.02": (66, 0, 0), "pinky.03": (42, 0, 0),
}
GRIP_V2 = dict(lean=12.0, gap=0.0012, index_in=0.052, web_below=0.004,
               thumb=(W / 2 - 0.05, -H / 2 + 0.036))  # thumb pad: 5 cm in from the right, 3.6 cm up
FINGER_R = 0.0085  # glove finger radius (pad depth from the bone)
THUMB_R = 0.0095


def _palmar(rig, name, r, at=0.6):
    """A point on the palmar surface of a bone, `at` along it, and the palmar direction (world)."""
    pb = rig.pose.bones[name]
    mw = rig.matrix_world
    p = mw @ (pb.head + (pb.tail - pb.head) * at)
    n = (mw.to_3x3() @ (pb.matrix.to_3x3() @ Vector((1.0, 0.0, 0.0)))).normalized()
    return p + n * r, n


def _glove_mods(glove, on):
    for m in glove.modifiers:
        m.show_viewport = on


def seat_hand_v2(root, rig, glove, g=GRIP_V2):
    """Hold the sheet from below its bottom edge near the right corner (all the references do):
    the distal finger pads lie flat against the back of the sheet, fingers pointing up and leaning
    `lean` deg towards its middle; the web sits just below the edge, `index_in` m in from the corner."""
    pose_joints(rig, FINGERS_V2)
    root.matrix_world = Matrix.Identity(4)
    bpy.context.view_layer.update()
    pi, ni = _palmar(rig, "index.03", FINGER_R)
    pm, nm = _palmar(rig, "middle.03", FINGER_R)
    tip = lambda n: rig.matrix_world @ rig.pose.bones[n].tail
    base = lambda n: rig.matrix_world @ rig.pose.bones[n].head
    u = ((tip("index.03") + tip("middle.03")) - (base("index.02") + base("middle.02"))).normalized()
    n = (ni + nm).normalized()
    n = (n - u * n.dot(u)).normalized()
    S = Matrix.Diagonal((-1.0, 1.0, 1.0))
    mu, mn = S @ u, S @ n
    A = Matrix((mu, mn, mu.cross(mn))).transposed()
    lean = math.radians(g["lean"])
    ut = Vector((-math.sin(lean), 0.0, math.cos(lean)))
    nt = Vector((0.0, -1.0, 0.0))  # the pads press the back of the sheet, facing the viewer
    B = Matrix((ut, nt, ut.cross(nt))).transposed()
    R = B @ A.transposed()
    M = R.to_4x4() @ S.to_4x4()
    root.matrix_world = M
    bpy.context.view_layer.update()
    pi, _ = _palmar(rig, "index.03", FINGER_R)
    pm, _ = _palmar(rig, "middle.03", FINGER_R)
    web = (rig.matrix_world @ rig.pose.bones["thumb.01"].head + base("index.01")) * 0.5
    shift = Vector((W / 2 - g["index_in"] - pi.x, g["gap"] - min(pi.y, pm.y), -H / 2 - g["web_below"] - web.z))
    root.matrix_world = Matrix.Translation(shift) @ M
    bpy.context.view_layer.update()
    return {"u": u, "n": n, "index_pad": pi + shift, "middle_pad": pm + shift}


def solve_thumb(rig, target, g=GRIP_V2, iters=900, seed=3):
    """Pose thumb.01 (flex, spread, twist), thumb.02 and thumb.03 (flex) so the thumb's PAD (not its
    tip) lies on the sheet's face at `target`, pressing straight in (+Y). Random search + refinement,
    within the reference ranges: CMC flex 0-40, opposition 20-60, MCP 0-30, IP -15..15 (hyperextends
    under load)."""
    import random
    rnd = random.Random(seed)
    lo = [0.0, -60.0, -70.0, 0.0, -15.0]
    hi = [40.0, 60.0, 70.0, 30.0, 15.0]

    def apply(x):
        pose_joints(rig, {"thumb.01": (x[0], x[1], x[2]), "thumb.02": (x[3], 0, 0), "thumb.03": (x[4], 0, 0)})

    def cost(x):
        apply(x)
        p, nrm = _palmar(rig, "thumb.03", THUMB_R, at=0.45)
        press = 1.0 - (-nrm).dot(Vector((0.0, 1.0, 0.0)))  # pad normal should point into the paper
        return (p - target).length ** 2 * 1e4 + press * 2.0, p

    best = [20.0, 0.0, 0.0, 15.0, 0.0]
    bc, _ = cost(best)
    for i in range(iters):
        scale = 1.0 if i < iters // 2 else 0.25
        x = [min(h, max(l, b + rnd.gauss(0.0, (h - l) * 0.25 * scale))) for b, l, h in zip(best, lo, hi)]
        c, _ = cost(x)
        if c < bc:
            best, bc = x, c
    c, p = cost(best)
    return best, c, p


def build_hand_v2(repo, export=True):
    sc = bpy.data.scenes[SCENE]
    bpy.context.window.scene = sc
    sc.frame_set(sc.frame_end)
    root, rig, copies = build_map_hand()
    glove = copies["GloveHand"]
    _glove_mods(glove, False)
    info = seat_hand_v2(root, rig, glove)
    tx, tz = GRIP_V2["thumb"]
    target = Vector((tx, -GRIP_V2["gap"], tz))
    x, c, pad = solve_thumb(rig, target)
    _glove_mods(glove, True)
    bpy.context.view_layer.update()
    info.update(thumb=x, thumb_cost=c, thumb_pad=pad)
    return root, rig, copies, info


GRIP_V3 = dict(lean=14.0, back=9.0, palm_back=18.0, gap=0.0012, index_in=0.064, web_below=0.002,
               thumb=(W / 2 - 0.066, -H / 2 + 0.036))


def seat_hand_v3(root, rig, glove, g=GRIP_V3):
    """The grip every reference shows (photos, Far Cry 2): the sheet's bottom edge sits in the web
    between thumb and index, near the right corner; the hand stands below it with the palm facing
    sideways towards the middle of the sheet (perpendicular to it, turned `palm_back` deg away from
    the eye); the thumb runs up the face, index and middle up the back, ring and little curl into the
    palm below the edge. The fingers point up, leaning `lean` deg in towards the middle and `back` deg
    away from the eye (wrist extension), so the forearm rises from below towards the camera."""
    from mathutils import Matrix
    pose_joints(rig, g.get("fingers", FINGERS_V2))
    lean, back, pb = (math.radians(g[k]) for k in ("lean", "back", "palm_back"))
    f = (Matrix.Rotation(-lean, 3, 'Y') @ Matrix.Rotation(-back, 3, 'X')) @ Vector((0.0, 0.0, 1.0))
    c0 = Vector((0.0, -1.0, 0.0))  # the thumb side faces the eye
    c0 = (c0 - f * c0.dot(f)).normalized()
    c0 = Matrix.Rotation(pb, 3, f) @ c0
    c2 = -f
    c1 = c2.cross(c0)  # the palm
    if c1.y < 0.0:  # turned the wrong way: the palm must turn away from the eye, not towards it
        c0 = Matrix.Rotation(-2.0 * pb, 3, f) @ c0
        c1 = c2.cross(c0)
    R = Matrix((c0, c1, c2)).transposed()
    M = R.to_4x4() @ Matrix.Diagonal((-1.0, 1.0, 1.0, 1.0))
    root.matrix_world = M
    bpy.context.view_layer.update()
    P = lambda n, tail=False: rig.matrix_world @ (rig.pose.bones[n].tail if tail else rig.pose.bones[n].head)
    web = (P("thumb.01", True) + P("index.01")) * 0.5
    if "web_in" in g:  # place by the web: the sheet's edge sits in it, `web_in` m from the corner
        shift = Vector((W / 2 - g["web_in"] - web.x, 0.0, -H / 2 - g["web_below"] - web.z))
    else:
        pad, _ = _palmar(rig, "index.03", FINGER_R)
        shift = Vector((W / 2 - g["index_in"] - pad.x, 0.0, -H / 2 - g["web_below"] - web.z))
    root.matrix_world = Matrix.Translation(shift) @ M
    bpy.context.view_layer.update()
    return {"palm": c1, "fingers": f}


def clear_sheet_back(root, rig, glove, gap=0.0012):
    """Slide the hand along Y so no non-thumb glove vertex over the sheet is in front of the paper."""
    from mathutils import Matrix
    inside = lambda p: p.x < W / 2 and p.z > -H / 2
    pts = [p for p in glove_points(glove, rig, lambda b: b is not None and not b.startswith("thumb")) if inside(p)]
    lo = min(p.y for p in pts) if pts else gap
    dy = gap - lo
    root.matrix_world = Matrix.Translation(Vector((0.0, dy, 0.0))) @ root.matrix_world
    bpy.context.view_layer.update()
    return dy


def build_hand_v3(repo, export=True, g=GRIP_V3):
    sc = bpy.data.scenes[SCENE]
    bpy.context.window.scene = sc
    sc.frame_set(sc.frame_end)
    root, rig, copies = build_map_hand()
    glove = copies["GloveHand"]
    info = seat_hand_v3(root, rig, glove, g)
    info["dy"] = clear_sheet_back(root, rig, glove, g["gap"])
    _glove_mods(glove, False)
    tx, tz = g["thumb"]
    x, c, pad = solve_thumb(rig, Vector((tx, -g["gap"] - 0.001, tz)))
    _glove_mods(glove, True)
    bpy.context.view_layer.update()
    info.update(thumb=x, thumb_cost=c, thumb_pad=pad)
    return root, rig, copies, info


def solve_thumb_mesh(rig, glove, target, iters=700, seed=5):
    """Pose the thumb against the real glove surface (subdivision off for speed): no thumb vertex
    behind the paper, the pad just touching it with a flat contact patch (the pad flattens, the tip
    doesn't dig in), and the thumb tip near `target` (x, z on the sheet). Ranges from the brief:
    CMC flex 0-40, opposition/spread +-60, twist +-70, MCP 0-30, IP -15..15."""
    import random
    rnd = random.Random(seed)
    sub = glove.modifiers.get("Subdiv")
    if sub:
        sub.show_viewport = False
    groups = {vg.index: vg.name for vg in glove.vertex_groups if vg.name.startswith("thumb")}
    thumb_vs, distal_vs = [], set()
    for v in glove.data.vertices:
        w = {groups[gr.group]: gr.weight for gr in v.groups if gr.group in groups}
        if sum(w.values()) > 0.5:
            thumb_vs.append(v.index)
            if w.get("thumb.03", 0.0) > 0.5:
                distal_vs.add(v.index)
    lo = [-10.0, -80.0, -90.0, -5.0, -15.0]
    hi = [50.0, 80.0, 90.0, 35.0, 20.0]
    dg = bpy.context.evaluated_depsgraph_get

    def cost(x):
        pose_joints(rig, {"thumb.01": (x[0], x[1], x[2]), "thumb.02": (x[3], 0, 0), "thumb.03": (x[4], 0, 0)})
        ev = glove.evaluated_get(dg())
        me = ev.to_mesh()
        mw = glove.matrix_world
        pen, front, ys_d = 0.0, -1.0, []
        for i in thumb_vs:
            p = mw @ me.vertices[i].co
            if p.x < W / 2 and p.z > -H / 2:
                pen += max(0.0, p.y + 0.0004) ** 2
                front = max(front, p.y)
                if i in distal_vs:
                    ys_d.append(p.y)
        ev.to_mesh_clear()
        flat = sum(1 for y in ys_d if y > front - 0.003) / max(1, len(ys_d))
        tip = rig.matrix_world @ rig.pose.bones["thumb.03"].tail
        reach = (tip.x - target.x) ** 2 + (tip.z - target.z) ** 2
        lift = max(0.0, -tip.y - 0.011) ** 2  # the tip lies along the sheet (bone ~1 cm off it), not up off it
        return pen * 1e6 + (front + 0.0006) ** 2 * 1e5 + max(0.0, 0.3 - flat) * 4.0 + reach * 1e4 + lift * 3e4

    best = [20.0, 0.0, 0.0, 15.0, 0.0]
    bc = cost(best)
    for i in range(iters):
        s = 1.0 if i < iters // 2 else 0.3
        x = [min(h, max(l, b + rnd.gauss(0.0, (h - l) * 0.2 * s))) for b, l, h in zip(best, lo, hi)]
        c = cost(x)
        if c < bc:
            best, bc = x, c
    cost(best)
    if sub:
        sub.show_viewport = True
    bpy.context.view_layer.update()
    return best, bc


def build_hand_v4(repo, g=GRIP_V3, tip_up=0.045, iters=1400):
    """v3 seating + the mesh-based thumb (tip `tip_up` m above the bottom edge, 5 cm in)."""
    sc = bpy.data.scenes[SCENE]
    bpy.context.window.scene = sc
    sc.frame_set(sc.frame_end)
    root, rig, copies = build_map_hand()
    glove = copies["GloveHand"]
    info = seat_hand_v3(root, rig, glove, g)
    info["dy"] = clear_sheet_back(root, rig, glove, g["gap"])
    tx, _ = g["thumb"]
    x, c = solve_thumb_mesh(rig, glove, Vector((tx, 0.0, -H / 2 + tip_up)), iters=iters)
    info.update(thumb=x, thumb_cost=c)
    return root, rig, copies, info



def grip_sheet_bottom(sheet, rig, bow=0.003, dent=0.0012):
    """The grip baked into the held panel's rest shape (B2 never moves): the paper bows back over the
    index and middle fingers behind it, most at the bottom edge where nothing flattens it, and the
    thumb pad presses a shallow dent. Both push the paper away from the eye (+Y), so the folded
    layers in front never intersect them. Call on a freshly built sheet (it accumulates)."""
    mw = rig.matrix_world
    P = lambda n, t=0.5: mw @ (rig.pose.bones[n].head + (rig.pose.bones[n].tail - rig.pose.bones[n].head) * t)
    lines = [(P("index.01", 0.0), P("index.03", 1.0)), (P("middle.01", 0.0), P("middle.03", 1.0))]
    pad = P("thumb.03", 0.45)
    for v in sheet.data.vertices:
        p = v.co
        if p.x < PW / 2 or p.z > 0.0:
            continue
        q = Vector((p.x, 0.0, p.z))
        wrap = 0.0
        for a, b in lines:
            a, b = Vector((a.x, 0.0, a.z)), Vector((b.x, 0.0, b.z))
            seg = b - a
            t = max(0.0, min(1.0, (q - a).dot(seg) / max(seg.length_squared, 1e-9)))
            wrap = max(wrap, math.exp(-((a + seg * t - q).length / 0.025) ** 2))
        edge = 1.0 - _ss(-H / 2, -H / 2 + 0.06, p.z)
        press = math.exp(-((q - Vector((pad.x, 0.0, pad.z))).length / 0.013) ** 2)
        p.y += bow * wrap * (0.3 + 0.7 * edge) + dent * press
    sheet.data.update()


def build_everything_v4(repo, tex_dir="", bake_paper=False):
    """Map (sheet, rig, unfold) + the v4 hand + the grip in the paper; bake the hand; export both."""
    res = build_all(repo, tex_dir, bake=bake_paper)
    root, rig, copies, info = build_hand_v4(repo)
    sheet = bpy.data.objects["MapSheet"]
    grip_sheet_bottom(sheet, rig)
    sc = bpy.data.scenes[SCENE]
    sc.frame_set(sc.frame_end)
    export(repo, bpy.data.objects["MapRig"], sheet)
    info["hand_glb"] = export_map_hand(repo)
    save_blend(repo)
    return info



# v5: the back of the hand leans OUT from the sheet (as in the main reference photo) and the index and
# middle stay fairly straight behind it (GRASP parallel extension), their curl bringing the fingertips
# back up and in; ring and little curl into the palm below the edge.
FINGERS_V5 = {
    "index.01": (34, 6, 0), "index.02": (14, 0, 0), "index.03": (9, 0, 0),
    "middle.01": (40, 0, 0), "middle.02": (20, 0, 0), "middle.03": (13, 0, 0),
    "ring.01": (58, -5, 0), "ring.02": (60, 0, 0), "ring.03": (40, 0, 0),
    "pinky.01": (66, -12, 0), "pinky.02": (72, 0, 0), "pinky.03": (46, 0, 0),
}
GRIP_V5 = dict(lean=-32.0, back=10.0, palm_back=18.0, gap=0.0012, web_in=0.055, web_below=0.003,
               thumb=(W / 2 - 0.075, -H / 2 + 0.036), fingers=FINGERS_V5)


# v6 (worked out from the main reference photo): the finger pads press the sheet from behind, so
# they face the eye, and so does the palm below the edge. Index and middle rise nearly straight
# behind the sheet; the thumb comes up its face from the outer side, its pad pressing in; ring and
# little curl into the palm below the edge.
FINGERS_V6 = {
    "index.01": (12, 4, 0), "index.02": (10, 0, 0), "index.03": (6, 0, 0),
    "middle.01": (16, 0, 0), "middle.02": (12, 0, 0), "middle.03": (8, 0, 0),
    "ring.01": (55, -6, 0), "ring.02": (65, 0, 0), "ring.03": (42, 0, 0),
    "pinky.01": (68, -14, 0), "pinky.02": (75, 0, 0), "pinky.03": (48, 0, 0),
}
GRIP_V6 = dict(lean=22.0, back=12.0, palm_out=20.0, gap=0.0012, mcp_in=0.07, mcp_below=0.012,
               fingers=FINGERS_V6)


def seat_hand_v6(root, rig, glove, g=GRIP_V6):
    from mathutils import Matrix
    pose_joints(rig, g["fingers"])
    lean, back, po = (math.radians(g[k]) for k in ("lean", "back", "palm_out"))
    f = (Matrix.Rotation(-lean, 3, 'Y') @ Matrix.Rotation(-back, 3, 'X')) @ Vector((0.0, 0.0, 1.0))
    palm = Vector((0.0, -1.0, 0.0))
    palm = (palm - f * palm.dot(f)).normalized()
    palm = Matrix.Rotation(po, 3, f) @ palm  # turned a little towards the outside, as in the photo
    c2, c1 = -f, palm
    c0 = c1.cross(c2)
    R = Matrix((c0, c1, c2)).transposed()
    M = R.to_4x4() @ Matrix.Diagonal((-1.0, 1.0, 1.0, 1.0))
    root.matrix_world = M
    bpy.context.view_layer.update()
    mcp = rig.matrix_world @ rig.pose.bones["index.01"].head
    thumb_base = rig.matrix_world @ rig.pose.bones["thumb.01"].head
    shift = Vector((W / 2 - g["mcp_in"] - mcp.x, 0.0, -H / 2 - g["mcp_below"] - mcp.z))
    root.matrix_world = Matrix.Translation(shift) @ M
    bpy.context.view_layer.update()
    return {"thumb_side_x": (thumb_base - mcp).x, "palm": palm}


FINGER_GROUPS = ("index", "middle", "ring", "pinky")


def _group_verts(glove, prefixes, min_w=0.5):
    idx = {vg.index for vg in glove.vertex_groups if vg.name.startswith(prefixes)}
    return [v.index for v in glove.data.vertices if sum(gr.weight for gr in v.groups if gr.group in idx) > min_w]


def clear_fingers_back(root, rig, glove, gap=0.0012):
    """Slide the hand along Y so every finger vertex (index..little, by weight) above the bottom edge
    is behind the paper. The thumb and its fleshy base stay in front; below the edge nothing matters."""
    from mathutils import Matrix
    vs = _group_verts(glove, FINGER_GROUPS)
    ev = glove.evaluated_get(bpy.context.evaluated_depsgraph_get())
    me = ev.to_mesh()
    mw = glove.matrix_world
    ys = [p.y for p in (mw @ me.vertices[i].co for i in vs) if p.z > -H / 2 and p.x < W / 2]
    ev.to_mesh_clear()
    dy = gap - min(ys) if ys else 0.0
    root.matrix_world = Matrix.Translation(Vector((0.0, dy, 0.0))) @ root.matrix_world
    bpy.context.view_layer.update()
    return dy


def thumb_reach_probe(rig, glove, steps=((-30, 51, 20), (-80, 81, 20), (-90, 91, 45))):
    """Coarse sweep of thumb.01 (flex, spread, twist) with the phalanges nearly straight: for each pose,
    the thumb tip's height above the bottom edge, its y and x, and how many thumb vertices end up
    behind the paper. Used to see what the thumb can physically reach from a hand placement."""
    import itertools
    sub = glove.modifiers.get("Subdiv")
    if sub:
        sub.show_viewport = False
    tv = _group_verts(glove, ("thumb",))
    rows = []
    for f, s, tw in itertools.product(*(range(*a) for a in steps)):
        pose_joints(rig, {"thumb.01": (f, s, tw), "thumb.02": (5, 0, 0), "thumb.03": (0, 0, 0)})
        ev = glove.evaluated_get(bpy.context.evaluated_depsgraph_get())
        me = ev.to_mesh()
        mw = glove.matrix_world
        pen = sum(1 for i in tv for p in (mw @ me.vertices[i].co,) if p.x < W / 2 and p.z > -H / 2 and p.y > -0.0004)
        ev.to_mesh_clear()
        tip = rig.matrix_world @ rig.pose.bones["thumb.03"].tail
        rows.append((round(tip.z + H / 2, 4), round(tip.y, 4), round(tip.x, 3), pen, (f, s, tw)))
    if sub:
        sub.show_viewport = True
    bpy.context.view_layer.update()
    return rows


# ---------------------------------------------------------------------------------------------
# Hand v7: solve the whole grip at once against the real glove surface (subdivision off for speed),
# instead of placing it by hand. Variables: the hand's rotation (rotation vector, relative to the
# reference-derived start) and position, and the thumb (CMC flex/spread/twist, MCP, IP).

GRIP_V7 = dict(thumb_pad=(W / 2 - 0.06, -H / 2 + 0.017), web=(W / 2 - 0.05, -H / 2 - 0.004), gap=0.0012)


def solve_hand_pose(root, rig, glove, start, g=GRIP_V7, iters=2500, seed=11, fingers=FINGERS_V6):
    import random
    from mathutils import Matrix
    rnd = random.Random(seed)
    sub = glove.modifiers.get("Subdiv")
    if sub:
        sub.show_viewport = False
    pose_joints(rig, fingers)
    fv = _group_verts(glove, FINGER_GROUPS)
    cv = _group_verts(glove, ("index.03", "middle.03"))
    tv = _group_verts(glove, ("thumb",))
    td = _group_verts(glove, ("thumb.03",))
    hide_vs = _group_verts(glove, ("index.02", "index.03", "middle.02", "middle.03"))
    eye, elbow = cam_in_map()
    tx, tz = g["thumb_pad"]
    wx, wz = g["web"]
    gap = g["gap"]
    S = Matrix.Diagonal((-1.0, 1.0, 1.0, 1.0))
    pivot = rig.matrix_world @ rig.pose.bones["index.01"].head  # turn the hand about its index knuckle

    def apply(x):
        rv = Vector(x[0:3])
        R = Matrix.Rotation(rv.length, 4, rv.normalized()) if rv.length > 1e-9 else Matrix.Identity(4)
        root.matrix_world = Matrix.Translation(pivot + Vector(x[3:6])) @ R @ Matrix.Translation(-pivot) @ start @ S
        pose_joints(rig, {"thumb.01": (x[6], x[7], x[8]), "thumb.02": (x[9], 0, 0), "thumb.03": (x[10], 0, 0)})

    def cost(x, detail=False):
        apply(x)
        ev = glove.evaluated_get(bpy.context.evaluated_depsgraph_get())
        me = ev.to_mesh()
        mw = glove.matrix_world
        co = lambda i: mw @ me.vertices[i].co
        over = lambda p: p.z > -H / 2 and p.x < W / 2
        pen_f = sum(max(0.0, gap - p.y) ** 2 for p in map(co, fv) if over(p))
        pen_t = sum(max(0.0, p.y + gap) ** 2 for p in map(co, tv) if over(p))
        c_back = [p.y for p in map(co, cv) if over(p)]
        c_front = [p for p in map(co, td) if over(p)]
        ev.to_mesh_clear()
        touch_b = (min(c_back) - gap) ** 2 if c_back else 0.01
        if c_front:
            yf = max(p.y for p in c_front)
            touch_f = (yf + gap) ** 2
            pad = [p for p in c_front if p.y > yf - 0.003]
            cx = sum(p.x for p in pad) / len(pad)
            cz = sum(p.z for p in pad) / len(pad)
            place = (cx - tx) ** 2 + (cz - tz) ** 2
        else:
            touch_f, place = 0.01, 0.01
        P = lambda n, t=False: rig.matrix_world @ (rig.pose.bones[n].tail if t else rig.pose.bones[n].head)
        web = (P("thumb.01", True) + P("index.01")) * 0.5
        web_c = (web.x - wx) ** 2 + (web.z - wz) ** 2
        wrist = P("hand")
        arm = (P("hand") - P("hand", True)).normalized()  # from the knuckles back through the wrist
        to_elbow = (elbow - wrist).normalized()
        arm_c = 1.0 - arm.dot(to_elbow)
        # the thumb nail faces the eye (the pad presses the sheet, so its back is what you see)
        tb = rig.pose.bones["thumb.03"]
        dorsal = -(rig.matrix_world.to_3x3() @ (tb.matrix.to_3x3() @ Vector((1.0, 0.0, 0.0)))).normalized()
        nail_c = 1.0 - dorsal.dot((eye - P("thumb.03", True)).normalized())
        # (review 2) the palm turns towards the sheet, not the camera, and index / middle stay hidden
        # behind the paper: their outer segments above the bottom edge
        # (the hand bone's local Z is the palm normal: measured, rig +Y)
        palm_n = (rig.matrix_world.to_3x3() @ (rig.pose.bones["hand"].matrix.to_3x3() @ Vector((0.0, 0.0, 1.0)))).normalized()
        palm_c = max(0.0, palm_n.dot((eye - wrist).normalized()) - 0.2)
        hidden_c = 0.0
        if hide_vs:
            ev2 = glove.evaluated_get(bpy.context.evaluated_depsgraph_get())
            me2 = ev2.to_mesh()
            below = sum(1 for i in hide_vs if (mw @ me2.vertices[i].co).z < -H / 2)
            ev2.to_mesh_clear()
            hidden_c = below / len(hide_vs)
        terms = dict(pen=(pen_f + pen_t) * 1e6, touch=(touch_b + touch_f) * 2e5, place=place * 3e3,
                     web=web_c * 2e3, arm=arm_c * 6.0, nail=nail_c * 0.8, palm=palm_c * 4.0, hidden=hidden_c * 4.0)
        return (terms if detail else sum(terms.values()))

    # the thumb's tip joint bends 12-28 deg at the paper's edge (reference): only its tip segment lies on the sheet
    # (twist capped at +-75: beyond that the glove's skin pinches into a flap at the thumb's base)
    lo = [-1.2, -1.2, -1.2, -0.3, -0.3, -0.3, -10.0, -80.0, -75.0, 0.0, 18.0]
    hi = [1.2, 1.2, 1.2, 0.3, 0.3, 0.3, 50.0, 80.0, 75.0, 40.0, 38.0]
    sd = [0.25, 0.25, 0.25, 0.02, 0.02, 0.02, 12.0, 20.0, 25.0, 8.0, 6.0]
    best = [0.0, 0.0, 0.0] + list(start.to_translation() * 0.0) + [20.0, 0.0, 0.0, 10.0, 18.0]
    best[3:6] = [0.0, 0.0, 0.0]
    bc = cost(best)
    for i in range(iters):
        k = 1.0 - i / iters
        x = [min(h, max(l, b + rnd.gauss(0.0, s * (0.15 + 0.85 * k)))) for b, l, h, s in zip(best, lo, hi, sd)]
        c = cost(x)
        if c < bc:
            best, bc = x, c
    terms = cost(best, detail=True)
    if sub:
        sub.show_viewport = True
    bpy.context.view_layer.update()
    return best, bc, terms


def build_hand_v7(repo, iters=2500):
    from mathutils import Matrix
    sc = bpy.data.scenes[SCENE]
    bpy.context.window.scene = sc
    sc.frame_set(sc.frame_end)
    root, rig, copies = build_map_hand()
    glove = copies["GloveHand"]
    gp = dict(GRIP_V6)
    seat_hand_v6(root, rig, glove, gp)
    start = root.matrix_world @ Matrix.Diagonal((-1.0, 1.0, 1.0, 1.0))  # un-mirrored start frame
    x, c, terms = solve_hand_pose(root, rig, glove, start, iters=iters)
    return root, rig, copies, {"x": x, "cost": c, "terms": terms}


def apply_hand_solution(root, rig, start, x, fingers=FINGERS_V6):
    """Put the hand in a solve_hand_pose() solution `x` (same pivot: the index knuckle at `start`)."""
    from mathutils import Matrix
    S = Matrix.Diagonal((-1.0, 1.0, 1.0, 1.0))
    pose_joints(rig, fingers)
    root.matrix_world = start @ S
    bpy.context.view_layer.update()
    pivot = rig.matrix_world @ rig.pose.bones["index.01"].head
    rv = Vector(x[0:3])
    R = Matrix.Rotation(rv.length, 4, rv.normalized()) if rv.length > 1e-9 else Matrix.Identity(4)
    root.matrix_world = Matrix.Translation(pivot + Vector(x[3:6])) @ R @ Matrix.Translation(-pivot) @ start @ S
    pose_joints(rig, {"thumb.01": (x[6], x[7], x[8]), "thumb.02": (x[9], 0, 0), "thumb.03": (x[10], 0, 0)})
    bpy.context.view_layer.update()


def preview_shots(out_dir, prefix, res=(960, 540)):
    """Eye / close / side / back renders of the held map (MapWork preview cameras)."""
    sc = bpy.data.scenes[SCENE]

    def shot(cam, loc, tgt, lens, path):
        cam.location = loc
        cam.rotation_mode = 'QUATERNION'
        cam.rotation_quaternion = (tgt - loc).to_track_quat('-Z', 'Y')
        cam.data.lens = lens
        sc.camera = cam
        sc.render.resolution_x, sc.render.resolution_y = res
        sc.render.filepath = path
        bpy.ops.render.render(write_still=True)

    eye = bpy.data.objects["MapPrevCam"]
    sc.camera = eye
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.render.filepath = os.path.join(out_dir, f"{prefix}_eye.png")
    bpy.ops.render.render(write_still=True)
    grip = Vector((W / 2 - 0.06, 0.0, -H / 2 + 0.01))
    shot(bpy.data.objects["MapPrevCam3"], eye.location.copy(), grip, 90, os.path.join(out_dir, f"{prefix}_close.png"))
    shot(bpy.data.objects["MapPrevCam2"], grip + Vector((0.28, -0.08, 0.02)), grip, 50, os.path.join(out_dir, f"{prefix}_side.png"))
    shot(bpy.data.objects["MapPrevCam2"], grip + Vector((-0.05, 0.3, 0.05)), grip, 50, os.path.join(out_dir, f"{prefix}_back.png"))
    sc.camera = eye


def build_everything_v7(repo, seeds=(4, 1, 2, 3), iters=4000):
    """Map (sheet, rig, unfold) + the solved right hand (best of several seeds) + the grip pressed
    into the paper; bake the hand; export map.glb and map_hand.glb; save art/map.blend."""
    from mathutils import Matrix
    build_all(repo, "", bake=False)
    sc = bpy.data.scenes[SCENE]
    sc.frame_set(sc.frame_end)
    root, rig, copies = build_map_hand()
    glove = copies["GloveHand"]
    seat_hand_v6(root, rig, glove, dict(GRIP_V6))
    start = root.matrix_world @ Matrix.Diagonal((-1.0, 1.0, 1.0, 1.0))
    runs = []
    for seed in seeds:
        apply_hand_solution(root, rig, start, [0.0] * 6 + [20.0, 0.0, 0.0, 10.0, 0.0])
        root.matrix_world = start @ Matrix.Diagonal((-1.0, 1.0, 1.0, 1.0))
        bpy.context.view_layer.update()
        x, c, terms = solve_hand_pose(root, rig, glove, start, iters=iters, seed=seed)
        runs.append((c, seed, x, terms))
    runs.sort(key=lambda r: r[0])
    c, seed, x, terms = runs[0]
    apply_hand_solution(root, rig, start, x)
    sheet = bpy.data.objects["MapSheet"]
    grip_sheet_bottom(sheet, rig)
    export(repo, bpy.data.objects["MapRig"], sheet)
    hand = export_map_hand(repo)
    save_blend(repo)
    return {"cost": c, "seed": seed, "x": x, "terms": terms, "hand": hand}



# v8 (after review 1): index and middle together and curled, pads pressing the back of the sheet
# behind the thumb (no "peace sign"); ring and little tucked tight into the palm.
FINGERS_V8 = {
    "index.01": (20, -2, 0), "index.02": (28, 0, 0), "index.03": (18, 0, 0),
    "middle.01": (22, 2, 0), "middle.02": (30, 0, 0), "middle.03": (20, 0, 0),
    "ring.01": (65, -3, 0), "ring.02": (78, 0, 0), "ring.03": (52, 0, 0),
    "pinky.01": (75, -8, 0), "pinky.02": (84, 0, 0), "pinky.03": (56, 0, 0),
}


def build_everything_v8(repo, seeds=(4, 1, 2, 3, 5, 6), iters=4000, fingers=FINGERS_V8):
    """v7 with the review-1 fixes: fingers V8, thumb tip segment only on the sheet (IP bent), nail to
    the eye, forearm from the bottom-right corner, a deeper thumb dent. Returns the thumb pad's UV
    (for the contact shading in map_parchment.gdshader)."""
    from mathutils import Matrix
    build_all(repo, "", bake=False)
    sc = bpy.data.scenes[SCENE]
    sc.frame_set(sc.frame_end)
    root, rig, copies = build_map_hand()
    glove = copies["GloveHand"]
    gp = dict(GRIP_V6)
    gp["fingers"] = fingers
    seat_hand_v6(root, rig, glove, gp)
    start = root.matrix_world @ Matrix.Diagonal((-1.0, 1.0, 1.0, 1.0))
    runs = []
    for seed in seeds:
        apply_hand_solution(root, rig, start, [0.0] * 6 + [20.0, 0.0, 0.0, 10.0, 18.0], fingers)
        x, c, terms = solve_hand_pose(root, rig, glove, start, iters=iters, seed=seed, fingers=fingers)
        runs.append((c, seed, x, terms))
    runs.sort(key=lambda r: r[0])
    c, seed, x, terms = runs[0]
    apply_hand_solution(root, rig, start, x, fingers)
    sheet = bpy.data.objects["MapSheet"]
    grip_sheet_bottom(sheet, rig, dent=0.002)
    pad = rig.matrix_world @ (rig.pose.bones["thumb.03"].head + (rig.pose.bones["thumb.03"].tail - rig.pose.bones["thumb.03"].head) * 0.5)
    uv = ((pad.x + W / 2) / W, 1.0 - (pad.z + H / 2) / H)  # Godot UV (v down)
    export(repo, bpy.data.objects["MapRig"], sheet)
    hand = export_map_hand(repo)
    save_blend(repo)
    return {"cost": c, "seed": seed, "x": x, "terms": terms, "hand": hand, "thumb_uv": uv,
            "all": [(r[0], r[1]) for r in runs]}



# v9 (after review 2): ring and little tucked into a compact fist under the edge; index and middle
# drawn together (no V), curled so their pads press the back of the sheet behind the thumb.
FINGERS_V9 = {
    "index.01": (24, -6, 0), "index.02": (30, 0, 0), "index.03": (20, 0, 0),
    "middle.01": (26, 4, 0), "middle.02": (32, 0, 0), "middle.03": (21, 0, 0),
    "ring.01": (80, 2, 0), "ring.02": (95, 0, 0), "ring.03": (60, 0, 0),
    "pinky.01": (88, 6, 0), "pinky.02": (98, 0, 0), "pinky.03": (62, 0, 0),
}



def build_everything_v10(repo, palm_outs=(-45.0, 20.0), seeds=(7, 3, 9), iters=4000, fingers=FINGERS_V9):
    """v8 pipeline, trying two starting turns of the hand (palm towards the sheet, -45; or towards
    the eye, +20) and keeping the best solve."""
    from mathutils import Matrix
    build_all(repo, "", bake=False)
    sc = bpy.data.scenes[SCENE]
    sc.frame_set(sc.frame_end)
    root, rig, copies = build_map_hand()
    glove = copies["GloveHand"]
    runs = []
    for po in palm_outs:
        gp = dict(GRIP_V6)
        gp["fingers"] = fingers
        gp["palm_out"] = po
        seat_hand_v6(root, rig, glove, gp)
        start = root.matrix_world @ Matrix.Diagonal((-1.0, 1.0, 1.0, 1.0))
        for seed in seeds:
            apply_hand_solution(root, rig, start, [0.0] * 6 + [20.0, 0.0, 0.0, 10.0, 24.0], fingers)
            x, c, terms = solve_hand_pose(root, rig, glove, start, iters=iters, seed=seed, fingers=fingers)
            runs.append((c, po, seed, x, terms, start))
    runs.sort(key=lambda r: r[0])
    c, po, seed, x, terms, start = runs[0]
    apply_hand_solution(root, rig, start, x, fingers)
    sheet = bpy.data.objects["MapSheet"]
    grip_sheet_bottom(sheet, rig, dent=0.002)
    pad = rig.matrix_world @ (rig.pose.bones["thumb.03"].head + (rig.pose.bones["thumb.03"].tail - rig.pose.bones["thumb.03"].head) * 0.5)
    uv = ((pad.x + W / 2) / W, 1.0 - (pad.z + H / 2) / H)
    export(repo, bpy.data.objects["MapRig"], sheet)
    hand = export_map_hand(repo)
    save_blend(repo)
    return {"cost": c, "palm_out": po, "seed": seed, "x": x, "terms": terms, "thumb_uv": uv,
            "all": [(r[0], r[1], r[2]) for r in runs]}



def rebuild_map_v11(repo):
    """The open sheet with the flutter (no unfold), the current hand's grip pressed into it, exported.
    The hand (MapHand, solved by build_everything_v10) is kept as it is."""
    build_all(repo, "", bake=False)
    sc = bpy.data.scenes[SCENE]
    sc.frame_set(sc.frame_end)
    sheet = bpy.data.objects["MapSheet"]
    grip_sheet_bottom(sheet, bpy.data.objects["MapHand_HandRig"], dent=0.002)
    path = export(repo, bpy.data.objects["MapRig"], sheet)
    save_blend(repo)
    return path
