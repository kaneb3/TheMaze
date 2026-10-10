shader_type canvas_item;
// Aged parchment for menus, in the spirit of the Marauder's Map: mottled hide-coloured paper,
// tea stains with dark tide-lines, fibres, fold creases worn pale, a ragged browned edge and a
// hand-ruled double ink border. Everything is procedural and keyed to pixels (sheet_size), so the
// grain stays the same size whatever the sheet's shape.

uniform vec2 sheet_size = vec2(460.0, 540.0);  // the rect's size in pixels
uniform float seed = 3.7;
uniform vec3 paper_light : source_color = vec3(0.87, 0.78, 0.59);
uniform vec3 paper_dark : source_color = vec3(0.71, 0.57, 0.37);
uniform vec3 stain : source_color = vec3(0.52, 0.36, 0.18);
uniform vec3 ink : source_color = vec3(0.19, 0.10, 0.05);
uniform vec2 folds = vec2(2.0, 2.0);  // panels across / down: creases between them
uniform float border_inset = 22.0;  // outer ink rule, pixels from the edge
uniform float edge_rag = 9.0;  // how far the torn edge wanders, pixels

float hash(vec2 p) {  // Dave Hoskins' hash12: no lattice artefacts
	vec3 p3 = fract(vec3(p.xyx + seed * 17.0) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	mat2 r = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	for (int i = 0; i < 5; i++) {
		v += a * vnoise(p);
		p = r * p * 2.03 + 17.1;
		a *= 0.5;
	}
	return v;
}

// One hand-ruled line: distance to an inset rectangle's outline, wobbling slightly along its length.
float ruled(vec2 px, float inset, float width) {
	vec2 lo = vec2(inset);
	vec2 hi = sheet_size - vec2(inset);
	float wob = (vnoise(px * 0.035 + inset) - 0.5) * 1.6;
	vec2 d = min(px - lo, hi - px);
	float inside = min(d.x, d.y);
	float outside = length(max(-d, 0.0));
	float dist = abs(inside > 0.0 ? inside : -outside) + wob;
	// ink skips a little where the nib ran dry
	float skip = smoothstep(0.18, 0.32, vnoise(px * 0.06 + inset * 3.0));
	return (1.0 - smoothstep(width * 0.5, width * 0.5 + 0.9, dist)) * mix(0.55, 1.0, skip);
}

void fragment() {
	vec2 px = UV * sheet_size;
	vec2 p = px / 140.0;

	// --- paper body: large soft mottling, then mid blotches, then grain
	float mott = fbm(p * 0.9);
	vec3 col = mix(paper_dark, paper_light, smoothstep(0.3, 0.72, mott));
	col = mix(col, paper_dark * 0.92, smoothstep(0.45, 0.8, fbm(p * 0.35 + 23.0)) * 0.5);  // broad age shading
	col *= 0.94 + 0.08 * fbm(p * 3.5 + 7.0);
	col *= 0.97 + 0.06 * vnoise(px * 0.9);

	// fibres: short streaks running mostly across the sheet
	float fib = vnoise(vec2(px.x * 0.05, px.y * 0.9) + 31.0);
	col *= 1.0 - 0.05 * smoothstep(0.7, 0.95, fib);
	float fib2 = vnoise(vec2(px.x * 0.7, px.y * 0.04) + 77.0);
	col *= 1.0 + 0.035 * smoothstep(0.75, 0.97, fib2);

	// tea stains with darker tide-lines where the water dried
	float s = fbm(p * 0.55 + 41.0);
	float blot = smoothstep(0.58, 0.64, s);
	float tide = smoothstep(0.57, 0.585, s) * (1.0 - smoothstep(0.585, 0.62, s));
	col = mix(col, col * mix(vec3(1.0), stain / paper_light, 0.35), blot * 0.6);
	col = mix(col, stain, tide * 0.35);
	// foxing: little rusty specks
	float fox = smoothstep(0.86, 0.93, vnoise(px * 0.11 + 5.0)) * smoothstep(0.5, 0.7, fbm(p * 2.0 + 9.0));
	col = mix(col, stain * 0.9, fox * 0.45);

	// --- fold creases: a hairline valley with a pale worn ridge beside it, and the panels
	// either side tilting slightly towards / away from the light
	float crease = 0.0;
	float ridge = 0.0;
	for (int i = 1; i < 4; i++) {
		if (float(i) < folds.x) {
			float cx = sheet_size.x * float(i) / folds.x + (vnoise(vec2(px.y * 0.02, float(i))) - 0.5) * 2.0;
			float dx = px.x - cx;
			crease += exp(-abs(dx) / 0.9) * 0.55 + exp(-abs(dx) / 22.0) * 0.12 * sign(-dx);
			ridge += exp(-abs(dx - 1.8) / 1.4);
		}
		if (float(i) < folds.y) {
			float cy = sheet_size.y * float(i) / folds.y + (vnoise(vec2(px.x * 0.02, float(i) + 9.0)) - 0.5) * 2.0;
			float dy = px.y - cy;
			crease += exp(-abs(dy) / 0.9) * 0.55 + exp(-abs(dy) / 22.0) * 0.12 * sign(-dy);
			ridge += exp(-abs(dy - 1.8) / 1.4);
		}
	}
	float wear = 0.5 + 0.5 * vnoise(px * 0.08);
	col *= 1.0 - 0.42 * clamp(crease, -1.0, 1.0) * wear;
	col = mix(col, paper_light * 1.06, clamp(ridge, 0.0, 1.0) * 0.3 * wear);

	// --- edge: ragged outline, browned and darkened towards it like old handled paper
	vec2 d2 = min(px, sheet_size - px);
	float d = min(d2.x, d2.y);
	float rag = (fbm(px * 0.03 + 19.0) - 0.5) * 2.0 * edge_rag + (vnoise(px * 0.4) - 0.5) * 2.5;
	float de = d + rag - edge_rag;  // signed distance inside the torn edge
	float alpha = smoothstep(0.0, 1.5, de);
	col *= mix(0.52, 1.0, smoothstep(0.0, 70.0, de));
	col = mix(col, stain * 0.55, (1.0 - smoothstep(0.0, 6.0, de)) * 0.7);

	// --- the hand-ruled double border in ink
	float ink_amt = max(ruled(px, border_inset, 2.2), ruled(px, border_inset + 7.0, 1.1));
	float ink_var = 0.75 + 0.25 * fbm(px * 0.05 + 3.0);
	col = mix(col, ink, ink_amt * ink_var * 0.9);

	COLOR = vec4(col, alpha * COLOR.a);
}
