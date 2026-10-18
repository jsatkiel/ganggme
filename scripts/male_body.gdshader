shader_type spatial;
// The user's male body under the baked clothes. Each vertex's COLOR holds how much it belongs to the hoodie,
// pants, shoes and bare skin (worked out from all 8 of its bone weights in crew_model.gd), and the covered
// parts are painted in the clothes' colors so any spot that pokes through still reads as cloth.

uniform sampler2D skin_tex : source_color, filter_linear_mipmap;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform vec4 hoodie_color : source_color = vec4(0.045, 0.045, 0.05, 1.0);
uniform vec4 pants_color : source_color = vec4(0.10, 0.105, 0.12, 1.0);
uniform vec4 shoe_color : source_color = vec4(0.75, 0.75, 0.76, 1.0);

varying vec4 region_w;

void vertex() {
	region_w = COLOR;
}

void fragment() {
	vec4 w = region_w;
	vec3 col = texture(skin_tex, UV).rgb;
	float rough = 0.6;
	float cloth = 1.0;
	if (w.x >= w.y && w.x >= w.z && w.x >= w.w) { col = hoodie_color.rgb; rough = 0.95; }
	else if (w.y >= w.z && w.y >= w.w) { col = pants_color.rgb; rough = 0.9; }
	else if (w.z >= w.w) { col = shoe_color.rgb; rough = 0.7; }
	else { cloth = 0.0; }
	ALBEDO = col;
	ROUGHNESS = rough;
	NORMAL_MAP = mix(texture(normal_tex, UV).rgb, vec3(0.5, 0.5, 1.0), cloth);
}
