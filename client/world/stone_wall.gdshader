shader_type spatial;
// Weathered maze-wall stone (Ring 1). A CC0 photoscan (Poly Haven rough_block_wall) on real relief
// geometry, layered with what years of damp do to a wall at night:
//  - macro variation in colour and roughness (no two walls alike, no visible tiling)
//  - moss settling into the joints (height-blended), heavier near the ground and under the hedge
//  - grime and damp rising from the ground, dark leak streaks running down from the hedge
//  - pale lichen blooms on the block faces
// Everything is matte (stone 0.85-0.95); only fresh damp streaks get a little sheen.
render_mode cull_back;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D arm_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;  // AO, roughness, metal
uniform sampler2D height_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D moss_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D moss_normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D leak_tex : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform sampler2D macro_noise : hint_default_white, filter_linear_mipmap, repeat_enable;

uniform float stone_top = 1.9;  // local height where the hedge takes over
uniform vec3 stone_tint : source_color = vec3(0.80, 0.79, 0.76);
uniform vec3 moss_tint : source_color = vec3(0.62, 0.66, 0.42);  // olive, not lawn
uniform vec3 grime_color : source_color = vec3(0.16, 0.13, 0.10);
uniform vec3 leak_color : source_color = vec3(0.10, 0.11, 0.08);
uniform vec3 lichen_color : source_color = vec3(0.66, 0.68, 0.60);
uniform float saturation = 0.62;  // the scan is warmer than the brief's grey stone
uniform float value = 0.8;
uniform float moss_amount = 0.55;
uniform bool box_map = false;  // pillars etc.: tile-scale UVs from local position, picked by face axis
uniform vec2 tile = vec2(3.04, 3.0);  // metres per texture tile (the photoscan's real size)
uniform float normal_strength = 0.85;

varying vec3 world_pos;
varying vec3 local_pos;
varying float wall_seed;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	local_pos = VERTEX;
	wall_seed = hash(floor(MODEL_MATRIX[3].xz + 0.5));
	if (box_map) {
		vec3 an = abs(NORMAL);
		if (an.y > max(an.x, an.z)) {
			UV = VERTEX.xz / tile;  // caps and undersides: planar from above, no stretching
		} else {
			float hz = an.x > an.z ? VERTEX.z : VERTEX.x;
			UV = vec2(hz / tile.x + wall_seed * 0.37, 1.0 - VERTEX.y / tile.y);
		}
	}
}

void fragment() {
	vec4 base = texture(albedo_tex, UV);
	vec3 arm = texture(arm_tex, UV).rgb;
	float h = texture(height_tex, UV).r;  // 0 deep joint .. 1 proud block face
	float y = local_pos.y;
	// coordinate running along the wall, offset per wall so the masks never repeat between walls
	float along = local_pos.x + wall_seed * 37.0;

	// macro variation: patches of warmer/colder, darker/lighter stone at 1-4 m scale
	float m1 = texture(macro_noise, vec2(along, y) * 0.23).r;
	float m2 = texture(macro_noise, vec2(along, y) * 0.71 + 0.37).r;
	float luma = dot(base.rgb, vec3(0.299, 0.587, 0.114));
	vec3 col = mix(vec3(luma), base.rgb, saturation) * stone_tint * value * mix(0.74, 1.12, m1);
	// block-to-block variation: some stones warmer, some colder, some darker (per ~0.5 m patch)
	float blk = texture(macro_noise, floor(vec2(along * 2.1, y * 2.8)) * 0.073).r;
	col *= mix(vec3(0.84, 0.86, 0.88), vec3(1.08, 1.02, 0.94), blk) * mix(0.85, 1.1, fract(blk * 7.3));
	col *= mix(vec3(1.04, 0.98, 0.92), vec3(0.94, 0.98, 1.03), m2);  // warm / cool cast

	// grime and rising damp near the ground, with a ragged edge
	// a ragged tide-line 30-80 cm up, darker and greener-black towards the floor
	float rise = 0.3 + 0.35 * m2 + 0.25 * texture(macro_noise, vec2(along * 1.3, 0.37)).r;
	float grime = 1.0 - smoothstep(rise - 0.12, rise + 0.04, y + 0.05 * (texture(macro_noise, vec2(along * 6.0, y * 4.0)).r - 0.5));
	grime = max(grime, (1.0 - smoothstep(0.0, 0.25, y)) * 0.8);  // splash and mud right at the base
	col = mix(col, col * vec3(0.55, 0.57, 0.50), grime * 0.85);

	// dark streaks leaking down from the wet hedge above (stronger at the top, fading downward)
	// a few broad, soft, tonal streaks per wall (8-25 cm wide, 0.3-1.2 m long), with faint hairlines
	float band = smoothstep(0.6, 0.72, texture(macro_noise, vec2(along * 0.33, 0.71)).r);
	float run = 0.3 + 0.9 * texture(macro_noise, vec2(along * 0.21, 0.13)).r;
	float below = stone_top - y;
	float leak = band * smoothstep(0.0, 0.1, below) * (1.0 - smoothstep(run * 0.5, run, below));
	float hair = smoothstep(0.35, 0.75, texture(leak_tex, vec2(along * 0.45, below * 0.55)).r);
	col *= 1.0 - leak * (0.2 + 0.08 * hair);

	// moss: lives in the joints (low height) and only climbs onto faces where it is damp
	float damp = clamp(grime * 0.9 + smoothstep(stone_top - 0.6, stone_top, y) * 0.7 + (m1 - 0.5) * 0.5, 0.0, 1.0);
	float patch = texture(macro_noise, vec2(along, y) * 1.7 + 0.61).r;  // moss grows in colonies
	float moss_level = moss_amount * (0.22 + 0.5 * damp) * smoothstep(0.25, 0.65, patch + 0.25 * damp);
	float moss = 1.0 - smoothstep(moss_level - 0.06, moss_level + 0.03, h + (m2 - 0.5) * 0.18);
	vec3 moss_col = texture(moss_tex, UV * 3.0).rgb * moss_tint;
	col = mix(col, moss_col, moss * 0.9);

	// lichen blooms: sparse pale rosettes on proud, dry faces
	vec2 cell = floor(vec2(along, y) * 3.3);
	vec2 frac_p = fract(vec2(along, y) * 3.3);
	float rnd = hash(cell + wall_seed);
	float spot = 1.0 - smoothstep(0.08, 0.32 * rnd, length(frac_p - vec2(hash(cell + 1.7), hash(cell + 4.1))));
	float lichen = spot * step(0.62, rnd) * smoothstep(0.5, 0.7, h) * (1.0 - damp * 0.8);
	lichen *= smoothstep(0.3, 0.6, texture(macro_noise, UV * 9.0).r);
	vec3 lichen_col = fract(rnd * 13.1) < 0.3 ? vec3(0.62, 0.56, 0.3) : lichen_color;  // some ochre rosettes
	col = mix(col, lichen_col * (0.6 + 0.3 * m2), clamp(lichen * 1.9, 0.0, 0.85));
	// black lichen dots on the upper, drier stone
	float dots = step(0.86, texture(macro_noise, UV * 23.0 + wall_seed).r) * smoothstep(0.6, 1.3, y) * smoothstep(0.55, 0.7, h);
	col = mix(col, vec3(0.025, 0.025, 0.02), dots * 0.9);

	// contact shade under the hedge's overhang
	float hem = stone_top - 0.6 + 0.25 * (texture(macro_noise, vec2(along * 1.4, 0.9)).r - 0.5);
	col *= mix(1.0, 0.4, smoothstep(hem, stone_top - 0.05, y));  // ragged contact shade under the hem

	ALBEDO = col;
	float rough = clamp(arm.g * 0.15 + 0.82, 0.0, 1.0);
	rough = mix(rough, 0.97, moss);
	rough = mix(rough, 0.6, clamp(leak * 0.7, 0.0, 0.6));  // fresh damp has a faint sheen
	ROUGHNESS = rough;
	METALLIC = 0.0;
	SPECULAR = 0.35;
	AO = arm.r * mix(1.0, 0.75, grime);
	AO_LIGHT_AFFECT = 0.45;
	vec3 n_stone = texture(normal_tex, UV).rgb;
	vec3 n_moss = texture(moss_normal_tex, UV * 3.0).rgb;
	NORMAL_MAP = mix(n_stone, n_moss, moss * 0.7);
	NORMAL_MAP_DEPTH = normal_strength;
}
