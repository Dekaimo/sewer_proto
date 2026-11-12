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
// 柱の絵（下揃えで使う）と、その行ごとの左右の端（R=左, G=右）
uniform sampler2D pillar_tex : filter_nearest;
uniform sampler2D pillar_edges : filter_nearest;
uniform float use_pillar = 0.0;

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
		// 中身：描き起こした柱の絵を、下揃えで使う（伸ばさないのでドットがきれいなまま）
		float u = (x - l) / max(r - l, 1.0);
		vec4 c;
		if (use_pillar > 0.5) {
			float trow = clamp(255.0 - (total_h - 1.0 - ypx), 0.0, 255.0);
			vec4 ed = texture(pillar_edges, vec2((trow + 0.5) / 256.0, 0.5));
			float tl = ed.r * 255.0;
			float tr = ed.g * 255.0;
			float tx = floor(mix(tl, tr, u) + 0.5);
			c = texture(pillar_tex, vec2((tx + 0.5) / 128.0, (trow + 0.5) / 256.0));
			if (c.a < 0.5) c = texture(pillar_tex, vec2(64.5 / 128.0, (trow + 0.5) / 256.0));
			c.a = 1.0;
		} else {
			c = vec4(0.925, 0.353, 0.620, 1.0);
		}
		// 上のつなぎ目：波打つ境目で、元の絵の続きに溶け込ませる
		float wave = 4.0 + 3.0 * sin(x * 0.35) + 2.0 * sin(x * 0.11 + 1.3);
		if (ypx < wave) {
			vec4 orig = texture(TEXTURE, vec2((x + 0.5) / tex_w, (band_y0 + ypx + 0.5) / tex_h));
			if (orig.a > 0.5) c = orig;
		}
		// 下のつなぎ目：根元の絵へ、波打つ境目でつなぐ
		float wave2 = 3.0 + 3.0 * sin(x * 0.27 + 2.0) + 2.0 * sin(x * 0.08);
		if (ypx > total_h - 1.0 - wave2) {
			vec4 o2 = texture(TEXTURE, vec2((x + 0.5) / tex_w, (band_y0 + band_h - 1.0 + 0.5) / tex_h));
			if (o2.a > 0.5) c = o2;
		}
		if (x - l < 1.0 || r - x < 1.0) c = vec4(0.10, 0.02, 0.08, 1.0);
		else if (x - l < 3.0) c.rgb = mix(c.rgb, vec3(1.0, 0.78, 0.90), 0.4);
		else if (r - x < 4.0) c.rgb *= 0.78;
		COLOR = c;
	}
}
