shader_type canvas_item;
// Behind an open menu: the game view blurred, dimmed and warmed so the parchment reads.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float amount : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec3 sharp = texture(screen_tex, SCREEN_UV).rgb;
	vec3 soft = textureLod(screen_tex, SCREEN_UV, 3.0).rgb;
	vec3 col = mix(sharp, soft, amount);
	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, luma * vec3(1.0, 0.86, 0.68), 0.5 * amount);  // desaturate towards sepia
	vec2 v = SCREEN_UV - 0.5;
	col *= mix(1.0, 0.55 - dot(v, v) * 0.9, amount);  // dim, with a vignette
	COLOR = vec4(col, 1.0);
}
