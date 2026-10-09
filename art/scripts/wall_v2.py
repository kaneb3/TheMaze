"""Ring 1 wall v2 (2026-10-09): scanned stone + dense real-leaf hedge + ivy creeping over the stone.

exec(open(r"<repo>/art/scripts/wall_v2.py").read(), g); g["build_all"](dl_dir)

Research-driven (see the 2026-10-09 wall review): real relief from a CC0 photoscan height map
(Poly Haven rough_block_wall, 3.04 x 3.0 m) instead of flat bevelled boxes; foliage as single
real-leaf cards (CC0 ambientCG LeafSet017/022/024 atlas, art/scripts/build_leaf_atlas.py) placed
in 3 depth layers over a dark inner shell, with normals transferred from the hedge envelope,
depth AO and a random tint per leaf in COLOR_0, and an LOD1 that keeps 30% of the leaves 1.6x
larger. Materials are assigned in Godot by object name; Blender only carries placeholders.
"""

import json
import math
import random

import bmesh
import bpy
import mathutils.noise
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

REPO = r"C:\Users\kaneb\Documents\the-maze"
HALF_X = 1.62  # wall half-length (ends hide inside the pillars)
STONE_TOP = 1.9  # where the foliage hem starts (grime, leaks and contact shade key off this)
WALL_TOP = 7.0  # the stone itself runs the full height; ivy and hedge grow over it
STONE_FACE_Y = 0.30  # mean face plane (core is 0.4 thick)
STONE_DEPTH = 0.04  # relief from the (softened) height map: joints ~2 cm in, faces ~2 cm out
STONE_TILE = (3.04, 3.0)  # metres covered by one texture tile
HEDGE_BOTTOM = 1.75
SHELL_INSET = 0.14  # the opaque shell sits this far inside the leaf envelope
SHELL_SEAL = STONE_TOP - 0.04  # the shell's bottom sits just inside the stone band (sealed, no gap)
COLL = "Kit_Wall2"


def _coll():
    c = bpy.data.collections.get(COLL)
    if c is None:
        c = bpy.data.collections.new(COLL)
        bpy.data.scenes["Ring1Kit"].collection.children.link(c)
    return c


def _replace(name, me):
    old = bpy.data.objects.get(name)
    if old:
        bpy.data.objects.remove(old, do_unlink=True)
    ob = bpy.data.objects.new(name, me)
    _coll().objects.link(ob)
    return ob


def _mat(name, color):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.diffuse_color = (*color, 1.0)
    return m


# ---------------------------------------------------------------------------------------------
# stone

class Height:
    def __init__(self, path):
        img = bpy.data.images.load(path, check_existing=True)
        self.w, self.h = img.size
        px = img.pixels[:]
        self.v = px[0::4]  # red channel, rows bottom-up

    def sample(self, u, v):
        """Bilinear, wrapping; u,v in tile units with v up (Blender image rows are bottom-up)."""
        x = (u % 1.0) * self.w - 0.5
        y = (v % 1.0) * self.h - 0.5
        x0, y0 = math.floor(x), math.floor(y)
        fx, fy = x - x0, y - y0
        def p(xx, yy):
            return self.v[(yy % self.h) * self.w + (xx % self.w)]
        a = p(x0, y0) * (1 - fx) + p(x0 + 1, y0) * fx
        b = p(x0, y0 + 1) * (1 - fx) + p(x0 + 1, y0 + 1) * fx
        return a * (1 - fy) + b * fy

    def soft(self, u, v, r=3.0):
        """Slightly blurred sample: rounds the arrises so the relief reads as worn, not crystalline."""
        du, dv = r / self.w, r / self.h
        return (self.sample(u, v) * 2 + self.sample(u + du, v) + self.sample(u - du, v)
                + self.sample(u, v + dv) + self.sample(u, v - dv)) / 6.0


def stone_surface_y(height, side, x, z, u_off):
    u = (x * side + u_off) / STONE_TILE[0]
    v = z / STONE_TILE[1]
    return side * (STONE_FACE_Y + STONE_DEPTH * (height.soft(u, v) - 0.5))


def _stone_rows(cell):
    """Row heights: fine where the stone is in plain view, coarser above the hem (behind leaves)."""
    rows, z = [], 0.0
    while z < WALL_TOP:
        rows.append(z)
        z += cell if z < STONE_TOP + 0.3 else 0.04
    rows.append(WALL_TOP)
    return rows


def build_stone(height, u_offsets=(0.37, 1.61), cell=0.012, ratio=0.15):
    """Both faces of the full-height stone wall as displaced grids with tile-scale UVs, decimated."""
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    nx = int(2 * HALF_X / cell)
    rows = _stone_rows(cell)
    nz = len(rows) - 1
    for side, u_off in zip((1, -1), u_offsets):
        grid = []
        for j in range(nz + 1):
            z = rows[j]
            row = []
            for i in range(nx + 1):
                x = -HALF_X + 2 * HALF_X * i / nx
                row.append(bm.verts.new((x, stone_surface_y(height, side, x, z, u_off), z)))
            grid.append(row)
        for j in range(nz):
            for i in range(nx):
                quad = (grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i])
                f = bm.faces.new(quad if side < 0 else tuple(reversed(quad)))
                for loop in f.loops:
                    co = loop.vert.co
                    loop[uv].uv = ((co.x * side + u_off) / STONE_TILE[0], co.z / STONE_TILE[1])
    # cap the top of the wall between its two faces
    cap = [bm.verts.new((x, y, WALL_TOP - 0.005)) for x, y in
           ((-HALF_X, -STONE_FACE_Y - 0.03), (HALF_X, -STONE_FACE_Y - 0.03), (HALF_X, STONE_FACE_Y + 0.03), (-HALF_X, STONE_FACE_Y + 0.03))]
    f = bm.faces.new(cap)
    for loop in f.loops:
        loop[uv].uv = (loop.vert.co.x / STONE_TILE[0], loop.vert.co.y / STONE_TILE[1])
    me = bpy.data.meshes.new("WallStone2")
    bm.to_mesh(me)
    bm.free()
    for poly in me.polygons:
        poly.use_smooth = True  # flat-shaded decimated triangles read as saw-tooth facets
    me.materials.append(_mat("M_Stone2", (0.45, 0.42, 0.38)))
    ob = _replace("WallStone2", me)
    dec = ob.modifiers.new("Decimate", 'DECIMATE')
    dec.ratio = ratio
    dec.use_collapse_triangulate = True
    far = _replace("WallStone2_LOD1", me.copy())  # beyond ~12 m the relief only needs its silhouette
    dec = far.modifiers.new("Decimate", 'DECIMATE')
    dec.ratio = ratio * 0.18
    dec.use_collapse_triangulate = True
    return ob, far


# ---------------------------------------------------------------------------------------------
# hedge envelope + shell

def hedge_envelope():
    """The existing lumpy hedge volume (WallHedge without its old leaf scatter), with its bottom
    raised to sit on the taller stone band. Returns a BVH-ready list of (verts, tris, vnormals)."""
    src = bpy.data.objects["WallHedge"]
    leaves = src.modifiers.get("Leaves")
    was = leaves.show_viewport if leaves else None
    if leaves:
        leaves.show_viewport = False
    dg = bpy.context.evaluated_depsgraph_get()
    ev = src.evaluated_get(dg)
    me = bpy.data.meshes.new_from_object(ev)
    if leaves:
        leaves.show_viewport = was
    zmin = min(v.co.z for v in me.vertices)
    zmax = max(v.co.z for v in me.vertices)
    for v in me.vertices:
        t = (v.co.z - zmin) / (zmax - zmin)
        v.co.z = HEDGE_BOTTOM + t * (zmax - HEDGE_BOTTOM)
    me.transform(src.matrix_world)
    # finer mesh so the hem and the bulges can be shaped
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=2, use_grid_fill=True)
    bm.normal_update()
    for v in bm.verts:
        p = v.co.copy()
        # bulges and columns: a slow in/out push with a vertical bias (1-2 m wavelength)
        bulge = mathutils.noise.noise(Vector((p.x * 0.8, p.y * 0.8, p.z * 0.45)) + Vector((5.3, 1.1, 9.7)))
        # (fading out towards the hem, so the bottom of the hedge stays tight over the stone)
        v.co = p + v.normal * (0.3 * bulge * min(1.0, max(0.0, (p.z - HEDGE_BOTTOM) / 1.2)))
        # uneven top: the crown rises and dips 0-30 cm along the wall
        if p.z > 6.5:
            crown = 0.25 * mathutils.noise.noise(Vector((p.x * 1.3, p.y, 4.2))) + 0.12 * mathutils.noise.noise(Vector((p.x * 4.1, p.y * 3.0, 9.1)))
            v.co.z += crown * min(1.0, (p.z - 6.5) / 0.5)
        # scalloped hem: the bottom edge dips and rises along the wall
        if p.z < HEDGE_BOTTOM + 0.25:
            dip = 0.12 * mathutils.noise.noise(Vector((p.x * 3.1, 7.3, p.y * 3.1))) + 0.06 * math.sin(p.x * 9.0)
            v.co.z -= max(0.0, dip) * (1.0 - (p.z - HEDGE_BOTTOM) / 0.25)
    bm.to_mesh(me)
    bm.free()
    me.update()
    return me


def build_shell(env):
    """Opaque dark inner volume seen through the gaps between leaves."""
    me = env.copy()
    me.name = "HedgeShell2"
    for v in me.vertices:
        v.co -= v.normal * SHELL_INSET
        v.co.z = max(v.co.z, SHELL_SEAL)
        if v.co.z < STONE_TOP + 0.25:  # tuck the shell's bottom inside the stone faces: no ledge to see
            v.co.y = max(-STONE_FACE_Y + 0.04, min(STONE_FACE_Y - 0.04, v.co.y))
    me.materials.clear()
    me.materials.append(_mat("M_HedgeShell2", (0.03, 0.05, 0.02)))
    return _replace("HedgeShell2", me)


# ---------------------------------------------------------------------------------------------
# leaf cards

def load_rects():
    with open(REPO + r"\client\assets\ring1\foliage\leaf_rects.json") as f:
        return json.load(f)


QUAD_METRES = {"ivy": 0.19, "ivy_old": 0.19, "laurel": 0.22, "beech": 0.24}  # metres per atlas quadrant (leaves 4-8 cm)


class Cards:
    """Accumulates folded single-leaf cards: 6 verts / 4 tris each, stem at the attach point."""

    def __init__(self, name):
        self.name = name
        self.verts, self.faces, self.uvs, self.normals, self.colors = [], [], [], [], []

    def add(self, rect, scale, origin, tip_dir, face_dir, normal, ao, rnd, flag):
        q = QUAD_METRES[rect["species"]]
        w = (rect["u1"] - rect["u0"]) * 2 * q * scale
        h = (rect["v1"] - rect["v0"]) * 2 * q * scale
        y = tip_dir.normalized()
        z = face_dir - y * face_dir.dot(y)
        z.normalize()
        x = y.cross(z)
        fold = w * 0.16
        base = len(self.verts)
        for (lx, ly, lz), (u, v) in (
                ((-w / 2, 0, fold), (rect["u0"], rect["v1"])), ((0, 0, 0), ((rect["u0"] + rect["u1"]) / 2, rect["v1"])),
                ((w / 2, 0, fold), (rect["u1"], rect["v1"])), ((-w / 2, h, fold), (rect["u0"], rect["v0"])),
                ((0, h, 0), ((rect["u0"] + rect["u1"]) / 2, rect["v0"])), ((w / 2, h, fold), (rect["u1"], rect["v0"]))):
            self.verts.append(origin + x * lx + y * ly + z * lz)
            self.uvs.append((u, 1.0 - v))  # glTF/Godot v runs down; Blender UV v runs up
            self.normals.append(normal)
            self.colors.append((ao, rnd, flag, 1.0))
        for a, b, c, d in ((0, 1, 4, 3), (1, 2, 5, 4)):
            self.faces.append((base + a, base + b, base + c, base + d))

    def build(self, mat):
        me = bpy.data.meshes.new(self.name)
        me.from_pydata([tuple(v) for v in self.verts], [], self.faces)
        uv = me.uv_layers.new(name="UVMap")
        col = me.color_attributes.new("Col", 'FLOAT_COLOR', 'POINT')
        for i, c in enumerate(self.colors):
            col.data[i].color = c
        for poly in me.polygons:
            poly.use_smooth = True
            for li in poly.loop_indices:
                uv.data[li].uv = self.uvs[me.loops[li].vertex_index]
        me.normals_split_custom_set_from_vertices([tuple(n) for n in self.normals])
        me.materials.append(mat)
        return _replace(self.name, me)


def _tri_sampler(me, rng, keep):
    me.calc_loop_triangles()
    tris, weights = [], []
    for t in me.loop_triangles:
        c = sum((me.vertices[i].co for i in t.vertices), Vector()) / 3
        if keep(c, t.normal):
            tris.append(t)
            weights.append(t.area)
    total = sum(weights)
    acc, cum = 0.0, []
    for wgt in weights:
        acc += wgt
        cum.append(acc)

    def sample():
        import bisect
        t = tris[min(len(tris) - 1, bisect.bisect_left(cum, rng.random() * total))]
        a, b = rng.random(), rng.random()
        if a + b > 1:
            a, b = 1 - a, 1 - b
        vs = [me.vertices[i] for i in t.vertices]
        p = vs[0].co * (1 - a - b) + vs[1].co * a + vs[2].co * b
        n = (vs[0].normal * (1 - a - b) + vs[1].normal * a + vs[2].normal * b).normalized()
        return p, n
    return sample, total


def scatter_hedge(env, rects, rng, density_low=820.0, density_high=380.0, split_z=3.5):
    """Leaves over the hedge envelope in depth layers; returns (lod0, lod1) Cards."""
    by_species = {}
    for r in rects:
        by_species.setdefault(r["species"], []).append(r)
    mix = [("beech", 0.78), ("ivy", 0.14), ("ivy_old", 0.08)]
    keep = lambda c, n: abs(c.x) < HALF_X - 0.05
    sample, area = _tri_sampler(env, rng, keep)
    lod0, lod1 = Cards("HedgeLeaves2_LOD0"), Cards("HedgeLeaves2_LOD1")
    # sample at the close-range density, then thin out above split_z (out of reach, in the dark)
    # and on the top (only seen from far away)
    up = Vector((0, 0, 1))
    for _ in range(int(area * density_low)):
        p, n = sample()
        high = p.z > split_z
        if high and rng.random() > density_high / density_low:
            continue
        top = n.z > 0.5
        if top and rng.random() > 0.7:
            continue
        # clumps and pockets: density and leaf size follow a slow noise, so the mass bulges and
        # the dark interior shows through in places instead of an even carpet
        clump = 0.5 + 0.5 * mathutils.noise.noise(p * 1.6 + Vector((3.1, 7.7, 1.3)))
        if rng.random() > 0.35 + 0.75 * clump:
            continue
        roll = rng.random()
        species = next(s for s, wgt in _cum(mix) if roll <= wgt)
        rect = rng.choice(by_species[species])
        depth = rng.uniform(-0.075, 0.035) + (clump - 0.5) * 0.05  # bulges stand proud
        sprig = 0.0
        if top or (n.z > 0.15 and p.z > 6.0):
            # a ragged crown: shoots and sprigs standing 5-45 cm proud of the top, so the skyline
            # is broken and leafy instead of a ruler-straight edge
            sprig = rng.random() ** 2.2 * 0.45 * (0.4 + 1.2 * clump)
        origin = p + n * depth + Vector((0, 0, sprig))
        jitter = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1)))
        face = (n * 0.7 + jitter * 0.5 + up * 0.2).normalized()  # mostly outward; some edge-on
        jitter2 = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1)))
        tip = jitter2 - face * jitter2.dot(face) - up * 0.4
        if tip.length < 1e-3:
            tip = n.cross(up)
        scale = _size(rng) * (1.2 if high else 1.0) * (0.85 + 0.3 * clump)
        normal = (n * 0.5 + face * 0.5).normalized()
        ao = min(1.0, 0.35 + 0.65 * (depth + 0.075) / 0.11 + sprig)
        if n.z < -0.4:
            ao *= 0.6  # undersides of the overhang sit in their own shade
        rnd = rng.random()
        lod0.add(rect, scale, origin, tip, face, normal, ao, rnd, 0.0)
        if rng.random() < (0.55 if sprig > 0.05 else 0.3):  # keep the skyline ragged at distance too
            lod1.add(rect, scale * 1.6, origin, tip, face, normal, ao, rnd, 0.0)
    return lod0, lod1


def _size(rng):
    """Log-normal leaf size spread, 0.6-1.4x."""
    return max(0.6, min(1.4, math.exp(rng.gauss(0.0, 0.22))))


def _cum(mix):
    acc = 0.0
    for s, w in mix:
        acc += w
        yield s, acc


# ---------------------------------------------------------------------------------------------
# ivy over the stone

def scatter_ivy(height, rects, rng, u_offsets=(0.37, 1.61), vines_per_face=13):
    """Vines growing down from the hedge over both stone faces, with ivy leaves along them."""
    ivy = [r for r in rects if r["species"] in ("ivy", "ivy_old")]
    leaves = Cards("IvyLeaves2")
    stems = []
    for side, u_off in zip((1, -1), u_offsets):
        for k in range(vines_per_face):
            x = rng.uniform(-HALF_X + 0.15, HALF_X - 0.15)
            z = STONE_TOP + 0.02
            r = rng.random()
            length = rng.uniform(1.4, 1.85) if r < 0.15 else rng.uniform(0.25, 1.1)  # a few runners reach the ground
            heading = rng.uniform(-0.35, 0.35)
            pts = []
            travelled = 0.0
            while travelled < length and z > 0.08:
                y = stone_surface_y(height, side, x, z, u_off) + side * 0.008
                pts.append(Vector((x, y, z)))
                heading = max(-0.8, min(0.8, heading + rng.uniform(-0.25, 0.25)))
                x = max(-HALF_X + 0.05, min(HALF_X - 0.05, x + math.sin(heading) * 0.03))
                z -= math.cos(heading) * 0.03
                travelled += 0.03
            if len(pts) < 3:
                continue
            stems.append(pts)
            # leaves: alternate sides every ~4-6 cm, a little cluster at the top (older growth)
            out = Vector((0, side, 0))
            i = 0
            while i < len(pts) - 1:
                p = pts[i]
                along = (pts[i + 1] - p).normalized()
                lateral = along.cross(out) * (1 if (i // 2) % 2 else -1)
                n_here = 4 if p.z > STONE_TOP - 0.2 else (2 if p.z > STONE_TOP - 0.5 else 1)  # ragged hem
                for _ in range(n_here):
                    rect = rng.choice(ivy)
                    lift = rng.uniform(0.01, 0.05)
                    origin = p + out * lift + lateral * rng.uniform(0.0, 0.03)
                    face = (out * 0.8 + Vector((0, 0, 0.45)) + lateral * rng.uniform(-0.3, 0.3)).normalized()
                    tip = (lateral * rng.uniform(0.2, 0.8) + Vector((0, 0, -0.5)) + out * 0.2)
                    scale = _size(rng) * (0.75 + 0.35 * (p.z / STONE_TOP))  # young growth at the tips is small
                    ao = 0.45 + 0.55 * min(1.0, lift / 0.05)
                    normal = (out * 0.6 + face * 0.4).normalized()
                    leaves.add(rect, scale, origin, tip, face, normal, ao, rng.random(), 1.0)
                i += rng.choice((1, 2))
    return leaves, stems


def scatter_hem(height, rects, rng, cards, stems, u_offsets=(0.37, 1.61)):
    """Breaks the hedge's bottom edge: leafy tongues hanging 0.3-0.8 m over the stone, foliage
    spilling round the pillar corners, and fallen leaves along the base of the wall."""
    by = {}
    for r in rects:
        by.setdefault(r["species"], []).append(r)
    hedge_mix = [("beech", 0.7), ("ivy", 0.2), ("ivy_old", 0.1)]
    up = Vector((0, 0, 1))
    for side, u_off in zip((1, -1), u_offsets):
        out = Vector((0, side, 0))
        x = -HALF_X + rng.uniform(0.1, 0.5)
        while x < HALF_X - 0.15:
            width = rng.uniform(0.15, 0.35)
            length = rng.uniform(0.3, 0.8)
            top = HEDGE_BOTTOM + 0.15 + (rng.uniform(-0.25, 0.12) if rng.random() < 0.3 else 0.0)
            n = int(width * length * 900 * 0.6)
            for _ in range(n):
                t = rng.random() ** 0.7  # denser near the top
                z = top - t * length
                w = width * (1.0 - 0.75 * t) * 0.5
                lx = x + rng.uniform(-w, w)
                if abs(lx) > HALF_X - 0.05 or z < 0.1:
                    continue
                y = stone_surface_y(height, side, lx, min(z, STONE_TOP), u_off)
                lift = rng.uniform(0.02, 0.12) * (1.0 - 0.6 * t)
                origin = Vector((lx, y, z)) + out * lift
                roll = rng.random()
                species = next(s for s, wgt in _cum(hedge_mix) if roll <= wgt)
                jitter = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1)))
                face = (out * 0.75 + jitter * 0.45 + up * 0.25).normalized()
                tip = jitter - face * jitter.dot(face) - up * 0.6
                ao = 0.35 + 0.65 * min(1.0, lift / 0.1)
                cards.add(rng.choice(by[species]), _size(rng), origin, tip, face,
                          (out * 0.7 + face * 0.3).normalized(), ao, rng.random(), 0.0)
            # a bare stem or two showing in the tongue
            pts = []
            for k in range(int(length / 0.03)):
                z = top - k * 0.03
                pts.append(Vector((x + rng.uniform(-0.01, 0.01),
                                   stone_surface_y(height, side, x, min(z, STONE_TOP), u_off) + side * 0.012, z)))
            if len(pts) > 3:
                stems.append(pts)
            x += width + rng.uniform(0.45, 1.2)
        # spill round the pillar corners (pillar faces sit at |y| = 0.5, from |x| = 1.5)
        for end in (-1, 1):
            strip = rng.uniform(0.07, 0.3) if rng.random() < 0.7 else rng.uniform(0.04, 0.08)
            low = HEDGE_BOTTOM - rng.uniform(0.0, 0.6)
            n = int(strip * (7.0 - low) * 700)
            for _ in range(n):
                px = end * (1.5 + rng.random() ** 1.5 * strip)
                pz = rng.uniform(low, 7.0)
                origin = Vector((px, side * (0.505 + rng.uniform(0.0, 0.06)), pz))
                jitter = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1)))
                face = (out * 0.75 + jitter * 0.45 + up * 0.2).normalized()
                tip = jitter - face * jitter.dot(face) - up * 0.5
                roll = rng.random()
                species = next(s for s, wgt in _cum(hedge_mix) if roll <= wgt)
                cards.add(rng.choice(by[species]), _size(rng), origin, tip, face,
                          (out * 0.7 + face * 0.3).normalized(), rng.uniform(0.5, 1.0), rng.random(), 0.0)
        # fallen leaves along the base: dry, brown, lying almost flat
        for _ in range(rng.randint(14, 30)):
            dist = 0.33 + abs(rng.gauss(0.0, 0.18))
            origin = Vector((rng.uniform(-HALF_X, HALF_X), side * dist, 0.004))
            face = (up + Vector((rng.uniform(-0.3, 0.3), rng.uniform(-0.3, 0.3), 0))).normalized()
            tip = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), 0))
            species = rng.choice(("beech", "ivy_old"))
            cards.add(rng.choice(by[species]), _size(rng) * 0.9, origin, tip, face, up, 0.6,
                      rng.uniform(0.0, 0.07), 0.0)


def build_stems(stems, radius=0.0055):
    bm = bmesh.new()
    for pts in stems:
        rings = []
        for i, p in enumerate(pts):
            d = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
            a = d.orthogonal().normalized()
            b = d.cross(a)
            r = radius * (1.0 - 0.6 * i / len(pts))
            rings.append([bm.verts.new(p + (a * math.cos(t) + b * math.sin(t)) * r) for t in (0, 2.094, 4.189)])
        for r0, r1 in zip(rings, rings[1:]):
            for k in range(3):
                bm.faces.new((r0[k], r0[(k + 1) % 3], r1[(k + 1) % 3], r1[k]))
    me = bpy.data.meshes.new("IvyStems2")
    bm.to_mesh(me)
    bm.free()
    for poly in me.polygons:
        poly.use_smooth = True
    me.materials.append(_mat("M_IvyStem2", (0.12, 0.08, 0.05)))
    return _replace("IvyStems2", me)


# ---------------------------------------------------------------------------------------------

def build_all(dl_dir, seed=11, u_offsets=(0.37, 1.61)):
    bpy.context.window.scene = bpy.data.scenes["Ring1Kit"]  # modifiers evaluate in the active scene only
    rng = random.Random(seed)
    height = Height(dl_dir + r"\rough_block_wall\rough_block_wall_disp_2k.png")
    stone, stone_far = build_stone(height, u_offsets)
    env = hedge_envelope()
    rects = load_rects()
    leaf_mat = _mat("M_Leaf2", (0.2, 0.35, 0.15))
    lod0, lod1 = scatter_hedge(env, rects, rng)
    ivy, stems = scatter_ivy(height, rects, rng, u_offsets)
    scatter_hem(height, rects, rng, ivy, stems, u_offsets)
    objs = [stone, stone_far, lod0.build(leaf_mat), lod1.build(leaf_mat), ivy.build(leaf_mat), build_stems(stems)]
    bpy.data.meshes.remove(env)
    return {o.name: len(o.data.polygons) for o in objs}


def export(path):
    """Export Kit_Wall2 (modifiers applied, custom normals and COLOR_0) as one glb."""
    prev = bpy.context.window.scene
    tmp = bpy.data.scenes.new("Wall2Tmp")
    for ob in _coll().objects:
        tmp.collection.objects.link(ob)
    bpy.context.window.scene = tmp
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_active_scene=True, export_apply=True,
                              export_yup=True, export_vertex_color='ACTIVE', export_normals=True)
    bpy.context.window.scene = prev
    bpy.data.scenes.remove(tmp)


# Variants so neighbouring walls never repeat: different stretches of the photoscan per face and
# different foliage seeds (look-dev picks one per wall by hash).
VARIANTS = {"a": (11, (0.37, 1.61)), "b": (23, (0.91, 2.27)), "c": (37, (1.53, 0.12))}


def build_variants(dl_dir, out_dir):
    out = {}
    for key, (seed, offs) in VARIANTS.items():
        out[key] = build_all(dl_dir, seed, offs)
        export(out_dir + rf"\wall2_{key}.glb")
    return out


# ---------------------------------------------------------------------------------------------
# Pillar v2 (2026-10-09): the old pillars were smooth 8.2 m stone posts with flat caps that stood
# above the hedges and read as hard cut-out silhouettes against the sky. Now: a stone base like the
# walls, then hedge all the way up with a ragged leafy crown just above the wall hedges.

PILLAR_HALF = 0.5
PILLAR_TOP = 7.35


def build_pillar_stone(height, cell=0.014, ratio=0.15):
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    n = int(2 * PILLAR_HALF / cell)
    rows = _stone_rows(cell)
    nz = len(rows) - 1
    for k in range(4):
        rot = Matrix.Rotation(k * math.pi / 2, 3, 'Z')
        u_off = 0.23 + 0.71 * k
        grid = []
        for j in range(nz + 1):
            z = rows[j]
            row = []
            for i in range(n + 1):
                x = -PILLAR_HALF + 2 * PILLAR_HALF * i / n
                # corners pull in a little so the four faces meet as a worn arris, not a seam
                edge = min(1.0, (PILLAR_HALF - abs(x)) / 0.04)
                d = (STONE_FACE_Y - 0.3 + PILLAR_HALF) + STONE_DEPTH * (height.soft((x + u_off) / STONE_TILE[0], z / STONE_TILE[1]) - 0.5) * edge
                row.append(bm.verts.new(rot @ Vector((x, d, z))))
            grid.append(row)
        for j in range(nz):
            for i in range(n):
                quad = (grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i])
                f = bm.faces.new(tuple(reversed(quad)))
                for loop in f.loops:
                    lc = rot.inverted() @ loop.vert.co
                    loop[uv].uv = ((lc.x + u_off) / STONE_TILE[0], lc.z / STONE_TILE[1])
    cap = [bm.verts.new((x, y, WALL_TOP + 0.05)) for x, y in ((-0.5, -0.5), (0.5, -0.5), (0.5, 0.5), (-0.5, 0.5))]
    bm.faces.new(cap)
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=0.004)
    me = bpy.data.meshes.new("PillarStone2")
    bm.to_mesh(me)
    bm.free()
    for poly in me.polygons:
        poly.use_smooth = True
    me.materials.append(_mat("M_Stone2", (0.45, 0.42, 0.38)))
    ob = _replace("PillarStone2", me)
    dec = ob.modifiers.new("Decimate", 'DECIMATE')
    dec.ratio = ratio
    dec.use_collapse_triangulate = True
    return ob


def pillar_envelope():
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * 1.12, v.co.y * 1.12, HEDGE_BOTTOM + (v.co.z + 0.5) * (PILLAR_TOP - HEDGE_BOTTOM)))
    bmesh.ops.bevel(bm, geom=bm.edges[:], offset=0.18, segments=3, affect='EDGES')
    bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=3, use_grid_fill=True)
    bm.normal_update()
    for v in bm.verts:
        p = v.co.copy()
        lump = mathutils.noise.noise(p * 1.7 + Vector((2.2, 8.1, 4.4)))
        crown = 0.25 * max(0.0, mathutils.noise.noise(p * 3.1)) if p.z > PILLAR_TOP - 0.3 else 0.0
        v.co = p + v.normal * (0.07 * lump * min(1.0, (p.z - HEDGE_BOTTOM) / 0.8)) + Vector((0, 0, crown))
    me = bpy.data.meshes.new("PillarEnv")
    bm.to_mesh(me)
    bm.free()
    return me


def build_pillar(dl_dir, out_path, seed=5):
    global COLL
    bpy.context.window.scene = bpy.data.scenes["Ring1Kit"]
    prev_coll = COLL
    COLL = "Kit_Pillar2"
    try:
        rng = random.Random(seed)
        height = Height(dl_dir + r"\rough_block_wall\rough_block_wall_disp_2k.png")
        stone = build_pillar_stone(height)
        env = pillar_envelope()
        rects = load_rects()
        leaf_mat = _mat("M_Leaf2", (0.2, 0.35, 0.15))
        lod0, lod1 = scatter_hedge(env, rects, rng)
        objs = [stone, lod0.build(leaf_mat), lod1.build(leaf_mat)]
        bpy.data.meshes.remove(env)
        export(out_path)
        return {o.name: len(o.data.polygons) for o in objs}
    finally:
        COLL = prev_coll
