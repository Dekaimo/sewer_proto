shader_type canvas_item;
// 下水道の床。下地は古いペンキ染み、その上に「ドロドロ」(goop_tex) を描く。
// goop_tex は床全体の厚みマップ（0〜1）。キャラのドット絵と同じ描き方（暗い輪郭・下側の影・てかり）にする。

uniform vec2 size = vec2(960.0, 210.0);
uniform float px = 1.0;
uniform sampler2D goop_tex : filter_linear, repeat_disable;
// 地中で何かが暴れている場所：床のペンキそのものが盛り上がる（x, y, 横の半径, 高さ）床の座標・ピクセル
uniform vec4 heaves[12];
uniform int heave_n = 0;
// 波紋（x, y, 半径, 強さ）
uniform vec4 rings[6];
uniform int ring_n = 0;

float heave_h(vec2 p) {
	float h = 0.0;
	for (int i = 0; i < 12; i++) {
		if (i >= heave_n) break;
		vec4 hv = heaves[i];
		vec2 d = (p - hv.xy) / vec2(hv.z, hv.z * 0.36);
		float r2 = dot(d, d);
		// 裾はなだらか、頂上は丸い（ガウス）
		h += hv.w * exp(-r2 * 2.2);
	}
	for (int j = 0; j < 6; j++) {
		if (j >= ring_n) break;
		vec4 rg = rings[j];
		vec2 d2 = (p - rg.xy) / vec2(1.0, 0.36);
		float dist = length(d2);
		h += rg.w * exp(-pow((dist - rg.z) / 5.0, 2.0));
	}
	return h;
}

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
	vec2 p0 = floor(UV * size / px) * px;
	// 盛り上がり：この画素に見えているのは、もっと手前（下）の床が持ち上がった面。逆算して元の位置を探す
	vec2 p = p0;
	float hh = 0.0;
	if (heave_n > 0 || ring_n > 0) {
		for (int it = 0; it < 5; it++) {
			hh = heave_h(p);
			p = vec2(p0.x, p0.y + hh);
		}
		p = floor(p);
	}
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
	// 盛り上がっているところは、床のドロドロが分厚く押し上げられている
	g = max(g, smoothstep(0.6, 3.0, hh) * 0.85);
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
		// 盛り上がりの陰影：手前側の斜面は暗く、頂上はてかる。上側の輪郭は暗い線
		if (hh > 0.8) {
			float hd = heave_h(p + vec2(0.0, 2.0));
			float hu = heave_h(p - vec2(0.0, 2.0));
			float slope = (hu - hd) * 0.5;   // 手前に向かって下る＝こちら向きの斜面
			if (slope > 0.9) gc = mix(gc, pink_dark, clamp((slope - 0.9) / 1.5, 0.0, 0.85));
			if (slope > 2.4) gc = mix(gc, vec3(0.42, 0.10, 0.30), 0.6);
			if (slope < -0.4 && slope > -1.6 && swirl < 0.4) gc = mix(gc, vec3(1.0, 0.78, 0.90), 0.55);
			// 頂上の小さなてかり
			if (abs(slope) < 0.25 && hh > 4.0 && fract(p.x / 9.0 + m) < 0.3) gc = vec3(1.0, 0.90, 0.96);
			// 上側のシルエット：一つ上の画素が、ずっと低い面を見ているなら輪郭
			vec2 pa = vec2(p0.x, p0.y - 1.0);
			float ha = 0.0;
			vec2 qa = pa;
			for (int it2 = 0; it2 < 4; it2++) { ha = heave_h(qa); qa = vec2(pa.x, pa.y + ha); }
			if (qa.y - p.y > 3.0) gc = vec3(0.26, 0.05, 0.19);
		}
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
