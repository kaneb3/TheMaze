shader_type spatial;
// Ring 1 maze floor: CC0 photoscan setts (Poly Haven cobblestone_pavement, 2.5 m tile) mapped in
// world space, so one plane covers the whole maze with no seams, plus:
//  - macro variation and trodden grime, heavier along the cell edges where walls stand
//  - moss and dirt packed into the joints
//  - shallow puddles / damp patches: darker, glossy, the only things that glint under the lantern
render_mode cull_back;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D arm_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D height_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D moss_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D macro_noise : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float tile_m = 2.5;
uniform float cell_m = 4.0;
uniform vec3 tint : source_color = vec3(0.74, 0.72, 0.68);
uniform vec3 dirt_color : source_color = vec3(0.20, 0.17, 0.13);
uniform vec3 moss_tint : source_color = vec3(0.55, 0.62, 0.36);

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	vec2 uv = p / tile_m;
	vec3 col = texture(albedo_tex, uv).rgb * tint;
	vec3 arm = texture(arm_tex, uv).rgb;
	float h = texture(height_tex, uv).r;
	float m1 = texture(macro_noise, p * 0.11).r;
	float m2 = texture(macro_noise, p * 0.37 + 0.5).r;
	col *= mix(0.7, 1.1, m1);
	col *= mix(0.88, 1.1, texture(macro_noise, floor(uv * 10.0) * 0.137).r);  // sett-to-sett variation

	// grime: everywhere a little, heavy near cell edges (where the walls stand), darkest in a
	// strip along the wall bases (wall faces sit 0.3 m from the edge line)
	vec2 f = abs(fract(p / cell_m + 0.5) - 0.5) * cell_m;  // distance to the cell edge lines
	float d_edge = min(f.x, f.y);
	float grime = clamp((1.0 - smoothstep(0.3, 0.9, d_edge)) * (0.55 + 0.6 * m2) + 0.15, 0.0, 1.0);
	col = mix(col, dirt_color, grime * 0.6);
	col = mix(col, dirt_color * 0.6, (1.0 - smoothstep(0.32, 0.62, d_edge)) * 0.7);

	// joints: packed dirt and moss
	float joint = 1.0 - smoothstep(0.18, 0.4, h);
	vec3 moss = texture(moss_tex, uv * 4.0).rgb * moss_tint;
	col = mix(col, mix(dirt_color * 0.8, moss, smoothstep(0.4, 0.75, m2)), joint * 0.85);

	// puddles and damp: low spots in wet patches
	float wet_patch = smoothstep(0.55, 0.66, texture(macro_noise, p * 0.17 + 0.23).r);
	float puddle = wet_patch * (1.0 - smoothstep(0.35, 0.6, h + (m1 - 0.5) * 0.3));
	col *= mix(1.0, 0.55, max(puddle, wet_patch * 0.5));

	ALBEDO = col;
	ROUGHNESS = mix(clamp(arm.g * 0.2 + 0.78, 0.0, 1.0), 0.12, puddle);
	ROUGHNESS = mix(ROUGHNESS, 0.5, wet_patch * (1.0 - puddle) * 0.6);
	SPECULAR = mix(0.3, 0.5, puddle);
	AO = arm.r * 0.4;  // the corridor floor sees about a quarter of the sky
	AO_LIGHT_AFFECT = 0.1;
	NORMAL_MAP = mix(texture(normal_tex, uv).rgb, vec3(0.5, 0.5, 1.0), puddle * 0.9);  // standing water is flat
	NORMAL_MAP_DEPTH = 1.6;
}
