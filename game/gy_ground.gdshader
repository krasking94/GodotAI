shader_type spatial;

// Земля кладбища: трава двух оттенков с крупными пятнами, проплешины голой земли,
// две утоптанные тропинки по диагоналям через центр (к склепам) и редкие цветочки.
// Всё считается по мировым координатам, поэтому плитки земли стыкуются без швов,
// а узор не зависит от размера плитки.

uniform vec3 grass_dark : source_color = vec3(0.14, 0.24, 0.12);
uniform vec3 grass_light : source_color = vec3(0.26, 0.40, 0.17);
uniform vec3 dirt_color : source_color = vec3(0.30, 0.23, 0.16);
uniform vec3 path_color : source_color = vec3(0.47, 0.37, 0.25);
uniform float path_width = 1.2;       // половина ширины тропинки в метрах
uniform float flower_rarity = 0.975;  // чем ближе к 1, тем реже цветы

varying vec3 world_pos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Плавный шум: случайные значения в узлах решётки, сглаженные между ними.
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

// Несколько слоёв шума разного масштаба: крупные пятна плюс мелкие детали.
float fbm(vec2 p) {
	float value = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 5; i++) {
		value += amplitude * noise(p);
		p = p * 2.03 + vec2(13.7, 7.1);
		amplitude *= 0.5;
	}
	return value;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	// Трава: крупные пятна светлого и тёмного оттенка.
	vec3 col = mix(grass_dark, grass_light, smoothstep(0.3, 0.75, fbm(p * 0.25)));
	// Проплешины голой земли.
	float bare = smoothstep(0.6, 0.74, fbm(p * 0.12 + vec2(17.0))) * 0.85;
	col = mix(col, dirt_color, bare);
	// Две тропинки по диагоналям через центр, к склепам, слегка извилистые.
	float wobble = (fbm(p * 0.3) - 0.5) * 1.6;
	float d = min(abs(p.x + p.y + wobble), abs(p.x - p.y + wobble)) * 0.7071;
	float path = 1.0 - smoothstep(path_width * 0.75, path_width * 1.25, d);
	vec3 trampled = path_color * (0.85 + 0.3 * noise(p * 3.0));
	col = mix(col, trampled, path);
	// Мелкая зернистость, чтобы трава не была плоской заливкой.
	col *= 0.88 + 0.24 * noise(p * 14.0);
	// Цветочки: редкие клетки по 25 см, не на тропинке.
	vec2 cell = floor(p * 4.0);
	float h = hash(cell);
	vec2 local = fract(p * 4.0) - 0.5;
	float petal = step(flower_rarity, h) * (1.0 - smoothstep(0.1, 0.16, length(local))) * (1.0 - path);
	vec3 flower = h > 0.992 ? vec3(0.75, 0.55, 0.90) : (h > 0.984 ? vec3(0.95, 0.85, 0.30) : vec3(0.95, 0.95, 0.90));
	col = mix(col, flower, petal);
	ALBEDO = col;
	ROUGHNESS = 0.95;
	METALLIC = 0.0;
}
