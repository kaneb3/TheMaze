shader_type spatial;
// Contact shading overlay (material_overlay on the first-person hand): blends the glove towards
// deep shadow where it wraps the lantern hoop's grip, a capsule given in the mesh's own
// space. Stands in for baked contact occlusion so the inside of the fist never catches light.
render_mode blend_mix, unshaded, depth_draw_never, cull_back, fog_disabled;  // blend_mul isn't applied to overlays

uniform vec3 cap_a;
uniform vec3 cap_b;
uniform float cap_r = 0.006;
uniform float reach = 0.03;  // distance over which the shading fades out (m)
uniform float floor_value = 0.18;  // remaining brightness where the glove touches the grip
uniform vec3 shadow_color = vec3(0.018, 0.011, 0.007);

varying float shade;

void vertex() {
	vec3 ab = cap_b - cap_a;
	float t = clamp(dot(VERTEX - cap_a, ab) / dot(ab, ab), 0.0, 1.0);
	vec3 to_axis = (cap_a + ab * t) - VERTEX;
	float d = length(to_axis) - cap_r;
	// only surfaces that face the grip (the inside of the curled fingers and palm) are occluded
	float facing = clamp(dot(NORMAL, normalize(to_axis)) * 1.2 + 0.85, 0.0, 1.0);  // rims of the cavity mostly occluded too
	float occ = (1.0 - smoothstep(0.0, reach, d)) * facing;
	shade = mix(1.0, floor_value, occ);
}

void fragment() {
	ALBEDO = shadow_color;
	ALPHA = 1.0 - shade;
}
