shader_type spatial;
// Repaints a Kenney Car Kit model: the bright toy body colors become real car paint
// (clear-coated, a little dusty), the light-blue window swatch becomes dark tinted glass,
// and the greys (tires, trim, bumpers) stay as they are, just dirtier.

uniform sampler2D colormap : source_color, filter_linear_mipmap;
uniform vec4 paint : source_color = vec4(0.3, 0.3, 0.32, 1.0);
uniform float dirt = 0.3;
uniform sampler2D grime_tex : filter_linear_mipmap;

void fragment() {
	vec3 c = texture(colormap, UV).rgb;
	float mx = max(c.r, max(c.g, c.b));
	float mn = min(c.r, min(c.g, c.b));
	float sat = mx > 0.001 ? (mx - mn) / mx : 0.0;
	float g = texture(grime_tex, UV * 6.0).r;
	if ((UV.x < 0.125 && UV.y < 0.25) || (mx > 0.78 && sat < 0.22)) {
		// windows
		ALBEDO = vec3(0.04, 0.05, 0.06);
		ROUGHNESS = 0.08;
		METALLIC = 0.5;
		SPECULAR = 0.8;
	} else if (sat > 0.28 && mx > 0.25) {
		// body panels
		ALBEDO = mix(paint.rgb, vec3(0.32, 0.29, 0.25), dirt * g);
		ROUGHNESS = mix(0.35, 0.8, dirt * g);
		METALLIC = 0.25;
		CLEARCOAT = 0.7;
		CLEARCOAT_ROUGHNESS = 0.25;
	} else {
		// tires, trim, bumpers, chrome
		ALBEDO = vec3(dot(c, vec3(0.3, 0.59, 0.11))) * 0.5;
		ROUGHNESS = mx > 0.7 ? 0.25 : 0.85;
		METALLIC = mx > 0.7 ? 0.7 : 0.0;
	}
}
