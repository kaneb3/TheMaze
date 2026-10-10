shader_type spatial;
// The first-person gloves and sleeves (the lantern arm and the hand holding the map): the textures
// art/scripts/bake_export.py bakes (albedo, ORM: G roughness / B metallic, tangent normal), shaded as
// worn oilskin and leather under a lantern that is only ~25-35 cm away.
//  - A soft oiled sheen (0.3), not the default plastic 0.5: that, plus the lantern's unclamped highlight,
//    read as a pale latex glove (tested: with the albedo forced red it still came out pink); with none
//    at all the dark leather vanished into the night.
//  - The lantern's light, and its sheen, roll off softly (as on the map) instead of washing it white.
//  - A warm bias so brown leather survives AgX and the teal grade (which pull it to blue-grey clay).
//  - Optional depth trick (depth_scale < 1) for parts held out in front, so walls don't cut them.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform float depth_scale = 1.0;
uniform vec3 tint : source_color = vec3(1.0, 0.86, 0.68);
uniform float value = 1.35;
uniform float normal_depth = 1.1;  // the baked grain and folds (stronger reads as caterpillar bands on the thumb)
uniform float leather_specular = 0.16;  // oiled leather: a soft broad sheen, not plastic (0.5) or dead (0.1)
uniform vec2 roughness_range = vec2(0.68, 0.92);  // worn glossier at the knuckles and tips, dull elsewhere
uniform float light_knee = 1.4;
uniform float sheen = 0.5;

// (Godot hands projection to the shader if POSITION is written anywhere, even in a branch: always
// write it; depth_scale = 1 leaves the depth unchanged.)
void vertex() {
	vec4 view = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	POSITION = PROJECTION_MATRIX * view;
	// (not in the lantern's shadow pass: there the depth must be true, or the shadows land wrong)
	float k = IN_SHADOW_PASS ? 1.0 : depth_scale;
	vec4 near = PROJECTION_MATRIX * vec4(view.xyz * k, 1.0);
	POSITION.z = near.z / near.w * POSITION.w;
}

void fragment() {
	ALBEDO = texture(albedo_tex, UV).rgb * tint * value;
	vec3 orm = texture(orm_tex, UV).rgb;
	ROUGHNESS = mix(roughness_range.x, roughness_range.y, orm.g);
	METALLIC = orm.b;
	SPECULAR = leather_specular;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = normal_depth;
}

void light() {
	float nl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	vec3 l = LIGHT_COLOR * ATTENUATION * nl / PI;
	vec3 lk = l / (1.0 + light_knee * max(l.r, max(l.g, l.b)));  // rolled-off light (the lantern is close)
	DIFFUSE_LIGHT += lk;
	// the sheen goes through the same roll-off: raw, the lantern 35 cm away washed the glove white
	vec3 h = normalize(VIEW + LIGHT);
	float a = ROUGHNESS * ROUGHNESS;
	float nh = clamp(dot(NORMAL, h), 0.0, 1.0);
	float d = a * a / (PI * pow(nh * nh * (a * a - 1.0) + 1.0, 2.0));
	SPECULAR_LIGHT += lk * PI * min(d, 4.0) * 0.04 * sheen;
}
