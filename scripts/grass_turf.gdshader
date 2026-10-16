shader_type spatial;
render_mode cull_disabled, shadows_disabled;
// Low turf (grass_short.png): like grass.gdshader, but each card turns about its upright axis to face the
// camera, so the short cards never show their edges or read as X shapes from standing height.

uniform sampler2D clump : source_color, filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(0.8, 0.82, 0.62, 1.0);
uniform float sway = 0.025;

varying vec3 shade;

void vertex() {
	float top = clamp(VERTEX.y, 0.0, 1.0);
	vec3 world = MODEL_MATRIX[3].xyz;
	float t = TIME * 1.6 + world.x * 0.35 + world.z * 0.27;
	VERTEX.x += sin(t) * sway * top;
	// upright billboard that keeps the instance's size
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), INV_VIEW_MATRIX[2].xyz));
	vec3 fwd = cross(right, vec3(0.0, 1.0, 0.0));
	mat4 face = mat4(vec4(right * length(MODEL_MATRIX[0].xyz), 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(fwd * length(MODEL_MATRIX[2].xyz), 0.0), MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = VIEW_MATRIX * face;
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
	NORMAL = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz; // light like the lawn
}
