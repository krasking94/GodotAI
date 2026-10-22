shader_type spatial;

// Земля кладбища: трава двух оттенков с крупными пятнами, проплешины голой земли,
// утоптанные тропинки через центр (к склепам) и редкие цветочки. Карта (gy_maps.gd) добавляет
// снег (snow: белый покров с голубыми тенями и искрами), мокрые тёмные пятна (wet: болото),
// брусчатку (cobble: мозаика камней на дорожках) и выбирает число тропинок (paths: 1 — крест
// по диагоналям, 2 — крест по осям и диагонали, 3 — одно прямое шоссе вдоль X).
// Всё считается по мировым координатам, поэтому плитки земли стыкуются без швов.

uniform vec3 grass_dark : source_color = vec3(0.14, 0.24, 0.12);
uniform vec3 grass_light : source_color = vec3(0.26, 0.40, 0.17);
uniform vec3 dirt_color : source_color = vec3(0.30, 0.23, 0.16);
uniform vec3 path_color : source_color = vec3(0.47, 0.37, 0.25);
uniform float path_width = 1.2;       // половина ширины тропинки в метрах
uniform float flower_rarity = 0.975;  // чем ближе к 1, тем реже цветы
uniform float snow = 0.0;
uniform float wet = 0.0;
uniform float cobble = 0.0;
uniform int paths = 1;

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

// Мозаика камней: ячейки со случайным сдвигом, тёмные швы между ними.
float stones(vec2 p) {
	vec2 cell = floor(p);
	float best = 10.0;
	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			vec2 c = cell + vec2(float(x), float(y));
			vec2 center = c + 0.5 + (vec2(hash(c), hash(c + 5.0)) - 0.5) * 0.6;
			float d = max(abs(p.x - center.x), abs(p.y - center.y)) + length(p - center) * 0.3;
			best = min(best, d);
		}
	}
	return best;
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
	// Тропинки, слегка извилистые.
	float wobble = (fbm(p * 0.3) - 0.5) * 1.6;
	float d;
	if (paths == 3) {
		d = abs(p.y + wobble * 0.5);
	} else {
		d = min(abs(p.x + p.y + wobble), abs(p.x - p.y + wobble)) * 0.7071;
		if (paths == 2) {
			d = min(d, min(abs(p.x + wobble * 0.5), abs(p.y + wobble * 0.5)));
		}
	}
	float path = 1.0 - smoothstep(path_width * 0.75, path_width * 1.25, d);
	vec3 trampled = path_color * (0.85 + 0.3 * noise(p * 3.0));
	if (cobble > 0.0) {
		float seam = smoothstep(0.40, 0.47, stones(p * 2.2));
		vec3 stone = path_color * (0.85 + 0.3 * hash(floor(p * 2.2)));
		trampled = mix(trampled, mix(stone, path_color * 0.6, seam), cobble * 0.8);
	}
	col = mix(col, trampled, path);
	// Мокрые тёмные пятна (болото): темнее и более гладкие.
	float puddle = smoothstep(0.55, 0.7, fbm(p * 0.2 + vec2(41.0))) * wet;
	col = mix(col, col * 0.45 + vec3(0.02, 0.05, 0.04), puddle);
	// Мелкая зернистость, чтобы трава не была плоской заливкой.
	col *= 0.88 + 0.24 * noise(p * 14.0);
	// Цветочки: редкие клетки по 25 см, не на тропинке.
	vec2 cell = floor(p * 4.0);
	float h = hash(cell);
	vec2 local = fract(p * 4.0) - 0.5;
	float petal = step(flower_rarity, h) * (1.0 - smoothstep(0.1, 0.16, length(local))) * (1.0 - path);
	vec3 flower = h > 0.992 ? vec3(0.75, 0.55, 0.90) : (h > 0.984 ? vec3(0.95, 0.85, 0.30) : vec3(0.95, 0.95, 0.90));
	col = mix(col, flower, petal);
	// Снег: белый покров с голубыми тенями, на тропинках утоптан и серее, редкие искры.
	float rough = 0.95;
	if (snow > 0.0) {
		float cover = smoothstep(0.25, 0.6, fbm(p * 0.35 + vec2(3.0))) * 0.35 + 0.65;
		vec3 snow_col = mix(vec3(0.5, 0.56, 0.7), vec3(0.72, 0.76, 0.86), cover);
		snow_col = mix(snow_col, vec3(0.44, 0.47, 0.54) * (0.9 + 0.2 * noise(p * 6.0)), path * 0.7);
		float sparkle = step(0.995, hash(floor(p * 9.0) + 1.0)) * 0.6;
		snow_col += vec3(sparkle);
		col = mix(col, snow_col, snow * (1.0 - bare * 0.3));
		rough = mix(0.95, 0.7, snow);
	}
	ALBEDO = col;
	ROUGHNESS = mix(rough, 0.25, puddle);
	METALLIC = 0.0;
}
