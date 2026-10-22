shader_type sky;

// Небо «Кладбища»: градиент от горизонта к зениту, мерцающие звёзды, луна с ореолом.
// Цвета задаёт карта (gy_maps.gd): кровавая луна красная, зимняя белая, в лесу еле видна.

uniform vec3 top_color : source_color = vec3(0.04, 0.07, 0.19);
uniform vec3 horizon_color : source_color = vec3(0.16, 0.23, 0.40);
uniform vec3 ground_color : source_color = vec3(0.08, 0.11, 0.19);
uniform vec3 haze_color : source_color = vec3(0.16, 0.23, 0.40);
uniform vec3 moon_color : source_color = vec3(0.96, 0.94, 0.88);
uniform vec3 moon_dir = vec3(0.45, 0.55, -0.35);
uniform float moon_size = 0.035;
uniform float stars = 1.0;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float h = d.y;
	vec3 col;
	if (h >= 0.0) {
		col = mix(horizon_color, top_color, clamp(pow(h, 0.55), 0.0, 1.0));
	} else {
		col = mix(horizon_color, ground_color, clamp(-h * 4.0, 0.0, 1.0));
	}
	// Дымка у горизонта.
	col = mix(col, haze_color, (1.0 - smoothstep(0.0, 0.25, abs(h))) * 0.5);
	// Звёзды: в каждой ячейке неба по случайной точке, часть ячеек пустые, яркость мерцает.
	if (h > 0.02 && stars > 0.0) {
		vec3 cell = floor(d * 90.0);
		float r = hash13(cell);
		vec3 offset = vec3(hash13(cell + 7.0), hash13(cell + 13.0), hash13(cell + 29.0)) - 0.5;
		float dist = length(d * 90.0 - (cell + 0.5 + offset * 0.7));
		float twinkle = 0.65 + 0.35 * sin(TIME * (1.5 + r * 3.0) + r * 20.0);
		float star = step(1.0 - 0.09 * stars, r) * (1.0 - smoothstep(0.0, 0.22 + 0.2 * r, dist)) * twinkle;
		star *= smoothstep(0.02, 0.2, h);
		col += vec3(0.9, 0.93, 1.0) * star * 1.6;
	}
	// Луна: диск и мягкий ореол.
	vec3 m = normalize(moon_dir);
	float angle = acos(clamp(dot(d, m), -1.0, 1.0));
	float disc = 1.0 - smoothstep(moon_size * 0.85, moon_size, angle);
	float halo = exp(-angle * 9.0) * 0.5;
	col += moon_color * (disc * 1.8 + halo);
	COLOR = col;
}
