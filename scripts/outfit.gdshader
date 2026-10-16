shader_type spatial;
render_mode cull_disabled; // the first-person hand is seen up close from behind the wrist: keep it solid
// Paints clothes onto the base body by which bone each vertex follows, so the outfit
// moves with every animation: 0 hoodie, 1 pants, 2 shoes, 3 skin (original texture),
// 4 head + neck (skin), 5 forearm (hoodie). The player's own first-person view draws only forearms + hands.

uniform int regions[128];
uniform bool hide_head = false;
uniform float near_cut = 0.2; // first person: drop anything closer to the eye than this
uniform bool hide_sleeve = false; // first person, aiming: only the hand shows
uniform sampler2D skin_tex : source_color, filter_linear_mipmap;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform vec4 hoodie_color : source_color = vec4(0.04, 0.04, 0.045, 1.0);
uniform vec4 pants_color : source_color = vec4(0.10, 0.105, 0.12, 1.0);
uniform vec4 shoe_color : source_color = vec4(0.92, 0.92, 0.9, 1.0);
// push cloth out from the body so it reads as a baggy hoodie / pants instead of a bodysuit
uniform float hoodie_puff = 0.035;
uniform float pants_puff = 0.022;
uniform float shoe_puff = 0.02;

varying vec4 region_w;
varying float head_w;
varying float arm_w; // forearm + hands: all the first-person view draws
varying float sleeve_w;

void vertex() {
	vec4 w = vec4(0.0);
	float h = 0.0;
	float a = 0.0;
	float s = 0.0;
	for (int i = 0; i < 4; i++) {
		int r = regions[int(BONE_INDICES[i]) % 128];
		float bw = BONE_WEIGHTS[i];
		if (r == 0 || r == 5) { w.x += bw; if (r == 5) { a += bw; s += bw; } }
		else if (r == 1) { w.y += bw; }
		else if (r == 2) { w.z += bw; }
		else { w.w += bw; if (r == 4) { h += bw; } else { a += bw; } }
	}
	region_w = w;
	head_w = h;
	arm_w = a;
	sleeve_w = s;
	VERTEX += NORMAL * (w.x * hoodie_puff + w.y * pants_puff + w.z * shoe_puff);
}

void fragment() {
	// first person: only the forearms and hands are drawn
	if (hide_head && (arm_w < 0.5 || head_w > 0.05 || length(VERTEX) < near_cut || (hide_sleeve && sleeve_w > 0.4))) {
		discard;
	}
	// pick the strongest region per pixel for crisp seams (cuffs, collar, waistband)
	vec4 w = region_w;
	vec3 col = texture(skin_tex, UV).rgb;
	float rough = 0.6;
	float cloth = 0.0;
	if (w.x >= w.y && w.x >= w.z && w.x >= w.w) { col = hoodie_color.rgb; rough = 0.95; cloth = 1.0; }
	else if (w.y >= w.z && w.y >= w.w) { col = pants_color.rgb; rough = 0.9; cloth = 1.0; }
	else if (w.z >= w.w) { col = shoe_color.rgb; rough = 0.7; cloth = 1.0; }
	ALBEDO = col;
	ROUGHNESS = rough;
	// keep the body's muscle normals on skin only; cloth reads smoother
	vec3 n = texture(normal_tex, UV).rgb;
	NORMAL_MAP = mix(n, vec3(0.5, 0.5, 1.0), cloth);
}
