shader_type canvas_item;
// Fine animated film grain (~3%), strongest in the midtones: the film reference is 35 mm, and
// perfectly clean gradients in fog and shadow read as CG plastic.
uniform sampler2D screen : hint_screen_texture, filter_nearest;
uniform float amount = 0.03;

float rand(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec3 c = texture(screen, SCREEN_UV).rgb;
	float luma = dot(c, vec3(0.299, 0.587, 0.114));
	float g = rand(FRAGCOORD.xy + fract(TIME * 7.13) * 431.0) - 0.5;
	float w = amount * (0.35 + 0.65 * (1.0 - abs(luma * 2.0 - 1.0)));
	COLOR = vec4(c + g * w, 1.0);
}
