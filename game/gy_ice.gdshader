shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

// Лужа на земле: лёд (блестит, с трещинами) или грязь (тёмная, мокрая). Круг с мягким краем
// вырезается из квадратной плоскости по UV, узор считается по мировым координатам.

uniform vec3 base_color : source_color = vec3(0.42, 0.62, 0.84);
uniform vec3 edge_color : source_color = vec3(0.58, 0.76, 0.92);
uniform float shine = 1.0;      // 1 — лёд (зеркальный), 0 — грязь (матовая)
uniform float cracks = 1.0;     // сколько трещин
uniform float alpha_max = 0.9;

varying vec3 world_pos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 c = UV - 0.5;
	float r = length(c) * 2.0;
	float wobble = (noise(world_pos.xz * 1.7) - 0.5) * 0.25;
	float mask = 1.0 - smoothstep(0.78 + wobble, 1.0 + wobble, r);
	if (mask < 0.02) {
		discard;
	}
	vec2 p = world_pos.xz;
	// Трещины: тонкие светлые линии там, где шум проходит через середину.
	float n = noise(p * 2.3);
	float crack = (1.0 - smoothstep(0.0, 0.035, abs(n - 0.5))) * cracks;
	float n2 = noise(p * 5.1 + 3.0);
	crack = max(crack, (1.0 - smoothstep(0.0, 0.02, abs(n2 - 0.5))) * 0.6 * cracks);
	vec3 col = mix(base_color, edge_color, smoothstep(0.5, 1.0, r) * 0.6);
	col = mix(col, vec3(1.0), crack * 0.5);
	// Блики: по направлению взгляда (Френель), на льду сильнее.
	float fresnel = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.0);
	col += vec3(0.6, 0.75, 0.9) * fresnel * 0.5 * shine;
	ALBEDO = col;
	ALPHA = mask * alpha_max;
	ROUGHNESS = mix(0.9, 0.08, shine);
	METALLIC = 0.0;
	SPECULAR = mix(0.2, 0.7, shine);
}
