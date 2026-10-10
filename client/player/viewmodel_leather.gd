class_name ViewmodelLeather
extends RefCounted
## Swaps a baked viewmodel part's StandardMaterial3D (from bake_export.py) for viewmodel_leather.gdshader
## with the same textures. depth_scale < 1 for parts held out in front of the camera (see the shader).

const SHADER := "res://client/player/viewmodel_leather.gdshader"


static func apply(mi: MeshInstance3D, depth_scale := 1.0) -> void:
	var baked := mi.mesh.surface_get_material(0) as StandardMaterial3D
	if baked == null or baked.albedo_texture == null:
		return
	var m := ShaderMaterial.new()
	m.shader = load(SHADER)
	m.set_shader_parameter("albedo_tex", baked.albedo_texture)
	m.set_shader_parameter("orm_tex", baked.roughness_texture)
	m.set_shader_parameter("normal_tex", baked.normal_texture)
	m.set_shader_parameter("depth_scale", depth_scale)
	mi.material_override = m
