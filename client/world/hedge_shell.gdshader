shader_type spatial;
// The opaque mass inside the hedge, seen through gaps between the leaf cards (and alone beyond
// the leaves' range). It is painted with the same scanned leaves, tiled in two offset layers and
// kept dark, so a gap shows deeper leaves in shadow - never a bare surface. Matte, sky-occluded.
render_mode diffuse_lambert, specular_disabled;

uniform sampler2D leaf_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tile_m = 0.5;  // metres per atlas repeat (leaves ~4-8 cm, like the cards)
uniform vec3 deep_color : source_color = vec3(0.012, 0.018, 0.014);
uniform float leaf_value = 0.32;  // how bright the inner leaves get (they sit in the hedge's shade)
varying vec3 v_wpos;
varying vec3 v_wnrm;
varying float v_sky;

uniform float sky_occl_strength = 1.0;
uniform float sky_floor = 0.15;
float sky_visibility(float h, float up) {
	float d = max(7.0 - h, 0.0);
	float side = 1.0 - d * inversesqrt(d * d + 3.4 * 3.4);
	return mix(sky_floor, 1.0, mix(side, 1.0, smoothstep(0.2, 0.9, up)));
}

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_sky = sky_visibility(VERTEX.y, NORMAL.y);
}

vec4 leaves(vec2 uv) {
	vec4 a = texture(leaf_albedo, uv);
	vec4 b = texture(leaf_albedo, uv * 1.37 + vec2(0.31, 0.57));
	return a.a >= b.a ? a : b;
}

void fragment() {
	// project from the dominant axis of the surface (walls face X or Z; tops face Y)
	vec3 an = abs(v_wnrm);
	vec2 uv = an.y > max(an.x, an.z) ? v_wpos.xz : (an.x > an.z ? v_wpos.zy : v_wpos.xy);
	vec4 l = leaves(uv / tile_m * vec2(1.0, -1.0));
	float cover = smoothstep(0.3, 0.7, l.a);
	ALBEDO = mix(deep_color, l.rgb * leaf_value * vec3(0.75, 0.9, 0.8), cover);
	ROUGHNESS = 1.0;
	AO = mix(1.0, v_sky, sky_occl_strength) * mix(0.5, 1.0, cover);
}
