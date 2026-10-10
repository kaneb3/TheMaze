shader_type spatial;
// The hand-held map's sheet (client/assets/map/map.glb, built by art/scripts/fp_map.py). Baked
// parchment (Blender: mottled vellum, tide-line stains, foxing, browned nibbled edges, creases) with
// the map's ink laid over it from MapInk's SubViewport (R = ink, G = lantern-lit gold).
//  - Iron-gall ink: brown-black, feathered a little into the paper fibres, faintly glossier.
//  - Lit cells: a warm gold wash that glows softly in the dark (spec §9.1: "lit cells glow").
//  - Marauder's-Map reveal: the ink spreads out from where you stand when the map opens (`spread`,
//    a radius in metres on the sheet), with a darker wet edge; `ink_fade` draws it back on closing.
//  - The back is plain parchment.
// The lantern hangs ~25 cm from the sheet, so its light is very strong here: light() rolls the
// highlights off softly instead of blowing the paper out to white.
render_mode cull_disabled, diffuse_lambert, depth_prepass_alpha;

uniform sampler2D front_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D back_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform sampler2D ink_tex : filter_linear;  // MapInk's viewport (the inked face)
uniform vec2 ink_texel = vec2(0.000651, 0.000868);  // 1 / viewport size
uniform vec2 sheet_size = vec2(0.40, 0.30);  // metres
uniform vec2 spread_centre = vec2(0.5, 0.5);  // UV where the ink wells up from (you are here)
uniform float spread = 1.0;  // metres of ink revealed around spread_centre
uniform float ink_fade = 1.0;
uniform vec3 ink_color : source_color = vec3(0.10, 0.06, 0.035);
uniform vec3 gold_color : source_color = vec3(1.0, 0.55, 0.03);
uniform float gold_glow = 0.22;
uniform float gold_wash = 0.88;
// Keeps the sheet warm tan under the cold lantern, AgX and the teal grade (which pulls red down hard
// and bleaches bright warm tones to olive): measured on screen, not guessed (look-dev --mapparam).
uniform vec3 paper_tint : source_color = vec3(1.15, 0.7, 0.36);
uniform float light_knee = 1.6;  // highlight roll-off for the close lantern (0 = linear)
uniform float normal_strength = 0.6;
// Held 44 cm out, the sheet would cut into a wall you stand against (you can be 40 cm from one).
// Its depth is written as if it were this much nearer (the picture is unchanged): just inside the
// closest wall, still behind the lantern arm.
uniform float depth_scale = 0.78;
uniform float corner_lift = 0.0;  // m, towards the eye
uniform float corner_radius = 0.17;
// Contact shading where the right thumb presses the sheet (its pad, solved in art/scripts/fp_map.py,
// sits ~6.5 cm in from the right edge and ~3.2 cm up from the bottom): a soft occlusion pool, a
// little longer along the thumb, offset away from the lantern on the left.
uniform vec2 thumb_uv = vec2(0.819, 0.908);  // printed by fp_map.build_everything_v8
uniform float thumb_shade = 0.6;
uniform float crease_strength = 0.6;

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	// the top-left corner's flutter (PaperSheet.corner_lift): a smooth push along the normal that fades
	// to nothing ~17 cm from the corner, so the sheet stays one continuous piece of paper
	float r = length(UV * sheet_size);  // UV (0, 0) is the top-left corner
	float f = max(0.0, 1.0 - r / corner_radius);
	VERTEX += NORMAL * corner_lift * f * f;
	vec4 view = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	POSITION = PROJECTION_MATRIX * view;
	vec4 near = PROJECTION_MATRIX * vec4(view.xyz * depth_scale, 1.0);
	POSITION.z = near.z / near.w * POSITION.w;
}

void fragment() {
	vec4 front = texture(front_tex, UV);
	vec3 paper = FRONT_FACING ? front.rgb : texture(back_tex, UV).rgb;
	ALPHA = front.a;  // one silhouette for both sides
	ALPHA_SCISSOR_THRESHOLD = 0.5;

	vec2 iuv = UV;
	vec4 ink = FRONT_FACING ? texture(ink_tex, iuv) : vec4(0.0);  // the back is plain parchment
	// feathering: the ink wicks a little way into the fibres around every stroke
	vec4 halo = (texture(ink_tex, iuv + vec2(2.5, 0.0) * ink_texel) + texture(ink_tex, iuv - vec2(2.5, 0.0) * ink_texel)
		+ texture(ink_tex, iuv + vec2(0.0, 2.5) * ink_texel) + texture(ink_tex, iuv - vec2(0.0, 2.5) * ink_texel)) * 0.25;
	halo *= FRONT_FACING ? 1.0 : 0.0;

	float mask = 1.0;
	float wet = 0.0;
	if (FRONT_FACING) {
		vec2 m = (UV - spread_centre) * sheet_size;
		float d = length(m) + (vnoise(UV * 38.0) - 0.5) * 0.03 + (vnoise(UV * 140.0) - 0.5) * 0.008;
		mask = 1.0 - smoothstep(spread - 0.012, spread, d);
		wet = (1.0 - smoothstep(0.0, 0.03, abs(spread - 0.015 - d))) * step(d, spread);
	}
	float fade = FRONT_FACING ? ink_fade : 1.0;
	float k = mask * fade;
	float ink_amt = clamp(ink.r * (0.92 + 0.3 * wet) + halo.r * 0.14, 0.0, 1.0) * k;
	// the gold is a watercolour wash: soft-edged, pooling unevenly in the paper
	vec4 wash = vec4(0.0);
	for (int i = 0; i < 8; i++) {
		float a = float(i) * 0.785;
		wash += texture(ink_tex, iuv + vec2(cos(a), sin(a)) * 14.0 * ink_texel);
	}
	wash *= FRONT_FACING ? 0.125 : 0.0;
	float pool = 0.75 + 0.5 * vnoise(UV * 90.0);
	float gold = clamp(mix(ink.g, wash.g, 0.65) * pool, 0.0, 1.0) * k;

	// fresh ink is darker and a touch more saturated than the dry, browned strokes
	vec3 inkc = mix(ink_color, ink_color * vec3(0.55, 0.5, 0.6), wet);
	vec3 col = paper * paper_tint;
	if (FRONT_FACING) {
		vec2 dm = (UV - thumb_uv - vec2(0.004, 0.006)) * sheet_size;  // metres
		dm = mat2(vec2(0.82, 0.57), vec2(-0.57, 0.82)) * dm;  // along the thumb (up and in)
		vec2 q = dm / vec2(0.016, 0.028);  // a pool a little wider than the thumb, so its rim shows
		float occ = exp(-dot(q, q));
		col *= 1.0 - thumb_shade * occ;
	}
	col = mix(col, gold_color * (0.55 + 0.45 * pool), gold * gold_wash);  // a gilt wash, clearly not paper
	col = mix(col, inkc, ink_amt * 0.94);
	ALBEDO = col;
	EMISSION = gold_color * (gold + wash.g * 0.35 * k) * gold_glow * (1.0 - ink_amt);
	ROUGHNESS = mix(0.92, 0.6, ink_amt);
	SPECULAR = 0.06;  // matte vellum: no sky sheen
	vec3 nm = texture(normal_tex, UV).rgb * 2.0 - 1.0;
	if (FRONT_FACING) {
		// pressure creases radiating from the thumb's dent (ridges run outwards, so the normal swings
		// round the dent), fading in from the pad's edge and out over a few centimetres
		vec2 dt = (UV - thumb_uv) * sheet_size;
		float r = length(dt);
		float ang = atan(dt.y, dt.x);
		float band = smoothstep(0.006, 0.012, r) * (1.0 - smoothstep(0.012, 0.04, r));
		float ridge = sin(ang * 9.0 + (vnoise(vec2(ang * 3.0, 1.7)) - 0.5) * 4.0) * band * (0.5 + vnoise(UV * 40.0));
		nm.xy += vec2(-sin(ang), cos(ang)) * ridge * crease_strength;
	}
	NORMAL_MAP = normalize(nm) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = normal_strength;
}

void light() {
	float nl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	// paper scatters light through its fibres: a little wrap keeps raking light from banding the panels
	float wrap = clamp((dot(NORMAL, LIGHT) + 0.35) / 1.35, 0.0, 1.0);
	vec3 l = LIGHT_COLOR * ATTENUATION * wrap / PI;
	DIFFUSE_LIGHT += l / (1.0 + light_knee * max(l.r, max(l.g, l.b)));
	vec3 h = normalize(VIEW + LIGHT);
	float spec = pow(clamp(dot(NORMAL, h), 0.0, 1.0), mix(8.0, 40.0, 1.0 - ROUGHNESS)) * (1.0 - ROUGHNESS) * 0.25;
	SPECULAR_LIGHT += l / (1.0 + light_knee * max(l.r, max(l.g, l.b))) * PI * spec * SPECULAR_AMOUNT;
}
