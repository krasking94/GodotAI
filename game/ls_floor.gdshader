shader_type spatial;
render_mode cull_back;

// Полы и земля «Симулятора жизни», рисуются по мировым координатам (швы между комнатами не видны):
// mode 0 — доски (паркет), 1 — плитка, 2 — ковёр, 3 — трава снаружи. Два цвета и масштаб задаёт игра.

uniform int mode = 0;
uniform vec4 color_a : source_color = vec4(0.85, 0.66, 0.42, 1.0);
uniform vec4 color_b : source_color = vec4(0.72, 0.52, 0.30, 1.0);
uniform float cell = 0.6;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.85;

varying vec3 world_pos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	vec3 col = color_a.rgb;
	float rough = roughness_value;
	if (mode == 0) {
		// Доски: длинные по x, со случайным сдвигом ряда и лёгкими волокнами.
		float row = floor(p.y / (cell * 0.25));
		float shift = hash(vec2(row, 1.0)) * 2.0;
		float plank = floor((p.x + shift) / (cell * 2.2));
		float tone = hash(vec2(plank, row));
		float grain = noise(vec2(p.x * 9.0, p.y * 60.0)) * 0.12;
		col = mix(color_a.rgb, color_b.rgb, tone * 0.7 + grain);
		vec2 gap = vec2(fract((p.x + shift) / (cell * 2.2)), fract(p.y / (cell * 0.25)));
		float edge = step(gap.x, 0.02) + step(gap.y, 0.06);
		col *= 1.0 - clamp(edge, 0.0, 1.0) * 0.28;
		rough = 0.55;
	} else if (mode == 1) {
		// Плитка в шахматном порядке со швами.
		vec2 tile = floor(p / cell);
		float checker = mod(tile.x + tile.y, 2.0);
		col = mix(color_a.rgb, color_b.rgb, checker);
		col *= 0.96 + noise(p * 3.0) * 0.08;
		vec2 gap = abs(fract(p / cell) - 0.5);
		float seam = step(0.47, max(gap.x, gap.y));
		col = mix(col, col * 0.7, seam);
		rough = 0.35;
	} else if (mode == 2) {
		// Ковёр: мягкий шум ворса и редкие светлые точки.
		float n = noise(p * 18.0) * 0.5 + noise(p * 70.0) * 0.5;
		col = mix(color_a.rgb, color_b.rgb, n);
		rough = 1.0;
	} else {
		// Трава: пятна двух оттенков и мелкое зерно.
		float big = noise(p * 0.35);
		float fine = noise(p * 6.0);
		col = mix(color_a.rgb, color_b.rgb, smoothstep(0.35, 0.7, big) * 0.8 + fine * 0.2);
		col *= 0.92 + noise(p * 30.0) * 0.12;
		rough = 1.0;
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = 0.3;
}
