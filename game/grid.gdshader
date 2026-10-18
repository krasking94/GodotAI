shader_type spatial;

// Клетчатая разметка земли: две краски в шахматном порядке и светлые линии по границам клеток.
// Клетки считаются по мировым координатам, поэтому плоскость любого размера размечается одинаково,
// а по мелькающим линиям видно скорость и повороты машины.

uniform vec3 color_a : source_color = vec3(0.42, 0.42, 0.40);
uniform vec3 color_b : source_color = vec3(0.50, 0.50, 0.47);
uniform vec3 line_color : source_color = vec3(0.92, 0.92, 0.88);
uniform float cell = 4.0;        // размер клетки в метрах
uniform float line_width = 0.12; // толщина линии в метрах

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz / cell;
	vec2 f = fract(p);
	float checker = mod(floor(p.x) + floor(p.y), 2.0);
	vec3 col = mix(color_a, color_b, checker);
	vec2 d = min(f, 1.0 - f) * cell;
	float dist = min(d.x, d.y);
	float aa = fwidth(dist);
	float line = 1.0 - smoothstep(line_width * 0.5 - aa, line_width * 0.5 + aa, dist);
	ALBEDO = mix(col, line_color, line);
	ROUGHNESS = 0.95;
	METALLIC = 0.0;
}
