class_name WallMaterials
extends RefCounted
## Materials and render settings for the Ring 1 wall (client/assets/ring1/wall2.glb, built by
## art/scripts/wall_v2.py). Shared resources so Godot auto-instances every wall segment.
##
## - WallStone2: stone_wall.gdshader (CC0 photoscan + moss/grime/leaks/lichen); PillarStone: same,
##   box-mapped
## - HedgeLeaves2_LOD0 / _LOD1, IvyLeaves2: foliage.gdshader; LOD0 within FOLIAGE_LOD_M, LOD1 beyond
## - HedgeShell2: the dark mass inside the hedge; IvyStems2: woody stems
## Only near foliage casts lantern shadows (an omni shadow renders every caster 6 times).

const FOLIAGE_LOD_M := 11.0
const STONE_LOD_M := 12.0
const FOLIAGE_END_M := 26.0  # beyond this the fog leaves only the dark hedge mass
const LOD_MARGIN := 1.5
const DIR := "res://client/assets/ring1/"

static var _stone: ShaderMaterial
static var _pillar: ShaderMaterial
static var _leaves: ShaderMaterial
static var _shell: StandardMaterial3D
static var _stems: StandardMaterial3D
static var _floor: ShaderMaterial
static var _macro: NoiseTexture2D


static func apply(wall: Node) -> void:
	_ensure()
	for node in wall.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var n := String(mi.name)
		if n.begins_with("Hedge") or n.begins_with("Ivy"):
			mi.layers = WallMarkings.FOLIAGE_LAYER  # decals skip foliage
		if n.begins_with("WallStone2_LOD1"):
			mi.material_override = _stone
			mi.visibility_range_begin = STONE_LOD_M
			mi.visibility_range_begin_margin = LOD_MARGIN
		elif n.begins_with("WallStone2"):
			mi.material_override = _stone
			mi.visibility_range_end = STONE_LOD_M
			mi.visibility_range_end_margin = LOD_MARGIN
		elif n == "pillar" or n.begins_with("PillarStone"):
			mi.material_override = _pillar
		elif n.begins_with("HedgeLeaves2_LOD0"):
			mi.material_override = _leaves
			mi.visibility_range_end = FOLIAGE_LOD_M
			mi.visibility_range_end_margin = LOD_MARGIN
			# the hedge mass self-shadows through its depth AO; the lantern's shadow pass keeps
			# the ivy and tongues on the stone, where leaf shadows really read
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		elif n.begins_with("HedgeLeaves2_LOD1"):
			mi.material_override = _leaves
			mi.visibility_range_begin = FOLIAGE_LOD_M
			mi.visibility_range_begin_margin = LOD_MARGIN
			mi.visibility_range_end = FOLIAGE_END_M
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		elif n.begins_with("IvyLeaves2"):
			mi.material_override = _leaves
			mi.visibility_range_end = FOLIAGE_LOD_M + 6.0
		elif n.begins_with("HedgeShell2"):
			mi.material_override = _shell
		elif n.begins_with("IvyStems2"):
			mi.material_override = _stems
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.visibility_range_end = FOLIAGE_LOD_M + 6.0


static func _ensure() -> void:
	if _stone != null:
		return
	var noise := FastNoiseLite.new()
	noise.frequency = 0.012
	noise.fractal_octaves = 4
	var macro := NoiseTexture2D.new()
	macro.width = 512
	macro.height = 512
	macro.seamless = true
	macro.noise = noise
	_macro = macro

	_stone = ShaderMaterial.new()
	_stone.shader = load("res://client/world/stone_wall.gdshader")
	_stone.set_shader_parameter("albedo_tex", load(DIR + "stone/rough_block_wall_diff_2k.jpg"))
	_stone.set_shader_parameter("normal_tex", load(DIR + "stone/rough_block_wall_nor_gl_2k.png"))
	_stone.set_shader_parameter("arm_tex", load(DIR + "stone/rough_block_wall_arm_2k.jpg"))
	_stone.set_shader_parameter("height_tex", load(DIR + "stone/rough_block_wall_disp_2k.png"))
	_stone.set_shader_parameter("moss_tex", load(DIR + "stone/moss_color.jpg"))
	_stone.set_shader_parameter("moss_normal_tex", load(DIR + "stone/moss_normal.jpg"))
	_stone.set_shader_parameter("leak_tex", load(DIR + "stone/leak_mask.png"))
	_stone.set_shader_parameter("macro_noise", macro)

	_pillar = _stone.duplicate() as ShaderMaterial
	_pillar.set_shader_parameter("box_map", true)
	_pillar.set_shader_parameter("stone_top", 7.3)

	_leaves = ShaderMaterial.new()
	_leaves.shader = load("res://client/world/foliage.gdshader")
	_leaves.set_shader_parameter("leaf_albedo", load(DIR + "foliage/leaf_albedo.png"))
	_leaves.set_shader_parameter("leaf_normal", load(DIR + "foliage/leaf_normal.png"))
	_leaves.set_shader_parameter("leaf_rough", load(DIR + "foliage/leaf_rough.png"))

	_shell = StandardMaterial3D.new()
	_shell.albedo_color = Color(0.022, 0.034, 0.016)
	_shell.roughness = 1.0
	_shell.metallic_specular = 0.0  # seen at grazing angles from below; must never sheen

	_stems = StandardMaterial3D.new()
	_stems.albedo_color = Color(0.13, 0.09, 0.06)
	_stems.roughness = 0.8


## The maze floor (stone_floor.gdshader): CC0 photoscan setts in world space with grime, moss in
## the joints and damp patches.
static func floor_material() -> ShaderMaterial:
	_ensure()
	if _floor == null:
		_floor = ShaderMaterial.new()
		_floor.shader = load("res://client/world/stone_floor.gdshader")
		_floor.set_shader_parameter("albedo_tex", load(DIR + "stone/cobblestone_pavement_diff_2k.jpg"))
		_floor.set_shader_parameter("normal_tex", load(DIR + "stone/cobblestone_pavement_nor_gl_2k.png"))
		_floor.set_shader_parameter("arm_tex", load(DIR + "stone/cobblestone_pavement_arm_2k.jpg"))
		_floor.set_shader_parameter("height_tex", load(DIR + "stone/cobblestone_pavement_disp_2k.png"))
		_floor.set_shader_parameter("moss_tex", load(DIR + "stone/moss_color.jpg"))
		_floor.set_shader_parameter("macro_noise", _macro)
	return _floor
