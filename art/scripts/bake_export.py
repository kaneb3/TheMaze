"""Bake procedural Blender materials to textures and export game-ready glTF for Godot.

Run inside Blender (e.g. via the MCP connection):
    g = {}; exec(open(r"<repo>/art/scripts/bake_export.py").read(), g); g["export_asset"](...)

Each asset collection is evaluated (modifiers applied, curves converted), joined, UV-unwrapped and
baked (albedo, roughness+metallic packed as ORM, tangent normal) with Cycles. Parts listed in
`special` keep simple constant materials instead (glass, flames, emissive bits). Output:
client/assets/ring1/<name>.glb with textures embedded.
"""

import math
import os

import bmesh
import bpy
import numpy as np

REPO = r"C:\Users\kaneb\Documents\the-maze"
OUT_DIR = os.path.join(REPO, "client", "assets", "ring1")
BAKE_DIR = os.path.join(REPO, "art", "bake")


# ----------------------------------------------------------------------------------------------
# scene plumbing

def _bake_scene():
    sc = bpy.data.scenes.get("BakeTmp") or bpy.data.scenes.new("BakeTmp")
    sc.render.engine = 'CYCLES'
    sc.cycles.samples = 16
    sc.cycles.use_denoising = False
    sc.render.bake.margin = 8
    try:
        prefs = bpy.context.preferences.addons['cycles'].preferences
        for kind in ('OPTIX', 'CUDA', 'HIP', 'ONEAPI', 'METAL'):
            try:
                prefs.compute_device_type = kind
                prefs.get_devices()
                if any(d.type == kind for d in prefs.devices):
                    for d in prefs.devices:
                        d.use = True
                    sc.cycles.device = 'GPU'
                    break
            except TypeError:
                continue
    except KeyError:
        pass
    return sc


def _clear_scene(sc):
    for c in list(sc.collection.children):
        sc.collection.children.unlink(c)
    for ob in list(sc.collection.objects):
        sc.collection.objects.unlink(ob)


def _link(sc, ob):
    sc.collection.objects.link(ob)
    return ob


# ----------------------------------------------------------------------------------------------
# geometry

def _eval_mesh(ob, dg):
    ev = ob.evaluated_get(dg)
    me = bpy.data.meshes.new_from_object(ev, preserve_all_data_layers=False, depsgraph=dg)
    me.transform(ob.matrix_world)
    if not me.materials and ob.material_slots:
        for s in ob.material_slots:
            me.materials.append(s.material)
    return me


def _combine(name, meshes):
    bm = bmesh.new()
    mats = []
    for me in meshes:
        offset = len(mats)
        mats += list(me.materials)
        tmp = bmesh.new()
        tmp.from_mesh(me)
        for f in tmp.faces:
            f.material_index += offset
        tmp.to_mesh(me)
        tmp.free()
        bm.from_mesh(me)
    out = bpy.data.meshes.new(name)
    bm.to_mesh(out)
    bm.free()
    for m in mats:
        out.materials.append(m)
    return out


def _unwrap(ob):
    vl = bpy.context.view_layer
    for o in vl.objects:
        o.select_set(False)
    ob.select_set(True)
    vl.objects.active = ob
    bpy.ops.object.mode_set(mode='EDIT')
    try:
        with bpy.context.temp_override(edit_object=ob, active_object=ob, object=ob):
            bpy.ops.mesh.select_all(action='SELECT')
            bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.004)
    finally:
        bpy.ops.object.mode_set(mode='OBJECT')


# ----------------------------------------------------------------------------------------------
# baking

def _unique_mats(ob):
    seen = []
    for m in ob.data.materials:
        if m and m not in seen:
            seen.append(m)
    return seen


def _bake(ob, img, bake_type, **kw):
    added = []
    for m in _unique_mats(ob):
        n = m.node_tree.nodes.new("ShaderNodeTexImage")
        n.image = img
        m.node_tree.nodes.active = n
        added.append((m, n))
    try:
        with bpy.context.temp_override(active_object=ob, object=ob, selected_objects=[ob], selected_editable_objects=[ob]):
            bpy.ops.object.bake(type=bake_type, use_clear=True, margin=8, **kw)
    finally:
        for m, n in added:
            m.node_tree.nodes.remove(n)


def _bake_metallic(ob, img):
    """Bake the Metallic input by temporarily routing it into an Emission shader."""
    saved = []
    for m in _unique_mats(ob):
        nt = m.node_tree
        out = next(n for n in nt.nodes if n.type == 'OUTPUT_MATERIAL' and n.is_active_output)
        bsdf = next((n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED'), None)
        orig = out.inputs["Surface"].links[0].from_socket if out.inputs["Surface"].is_linked else None
        em = nt.nodes.new("ShaderNodeEmission")
        if bsdf is not None and bsdf.inputs["Metallic"].is_linked:
            nt.links.new(bsdf.inputs["Metallic"].links[0].from_socket, em.inputs["Color"])
        else:
            v = bsdf.inputs["Metallic"].default_value if bsdf is not None else 0.0
            em.inputs["Color"].default_value = (v, v, v, 1)
        nt.links.new(em.outputs[0], out.inputs["Surface"])
        saved.append((m, out, orig, em))
    try:
        _bake(ob, img, 'EMIT')
    finally:
        for m, out, orig, em in saved:
            nt = m.node_tree
            if orig is not None:
                nt.links.new(orig, out.inputs["Surface"])
            nt.nodes.remove(em)


def _image(name, size, non_color):
    img = bpy.data.images.get(name)
    if img:
        bpy.data.images.remove(img)
    img = bpy.data.images.new(name, size, size, alpha=False)
    img.colorspace_settings.name = 'Non-Color' if non_color else 'sRGB'
    return img


def _save(img, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.filepath_raw = path
    img.file_format = 'PNG'
    img.save()


def _baked_material(name, albedo, orm, normal):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    b = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(b.outputs[0], out.inputs[0])
    ta = nt.nodes.new("ShaderNodeTexImage"); ta.image = albedo
    to = nt.nodes.new("ShaderNodeTexImage"); to.image = orm
    tn = nt.nodes.new("ShaderNodeTexImage"); tn.image = normal
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nt.links.new(ta.outputs["Color"], b.inputs["Base Color"])
    nt.links.new(to.outputs["Color"], sep.inputs[0])
    nt.links.new(sep.outputs[1], b.inputs["Roughness"])
    nt.links.new(sep.outputs[2], b.inputs["Metallic"])
    nt.links.new(tn.outputs["Color"], nm.inputs["Color"])
    nt.links.new(nm.outputs[0], b.inputs["Normal"])
    return m


def constant_material(name, color=(0.5, 0.5, 0.5), rough=0.8, metal=0.0, alpha=1.0, emission=None, strength=0.0):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    b = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(b.outputs[0], out.inputs[0])
    b.inputs["Base Color"].default_value = (*color, 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    b.inputs["Alpha"].default_value = alpha
    if emission is not None:
        b.inputs["Emission Color"].default_value = (*emission, 1)
        b.inputs["Emission Strength"].default_value = strength
    m.surface_render_method = 'BLENDED' if alpha < 1.0 else 'DITHERED'
    return m


def bake_textures(ob, name, size):
    """Bake albedo / ORM / normal for every material on `ob` into one texture set."""
    _unwrap(ob)
    albedo = _image(f"{name}_albedo", size, False)
    rough = _image(f"{name}_rough_tmp", size, True)
    metal = _image(f"{name}_metal_tmp", size, True)
    normal = _image(f"{name}_normal", size, True)
    _bake(ob, albedo, 'DIFFUSE', pass_filter={'COLOR'})
    _bake(ob, rough, 'ROUGHNESS')
    _bake_metallic(ob, metal)
    _bake(ob, normal, 'NORMAL', normal_space='TANGENT')
    r = np.array(rough.pixels[:], dtype=np.float32).reshape(-1, 4)
    mt = np.array(metal.pixels[:], dtype=np.float32).reshape(-1, 4)
    orm_px = np.ones_like(r)
    orm_px[:, 1] = r[:, 0]
    orm_px[:, 2] = mt[:, 0]
    orm = _image(f"{name}_orm", size, True)
    orm.pixels[:] = orm_px.ravel()
    for img, suffix in ((albedo, "albedo"), (orm, "orm"), (normal, "normal")):
        _save(img, os.path.join(BAKE_DIR, f"{name}_{suffix}.png"))
    bpy.data.images.remove(rough)
    bpy.data.images.remove(metal)
    return _baked_material(f"{name}_Baked", albedo, orm, normal)


# ----------------------------------------------------------------------------------------------
# public entry point

def export_asset(name, collection, size=1024, special=None, skip=(), extra_objects=None):
    """Bake and export one asset collection.

    special: {object-name-prefix: (export-node-name, material)} parts kept separate with constant materials.
    skip: object-name prefixes to leave out entirely (lights, instances, helpers).
    extra_objects: list of (export-node-name, mesh) already-evaluated meshes to add as separate nodes.
    """
    special = special or {}
    window = bpy.context.window
    prev_scene = window.scene
    sc = _bake_scene()
    _clear_scene(sc)
    src = bpy.data.collections[collection]
    sc.collection.children.link(src)
    window.scene = sc
    created = []
    try:
        dg = bpy.context.evaluated_depsgraph_get()
        baked_parts, special_parts = [], {}
        for ob in src.all_objects:
            if ob.type not in {'MESH', 'CURVE'} or ob.name.startswith(tuple(skip)):
                continue
            me = _eval_mesh(ob, dg)
            hit = next((k for k in special if ob.name.startswith(k)), None)
            if hit:
                special_parts.setdefault(hit, []).append(me)
            else:
                baked_parts.append(me)
        sc.collection.children.unlink(src)

        export_objs = []
        if baked_parts:
            me = _combine(f"{name}_mesh", baked_parts)
            ob = _link(sc, bpy.data.objects.new(f"{name}", me))
            created.append(ob)
            mat = bake_textures(ob, name, size)
            me.materials.clear()
            me.materials.append(mat)
            export_objs.append(ob)
        for key, meshes in special_parts.items():
            node_name, mat = special[key]
            me = _combine(f"{name}_{node_name}", meshes)
            me.materials.clear()
            me.materials.append(mat)
            ob = _link(sc, bpy.data.objects.new(node_name, me))
            created.append(ob)
            export_objs.append(ob)
        for node_name, me in (extra_objects or []):
            ob = _link(sc, bpy.data.objects.new(node_name, me))
            created.append(ob)
            export_objs.append(ob)

        os.makedirs(OUT_DIR, exist_ok=True)
        path = os.path.join(OUT_DIR, f"{name}.glb")
        # The bake scene now holds exactly the export objects (the source collection was unlinked),
        # so export that whole scene rather than relying on selection state.
        if True:
            bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=False, use_active_scene=True,
                                      use_visible=False, export_apply=True,
                                      export_yup=True, export_materials='EXPORT', export_image_format='AUTO',
                                      export_lights=False, export_cameras=False)
        faces = sum(len(o.data.polygons) for o in export_objs)
        return {"glb": path, "bytes": os.path.getsize(path), "nodes": [o.name for o in export_objs], "faces": faces}
    finally:
        window.scene = prev_scene
        for ob in created:
            me = ob.data
            bpy.data.objects.remove(ob, do_unlink=True)
            if me.users == 0:
                bpy.data.meshes.remove(me)
