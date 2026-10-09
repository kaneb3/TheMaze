shader_type spatial;
// Weathered maze-wall stone (Ring 1). A CC0 photoscan (Poly Haven rough_block_wall) on real relief
// geometry, layered with what years of damp do to a wall at night:
//  - macro variation in colour and roughness (no two walls alike, no visible tiling)
//  - moss settling into the joints (height-blended), heavier near the ground and under the hedge
//  - grime and damp rising from the ground, dark leak streaks running down from the hedge
//  - pale lichen blooms on the block faces
// Everything is matte (stone 0.85-0.95); only fresh damp streaks get a little sheen.
//
// Lighting (2026-10-09 research into why close-lit stone read as satin/metallic): Lambert diffuse
// (Burley brightens rough surfaces at grazing angles), low SPECULAR (its f90 drove a near-mirror
// Fresnel sheen at grazing angles), a detail normal layer for sub-centimetre grain at arm's length,
// cavity darkening, and a custom light() that adds the micro-shadowing the shadow map can't
// resolve: AO-based micro-shadows (Brinck & Maximov 2016) and a short height-field march so each
// pit and lip casts a tiny shadow away from the lantern.
render_mode cull_back, diffuse_lambert;

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
uniform float value = 0.58;  // the reference keeps walls dark even under light
uniform float moss_amount = 0.55;
uniform bool box_map = false;  // old flat pillar: tile-scale UVs from local position, picked by face axis
uniform bool uv_along = false;  // meshes that wrap a corner (pillar2): masks run along the UVs, not local x
uniform vec2 tile = vec2(3.04, 3.0);  // metres per texture tile (the photoscan's real size)
uniform float normal_strength = 0.85;
uniform float specular_amount = 0.15;
uniform float ao_direct = 0.0;  // AO (incl. sky occlusion) is ambient-only; light() micro-shadows the lamp
uniform float detail_strength = 0.5;  // fine grain from the same scan at ~0.48 m per repeat
uniform float micro_shadow = 1.0;
uniform float horizon_depth = 0.02;  // m of relief the height march assumes (art knob)
uniform float horizon_soft = 0.003;

varying vec3 world_pos;
varying vec3 local_pos;
varying float wall_seed;
varying float v_ao;
varying vec3 v_t;
varying vec3 v_b;
varying vec3 v_n;
varying float v_dist;
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


float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	local_pos = VERTEX;
	wall_seed = hash(floor(MODEL_MATRIX[3].xz + 0.5));
	v_sky = sky_visibility(VERTEX.y, NORMAL.y);
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
	float along = (uv_along ? UV.x * tile.x : local_pos.x) + wall_seed * 37.0;

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

	// detail grain at a non-repeating odd scale of the same scan, and cavity darkening
	vec2 duv = UV * 6.37 + vec2(0.31, 0.77);
	col *= mix(0.9, 1.1, texture(albedo_tex, duv).g * 1.4);
	col *= mix(1.0, arm.r, 0.4);
	ALBEDO = col;
	float rough = clamp(arm.g * 0.15 + 0.82, 0.0, 1.0);
	rough = mix(rough, 0.97, moss);
	rough = mix(rough, 0.6, clamp(leak * 0.7, 0.0, 0.6));  // fresh damp has a faint sheen
	ROUGHNESS = rough;
	METALLIC = 0.0;
	SPECULAR = specular_amount;
	AO = arm.r * mix(1.0, 0.75, grime) * mix(1.0, v_sky, sky_occl_strength);
	AO_LIGHT_AFFECT = ao_direct;
	// whiteout blend of the base normal with a fine detail normal (Barré-Brisebois & Hill)
	vec3 nb = texture(normal_tex, UV).rgb * 2.0 - 1.0;
	vec3 nd = texture(normal_tex, duv).rgb * 2.0 - 1.0;
	vec3 n_stone = normalize(vec3(nb.xy + nd.xy * detail_strength, nb.z * nd.z)) * 0.5 + 0.5;
	vec3 n_moss = texture(moss_normal_tex, UV * 3.0).rgb;
	NORMAL_MAP = mix(n_stone, n_moss, moss * 0.7);
	NORMAL_MAP_DEPTH = normal_strength;
	v_ao = arm.r;
	v_t = TANGENT;
	v_b = BINORMAL;
	v_n = NORMAL;
	v_dist = length(VERTEX);
}


// Height-field self-shadow: march towards the light across the scan's height map and darken where
// nearby relief rises above the light ray (tiny cast shadows the shadow map can't see).
float horizon(vec2 uv, vec3 l) {
	vec2 dir = normalize(l.xy + 1e-5) * vec2(1.0, -1.0) / tile;
	float slope = max(l.z, 0.0) / max(length(l.xy), 1e-4);
	float h0 = textureLod(height_tex, uv, 0.0).r * horizon_depth;
	float occ = 0.0;
	for (int i = 1; i <= 8; i++) {
		float d = float(i * i) * 0.0008;  // 0.8 mm .. 51 mm, denser near the pixel
		occ = max(occ, (textureLod(height_tex, uv + dir * d, 0.0).r * horizon_depth - h0 - d * slope) / horizon_soft);
	}
	return 1.0 - clamp(occ, 0.0, 1.0);
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float nl = clamp(ndl, 0.0, 1.0);
	// micro-shadowing from the cavity AO (Brinck & Maximov 2016; HDRP ComputeMicroShadowing)
	float ms = mix(1.0, clamp(ndl + 2.0 * v_ao * v_ao - 1.0, 0.0, 1.0), micro_shadow);
	vec3 lt = vec3(dot(LIGHT, v_t), dot(LIGHT, v_b), dot(LIGHT, v_n));
	float hz = mix(horizon(UV, lt), 1.0, smoothstep(3.0, 6.0, v_dist));  // only where it can be seen
	float vis = ATTENUATION * ms * hz;
	DIFFUSE_LIGHT += nl * vis * LIGHT_COLOR / PI;
	// GGX specular with the grazing reflectance capped (rough stone shows no Fresnel sheen)
	vec3 H = normalize(VIEW + LIGHT);
	float a = ROUGHNESS * ROUGHNESS;
	float a2 = a * a;
	float nh = clamp(dot(NORMAL, H), 0.0, 1.0);
	float nv = clamp(dot(NORMAL, VIEW), 1e-4, 1.0);
	float D = a2 / (PI * pow(nh * nh * (a2 - 1.0) + 1.0, 2.0));
	float k = pow(ROUGHNESS + 1.0, 2.0) / 8.0;
	float Vis = 0.25 / ((nl * (1.0 - k) + k) * (nv * (1.0 - k) + k));
	float F = 0.02 + 0.13 * pow(1.0 - clamp(dot(LIGHT, H), 0.0, 1.0), 5.0);
	SPECULAR_LIGHT += D * Vis * F * nl * vis * v_ao * LIGHT_COLOR * SPECULAR_AMOUNT * (specular_amount / 0.15);
}
