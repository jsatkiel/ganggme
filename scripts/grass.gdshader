shader_type spatial;
render_mode cull_disabled, shadows_disabled;
// Grass clump cards (the user's grass.png): cut out by alpha (no wind sway: the user cut it), normals point up
// so the cards light like the lawn instead of flat paper.

uniform sampler2D clump : source_color, filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(0.8, 0.82, 0.62, 1.0);

varying vec3 shade;

void vertex() {
	NORMAL = vec3(0.0, 1.0, 0.0);
	shade = INSTANCE_CUSTOM.rgb;
}

void fragment() {
	vec4 c = texture(clump, UV);
	if (c.a < 0.45) {
		discard;
	}
	ALBEDO = c.rgb * tint.rgb * shade;
	ROUGHNESS = 0.9;
	NORMAL = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz; // light both sides like the lawn (no black backs)
}
