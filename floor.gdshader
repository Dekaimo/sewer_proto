shader_type canvas_item;
// 下水道の床。下地は古いペンキ染み、その上に「ドロドロ」(goop_tex) を描く。
// goop_tex は床全体の厚みマップ（0〜1）。キャラのドット絵と同じ描き方（暗い輪郭・下側の影・てかり）にする。

uniform vec2 size = vec2(960.0, 210.0);
uniform float px = 1.0;
uniform sampler2D goop_tex : filter_linear, repeat_disable;

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
	vec2 q = vec2(p.x / 70.0, p.y / (16.0 + 26.0 * depth));

	// --- 下地：濡れた石の床と、古くて濁ったペンキ染み ---
	vec3 base = mix(vec3(0.13, 0.14, 0.16), vec3(0.20, 0.21, 0.23), depth);
	float n0 = fbm(q * 0.8 + vec2(7.0, 0.0));
	vec3 col = base;
	if (n0 > 0.58) col = mix(base, vec3(0.30, 0.13, 0.24), 0.6);
	if (n0 > 0.66) col = mix(base, vec3(0.33, 0.29, 0.14), 0.5);

	// --- ドロドロ ---
	float t = TIME * 0.04;
	vec2 cell = 1.0 / size;
	float wob = (fbm(vec2(p.x / 22.0 + t, p.y / 9.0)) - 0.5) * 0.22;
	float g = texture(goop_tex, uv).r;
	float v = g + wob * step(0.03, g);
	float th = 0.30;
	if (v > th) {
		// となりの厚み（上＝奥、下＝手前）で、盛り上がりの明暗をつける
		float g_dn = texture(goop_tex, uv + vec2(0.0, cell.y * 5.0)).r + wob;
		float g_up = texture(goop_tex, uv - vec2(0.0, cell.y * 5.0)).r + wob;
		vec3 pink = vec3(0.925, 0.353, 0.620);
		vec3 pink_dark = vec3(0.722, 0.208, 0.478);
		vec3 yellow = vec3(0.976, 0.847, 0.302);
		vec3 gc = pink;
		float m = fbm(vec2(p.x / 46.0 - t, p.y / 14.0));
		float swirl = sin(p.x / 15.0 + m * 9.0 + p.y / 9.0);
		if (swirl > 0.80) gc = yellow;
		if (g_dn < th + 0.04) gc = pink_dark;                             // 手前の縁は影
		else if (g_up < th + 0.02 && swirl < 0.3) gc = vec3(1.0, 0.72, 0.86);   // 奥の縁はてかり
		if (m > 0.70 && swirl < -0.2 && v > th + 0.2) gc = vec3(1.0, 0.86, 0.94);   // 面のてかり
		if (v < th + 0.05) gc = vec3(0.26, 0.05, 0.19);                      // 暗い輪郭
		col = gc;
	} else if (v > th - 0.06 && g > 0.03) {
		col = mix(col, vec3(0.0), 0.45);   // 床に落ちる影
	} else if (g > 0.06) {
		// 薄いペンキ：引きずった跡・にじみ。薄くても見えるように、くすんだピンクで塗る
		float smear = sin(p.x / 7.0 + p.y / 3.0 + fbm(p / 18.0) * 6.0);
		vec3 thin = smear > 0.5 ? vec3(0.62, 0.22, 0.45) : vec3(0.48, 0.15, 0.34);
		if (smear > 0.9 && g > 0.15) thin = vec3(0.70, 0.60, 0.25);
		col = mix(col, thin, clamp(g / th, 0.35, 0.9));
	}
	COLOR = vec4(col, 1.0);
}
