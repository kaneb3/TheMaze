class_name LanternLighting
## Lighting rig for a lantern whose light source sits inside its own model.
##
## The world light ignores the lantern's meshes (render layer 2), so the lantern's frame never
## throws giant self-shadows across the maze and its glass isn't blown out. A tiny, shadowless
## fill light lights only the lantern model so it still glows convincingly.

const LANTERN_LAYER := 1 << 1  # render layer 2
const ALL_LAYERS := (1 << 20) - 1


static func rig(lantern: Node3D, world_light: OmniLight3D, flame_local: Vector3, fill_energy := 0.35) -> OmniLight3D:
	for node in lantern.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		mi.layers = LANTERN_LAYER
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world_light.light_cull_mask = ALL_LAYERS & ~LANTERN_LAYER
	world_light.shadow_caster_mask = ALL_LAYERS & ~LANTERN_LAYER

	var fill := OmniLight3D.new()
	fill.name = "LanternFill"
	fill.light_color = world_light.light_color
	fill.light_energy = fill_energy
	fill.omni_range = 0.6
	fill.shadow_enabled = false
	fill.light_volumetric_fog_energy = 0.0
	fill.light_cull_mask = LANTERN_LAYER
	fill.position = flame_local
	lantern.add_child(fill)
	return fill
