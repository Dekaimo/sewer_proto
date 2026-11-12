shader_type canvas_item;
// 粘液の幹。輪郭は上（上半身とのつなぎ目）から下（床の水たまり）へなめらかに広がる形で自前で描き、
// 中身は、ワニと同じ色のマーブル粘液をコードで描き、下へ流し落とす（繰り返し模様を避ける）。
// さらに行ごとに横へずらしてしならせる（根元 0 → 中ほど mid_off → 上端 top_off）。
uniform float v0 = 0.0;
uniform float v1 = 1.0;
uniform float total_h = 18.0;
uniform float band_y0 = 192.0;
uniform float band_h = 14.0;
uniform float flow = 0.0;
uniform float top_off = 0.0;
uniform float mid_off = 0.0;
uniform float tex_w = 256.0;
uniform float tex_h = 256.0;
uniform vec2 top_edge = vec2(74.0, 174.0);   // つなぎ目（上）の左右の端
uniform vec2 bot_edge = vec2(63.0, 201.0);   // 床側（下）の左右の端

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) { return noise(p) * 0.6 + noise(p * 2.1) * 0.3 + noise(p * 4.3) * 0.1; }

void fragment() {
	float local = clamp((UV.y - v0) / max(v1 - v0, 1e-5), 0.0, 0.9999);
	float ypx = floor(local * total_h);
	float k = ypx / max(total_h - 1.0, 1.0);      // 0=上 1=下
	float t = 1.0 - local;
	float off = floor(2.0 * (1.0 - t) * t * mid_off + t * t * top_off + 0.5);
	float x = floor(UV.x * tex_w) - off;
	// 輪郭：下ほど広がる（下の方で急に裾が開く）
	float kk = k * k;
	float l = mix(top_edge.x, bot_edge.x, kk);
	float r = mix(top_edge.y, bot_edge.y, kk);
	if (x < l || x > r) {
		COLOR = vec4(0.0);
	} else {
		// 中身：ワニと同じ色のマーブル粘液を、下へ流れ落ちるように描く（繰り返し模様にならない）
		float u = (x - l) / max(r - l, 1.0);
		float yy = ypx - flow;
		float n1 = fbm(vec2(x / 18.0, yy / 34.0));
		float n2 = fbm(vec2(x / 7.0 + 3.0, yy / 60.0));
		float marble = sin(x * 0.09 + n1 * 9.0 + yy * 0.015);
		vec3 col = vec3(0.925, 0.353, 0.620);
		if (abs(marble) < 0.09) col = vec3(0.976, 0.847, 0.302);           // 細い黄色の線（ワニの模様と同じ）
		else if (marble < -0.6) col = vec3(0.82, 0.27, 0.54);              // ひと段濃いピンク
		// 縦に流れる垂れ（ところどころ光る）
		if (n2 > 0.66 && fract(x / 11.0) < 0.25) col = vec3(1.0, 0.78, 0.90);
		// 丸い立体感：左寄りが明るく、右端へ向けて暗く
		float shade = 1.0 - smoothstep(0.35, 1.0, u) * 0.38;
		if (u < 0.22) shade += 0.06;
		col *= shade;
		vec4 c = vec4(col, 1.0);
		// 上のつなぎ目：最初の数行は元の絵の続き（同じ列・その下の行）をそのまま使って段差を消す
		if (ypx < 7.0) {
			vec4 orig = texture(TEXTURE, vec2((x + 0.5) / tex_w, (band_y0 + ypx + 0.5) / tex_h));
			if (orig.a > 0.5) c = mix(orig, c, ypx / 7.0);
		}
		// 輪郭線と、縁の内側の影
		if (x - l < 2.0 || r - x < 2.0) c = vec4(0.18, 0.03, 0.12, 1.0);
		else if (r - x < 6.0) c.rgb *= 0.75;
		else if (x - l < 5.0) c.rgb = mix(c.rgb, vec3(1.0, 0.85, 0.93), 0.35);   // 左の縁はてかり
		COLOR = c;
	}
}
