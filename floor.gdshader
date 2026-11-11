shader_type canvas_item;
// 下水道の床。下地は古いペンキ染み、その上に「ドロドロ」(goop_tex) を描く。
// goop_tex は横1行の厚みマップ（0〜1）。足元の線の周りに帯状に広がる。

uniform vec2 size = vec2(960.0, 110.0);
uniform float px = 1.0;
uniform sampler2D goop_tex : filter_linear, repeat_disable;
uniform float feet_v = 0.53;   // 足元の線の位置（0=奥 1=手前）

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) { v += a * noise(p); p *= 2.0; a *= 0.5; }
	return v;
}

void fragment() {
	vec2 p = floor(UV * size / px) * px;
	vec2 uv = p / size;
	float depth = uv.y;
	vec2 q = vec2(p.x / 60.0, p.y / (18.0 + 30.0 * depth));

	// --- 下地：古くて濁ったペンキ染み ---
	vec3 base = mix(vec3(0.15, 0.16, 0.18), vec3(0.19, 0.20, 0.22), depth);
	float n0 = fbm(q * 0.8 + vec2(7.0, 0.0));
	vec3 col = base;
	if (n0 > 0.58) col = mix(base, vec3(0.30, 0.13, 0.24), 0.6);
	if (n0 > 0.66) col = mix(base, vec3(0.33, 0.29, 0.14), 0.5);

	// --- ドロドロ ---
	float g = texture(goop_tex, vec2(uv.x, 0.5)).r;
	float t = TIME * 0.05;
	float wob = fbm(vec2(p.x / 26.0 + t, p.y / 9.0));
	// 厚いほど足元の線から奥・手前へ広く広がる
	float half_w = g * (0.42 + 0.25 * wob);
	float d = abs(depth - feet_v);
	float edge = half_w - d;
	if (g > 0.04 && edge > 0.0) {
		float m = fbm(vec2(p.x / 40.0 - t * 2.0, p.y / 12.0) * 1.5);
		vec3 pink = vec3(0.93, 0.36, 0.63);
		vec3 pink_dark = vec3(0.70, 0.20, 0.47);
		vec3 yellow = vec3(0.98, 0.85, 0.32);
		vec3 gc = pink;
		float swirl = sin(p.x / 9.0 + m * 10.0 + p.y / 7.0);
		if (swirl > 0.72) gc = yellow;
		if (edge < 0.035) gc = pink_dark;                       // 縁取り
		if (edge > 0.05 && m > 0.66 && swirl < 0.0) gc = vec3(1.0, 0.80, 0.90);   // てかり
		col = gc;   // 床のドロドロはワニと同じ色。どこから出てくるかわからないように一体化させる
	} else if (g > 0.04 && edge > -0.03) {
		col = mix(col, vec3(0.45, 0.12, 0.30), 0.6);   // にじみ
	}

	col *= 0.75 + 0.25 * smoothstep(0.0, 0.25, depth);
	COLOR = vec4(col, 1.0);
}
