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
// Distance to the nearest real wall base (metres / 2, 0..1) over the maze, built by look-dev from
// the maze data: grime and occlusion follow the actual walls, not the cell grid.
uniform sampler2D wall_dist_tex : hint_default_white, filter_linear, repeat_disable;
uniform vec2 maze_size = vec2(48.0, 48.0);

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
	col *= mix(0.85, 1.05, m1);
	col *= mix(0.9, 1.08, texture(macro_noise, floor(uv * 10.0) * 0.137).r);  // sett-to-sett variation

	// grime gathers along the bases of the real walls (soft, ragged), lightly everywhere else
	float d_wall = texture(wall_dist_tex, p / maze_size).r * 2.0;
	float base = 1.0 - smoothstep(0.0, 0.45 + 0.25 * m2, d_wall);
	col = mix(col, dirt_color, 0.15 + base * 0.45);

	// joints: packed dirt and moss
	float joint = 1.0 - smoothstep(0.18, 0.4, h);
	vec3 moss = texture(moss_tex, uv * 4.0).rgb * moss_tint;
	col = mix(col, mix(dirt_color * 0.8, moss, smoothstep(0.4, 0.75, m2)), joint * 0.85);

	// puddles and damp: low spots in wet patches
	// the odd shallow puddle in a low spot (small and rare, not big dark blotches)
	float wet_patch = smoothstep(0.68, 0.74, texture(macro_noise, p * 0.23 + 0.23).r);
	float puddle = wet_patch * (1.0 - smoothstep(0.3, 0.5, h));
	col *= mix(1.0, 0.7, puddle);

	ALBEDO = col;
	ROUGHNESS = mix(clamp(arm.g * 0.2 + 0.78, 0.0, 1.0), 0.12, puddle);
	ROUGHNESS = mix(ROUGHNESS, 0.6, wet_patch * (1.0 - puddle) * 0.4);
	SPECULAR = mix(0.3, 0.5, puddle);
	AO = arm.r * mix(0.3, 0.45, smoothstep(0.0, 1.7, d_wall));  // a corridor floor sees about a quarter of the sky
	AO_LIGHT_AFFECT = 0.1;
	NORMAL_MAP = mix(texture(normal_tex, uv).rgb, vec3(0.5, 0.5, 1.0), puddle * 0.9);  // standing water is flat
	NORMAL_MAP_DEPTH = 1.6;
}
