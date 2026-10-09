shader_type spatial;
// Real-leaf foliage cards (Ring 1 hedge and ivy). Each card is one scanned leaf from the CC0 atlas
// (art/scripts/build_leaf_atlas.py). The mesh carries normals transferred from the hedge envelope
// so the mass shades like a volume instead of paper cards, and COLOR_0:
//   r = depth AO (0 deep inside the hedge .. 1 outermost), g = random per leaf, b = 1 for wall ivy.
// Alpha-to-coverage (needs MSAA) keeps the leaf edges smooth; the back face keeps the outward
// normal so both sides light the same.
render_mode cull_disabled, depth_draw_opaque;

uniform sampler2D leaf_albedo : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D leaf_normal : hint_normal, filter_linear_mipmap;
uniform sampler2D leaf_rough : hint_default_white, filter_linear_mipmap;
uniform vec3 hedge_tint : source_color = vec3(0.30, 0.37, 0.30);
uniform vec3 ivy_tint : source_color = vec3(0.36, 0.45, 0.36);
uniform vec3 aged_tint : source_color = vec3(0.95, 0.80, 0.45);
uniform float aged_share = 0.08;
uniform vec3 backlight_color : source_color = vec3(0.10, 0.14, 0.04);
uniform float wind_strength = 0.004;

void vertex() {
	// barely-there night air: the free end of each leaf drifts a few millimetres
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float phase = COLOR.g * 6.283 + TIME * (0.7 + COLOR.g * 0.6) + dot(wp.xz, vec2(0.7, 0.4));
	VERTEX += NORMAL * sin(phase) * wind_strength * (1.0 - COLOR.b * 0.5);
}

void fragment() {
	vec4 tex = texture(leaf_albedo, UV);
	float rnd = COLOR.g;
	vec3 tint = mix(hedge_tint, ivy_tint, COLOR.b);
	tint *= mix(0.78, 1.14, fract(rnd * 7.31));  // value variation per leaf
	tint = mix(tint, tint * vec3(1.05, 0.97, 0.88), fract(rnd * 3.17));  // slight hue shift
	if (rnd < aged_share) {
		tint *= aged_tint;  // a few older, yellowing leaves
	}
	float ao = mix(0.25, 1.0, COLOR.r);
	ALBEDO = tex.rgb * tint * mix(0.3, 1.0, COLOR.r * COLOR.r);  // the core falls to near-black
	AO = ao;
	AO_LIGHT_AFFECT = 0.6;
	ALPHA = tex.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ALPHA_ANTIALIASING_EDGE = 0.3;
	ALPHA_TEXTURE_COORDINATE = UV * vec2(textureSize(leaf_albedo, 0));
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;  // both sides share the envelope normal
	}
	NORMAL_MAP = texture(leaf_normal, UV).rgb;
	NORMAL_MAP_DEPTH = 0.55;
	// hedge leaves are matte; ivy keeps a little wax. Specular fades with distance so the far,
	// moonlit hedge doesn't glitter like a smooth sheet.
	float far = smoothstep(6.0, 18.0, length(VERTEX));
	ROUGHNESS = mix(mix(0.7, 0.88, texture(leaf_rough, UV).r), 0.6, COLOR.b * (1.0 - far));
	SPECULAR = mix(mix(0.22, 0.3, COLOR.b), 0.08, far);
	BACKLIGHT = backlight_color * ao;
}
