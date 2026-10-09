shader_type spatial;
// The dark mass inside the hedge, seen through gaps between leaves (and alone beyond the leaves'
// range): mottled like deep foliage, never a smooth slab; matte; sky-occluded like the rest.
render_mode diffuse_lambert, specular_disabled;

uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
varying vec3 v_wpos;
varying float v_sky;

// Analytic sky occlusion in a 7 m deep, 3.4 m wide corridor: a point at height h sees the share
// 1 - d/sqrt(d^2 + w^2) of the sky (d = 7 - h). Tops see it all. Stands in for GI's sky shadowing.
uniform float sky_occl_strength = 1.0;
uniform float sky_floor = 0.15;  // light bounced off the opposite wall never quite lets it reach 0
float sky_visibility(float h, float up) {
	float d = max(7.0 - h, 0.0);
	float side = 1.0 - d * inversesqrt(d * d + 3.4 * 3.4);
	return mix(sky_floor, 1.0, mix(side, 1.0, smoothstep(0.2, 0.9, up)));
}

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_sky = sky_visibility(VERTEX.y, NORMAL.y);
}

void fragment() {
	vec2 p = v_wpos.xz + v_wpos.y * vec2(0.7, -0.4);
	float n = texture(noise_tex, p * 0.9).r * 0.6 + texture(noise_tex, p * 4.3 + 0.3).r * 0.4;
	ALBEDO = mix(vec3(0.018, 0.028, 0.022), vec3(0.06, 0.085, 0.06), n);
	ROUGHNESS = 1.0;
	AO = mix(1.0, v_sky, sky_occl_strength);
	vec2 e = vec2(0.02, 0.0);
	float nx = texture(noise_tex, (p + e.xy) * 4.3).r - texture(noise_tex, (p - e.xy) * 4.3).r;
	float ny = texture(noise_tex, (p + e.yx) * 4.3).r - texture(noise_tex, (p - e.yx) * 4.3).r;
	NORMAL_MAP = normalize(vec3(nx * 3.0, ny * 3.0, 1.0)) * 0.5 + 0.5;
}
