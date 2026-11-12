shader_type canvas_item;
// 抱きつき中の1枚絵（ワニ＋主人公）用。cat_mask（白=主人公）の部分にだけ、
// 汚れ率 contamination に応じてマーブルのペンキを乗せる。
// マスクはコマごとに tools/make_hug_masks.py で作る（色に頼らないので、どんな色の敵でも使える）。

uniform float contamination = 0.0;
uniform sampler2D cat_mask : filter_nearest;
// 取り込み：主人公の部分のうち、この高さ（UV）より下はワニの粘液に呑まれる。1.0=呑まれていない
uniform float absorb_y = 1.0;
// この高さ（UVのy）より下は、主人公の画素だけ残す（磔：ワニの細い柱を消して、下半身の絵に差し替える）
uniform float cut_y = 2.0;
// 上半身の下端を波打たせて消す（下の柱と自然につなぐ）。この行（ピクセル）から下が対象
uniform float wave_cut = 999.0;
uniform vec4 pink : source_color = vec4(1.0, 0.30, 0.66, 1.0);
uniform vec4 pink_dark : source_color = vec4(0.58, 0.14, 0.38, 1.0);
uniform vec4 yellow : source_color = vec4(1.0, 0.90, 0.20, 1.0);

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	vec4 base = texture(TEXTURE, UV);
	if (UV.y > cut_y && texture(cat_mask, UV).r < 0.5) discard;
	if (wave_cut < 900.0) {
		float px = floor(UV.x * 256.0);
		float w = wave_cut + 3.0 + 3.0 * sin(px * 0.31) + 2.0 * sin(px * 0.13 + 1.7);
		if (UV.y * 256.0 > w && texture(cat_mask, UV).r < 0.5) discard;
	}
	COLOR = base;
	if (base.a > 0.0) {
		vec3 c = base.rgb;
		float mx = max(c.r, max(c.g, c.b));
		float mn = min(c.r, min(c.g, c.b));
		float sat = mx > 0.0 ? (mx - mn) / mx : 0.0;
		// ワニ（明るいピンク・黄色）以外 = 主人公の灰色・紫・黒
		vec2 pp = floor(UV / TEXTURE_PIXEL_SIZE);
		float wave = absorb_y + sin(pp.x * 0.35 + TIME * 3.0) * 0.012 + sin(pp.x * 0.13 - TIME * 1.7) * 0.01;
		if (texture(cat_mask, UV).r > 0.5 && UV.y > wave) {
			// 呑まれた部分：ワニの体と同じピンクのマーブル。縁は盛り上がって光る
			float m2 = sin(pp.x * 0.21 + pp.y * 0.33 + sin(pp.y * 0.17 + TIME) * 2.5);
			vec3 goo = m2 > 0.7 ? yellow.rgb : vec3(0.93, 0.36, 0.63);
			if (m2 < -0.75) goo = vec3(0.72, 0.21, 0.48);
			float d = (UV.y - wave) / TEXTURE_PIXEL_SIZE.y;
			// 呑み込む粘液の表面：太い明るい縁 → その下に濃い影の帯（主人公との境目をはっきり）
			if (d < 3.0) goo = vec3(1.0, 0.86, 0.95);
			else if (d < 5.0) goo = vec3(0.98, 0.55, 0.78);
			else if (d < 8.0) goo = vec3(0.45, 0.08, 0.30);
			COLOR = vec4(goo, base.a);
		} else if (texture(cat_mask, UV).r > 0.5 && UV.y > wave - 2.5 * TEXTURE_PIXEL_SIZE.y) {
			COLOR = vec4(base.rgb * 0.45, base.a);   // 沈みかけている影
		} else if (texture(cat_mask, UV).r > 0.5) {
			vec2 p = floor(UV / TEXTURE_PIXEL_SIZE);
			float n = noise(p / 6.0) * 0.7 + noise(p / 2.5) * 0.3;
			// 下に垂れていくように、上ほど少し汚れにくく
			float th = 1.0 - clamp(contamination, 0.0, 1.0) * 0.72;   // 汚れても主人公の形は読めるように上限を抑える
			if (n > th) {
				float lum = dot(c, vec3(0.30, 0.59, 0.11));
				float marble = sin(p.x * 0.33 + p.y * 0.62 + sin(p.y * 0.27 + TIME * 0.6) * 2.6);
				vec3 paint = marble > 0.6 ? yellow.rgb : pink.rgb;
				vec3 col = paint * (0.82 + 0.45 * lum);
				if (n < th + 0.04) col = pink_dark.rgb;        // 縁取り
				if (lum < 0.08) col = mix(c, pink_dark.rgb * 0.5, 0.45);   // 輪郭は暗く残す
				COLOR = vec4(col, base.a);
			}
		}
	}
}
