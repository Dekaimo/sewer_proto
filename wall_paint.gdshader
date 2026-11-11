shader_type canvas_item;
// 壁にたまっていくペンキ。wall_tex の赤 = 厚み（4pxごと）。線形補間してしきい値で切ると、なめらかな塊になる。

uniform sampler2D wall_tex : filter_linear, repeat_disable;
uniform vec2 size = vec2(960.0, 430.0);

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	vec2 p = floor(UV * size);
	vec2 uv = (p + 0.5) / size;
	float m = texture(wall_tex, uv).r;
	float th = 0.28;
	if (m < th) {
		COLOR = vec4(0.0);
	} else {
		vec2 cell = 1.0 / size;
		float mn = min(min(texture(wall_tex, uv + vec2(cell.x, 0)).r, texture(wall_tex, uv - vec2(cell.x, 0)).r),
					   min(texture(wall_tex, uv + vec2(0, cell.y)).r, texture(wall_tex, uv - vec2(0, cell.y)).r));
		// ノイズでゆがめたマーブル（縞が規則的にならないように）
		float nz = noise(p / 22.0 + vec2(0.0, TIME * 0.05)) + 0.5 * noise(p / 9.0);
		float marble = sin(p.y * 0.05 + nz * 7.0);
		vec3 col = vec3(0.86, 0.31, 0.58);
		if (marble > 0.62) col = vec3(0.95, 0.81, 0.29);
		if (marble < -0.75) col = vec3(0.72, 0.22, 0.49);
		// 厚いほど明るく、薄いところは暗く沈む
		col *= 0.65 + 0.4 * clamp(m, 0.0, 1.0);
		if (mn < th) col = vec3(0.45, 0.10, 0.30);   // 縁取り
		else if (m > 0.85 && marble > 0.1 && marble < 0.35) col = vec3(1.0, 0.82, 0.92);   // てかり
		COLOR = vec4(col, 1.0);
	}
}
