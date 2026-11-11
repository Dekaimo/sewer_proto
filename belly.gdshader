shader_type canvas_item;
// サメの体内（小窓の背景）。ドロドロのペンキの肉壁が脈打ちながら迫ってくる。
// squeeze: 0〜1 で壁が内側に締まる。ドット絵に合わせて px 単位で量子化する。

uniform vec2 size = vec2(280.0, 180.0);
uniform float squeeze = 0.0;
uniform float px = 2.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	vec2 p = floor(UV * size / px) * px;
	vec2 c = (p - size * 0.5) / (size * 0.5);          // -1〜1
	float t = TIME;
	// 楕円の胃袋。締まると内側の空間が狭くなる
	float wob = noise(vec2(atan(c.y, c.x) * 3.0, t * 0.8)) * 0.18;
	float r = length(c * vec2(1.0, 1.15));
	float inner = 0.78 - squeeze * 0.22 + wob;
	vec3 deep = vec3(0.20, 0.03, 0.12);
	vec3 wall = vec3(0.62, 0.15, 0.40);
	vec3 pink = vec3(0.925, 0.353, 0.620);
	vec3 yellow = vec3(0.976, 0.847, 0.302);
	vec3 col;
	if (r < inner) {
		// 中の空間：暗い奥行き＋垂れてくるペンキ
		col = mix(vec3(0.33, 0.06, 0.20), deep, smoothstep(0.0, inner, r));
		float drip = step(0.86, noise(vec2(p.x / 9.0, p.y / 40.0 - t * 0.7)));
		if (drip > 0.5) col = mix(col, pink, 0.6);
	} else {
		// 肉壁：ひだ（リング）がゆっくり脈打つ
		float ring = sin((r - inner) * 16.0 - t * 2.0 + noise(p / 22.0) * 3.0);
		col = ring > 0.35 ? mix(wall, pink, 0.75) : wall * 0.85;
		float m = sin(p.x / 11.0 + noise(p / 20.0 + t * 0.2) * 8.0);
		if (m > 0.93) col = mix(wall, yellow, 0.7);
		if (ring > 0.96 && noise(p / 6.0) > 0.6) col = vec3(1.0, 0.82, 0.92);   // てかり（まばら）
		if (r - inner < 0.035) col = vec3(0.30, 0.04, 0.18);   // 内側の縁は暗く
	}
	// 小窓の外周は暗く落とす
	float edge = max(abs(c.x), abs(c.y));
	col *= 1.0 - smoothstep(0.9, 1.0, edge) * 0.6;
	COLOR = vec4(col, 1.0);
}
