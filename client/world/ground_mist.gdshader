shader_type fog;
// Patchy ground mist: 3-8 m wisps drifting slowly, densest at the floor and thinning with height,
// instead of one uniform veil.
uniform sampler3D noise_tex : repeat_enable;
uniform float density = 0.45;
uniform vec3 albedo : source_color = vec3(0.66, 0.76, 0.84);

void fog() {
	vec3 p = WORLD_POSITION * 0.06 + vec3(0.012, 0.0, 0.005) * TIME;
	float n = texture(noise_tex, p).r * 0.7 + texture(noise_tex, p * 3.1 + 0.37).r * 0.3;
	DENSITY = density * smoothstep(0.35, 0.75, n) * exp(-max(WORLD_POSITION.y, 0.0) * 0.9);
	ALBEDO = albedo;
}
