shader_type canvas_item;
// 抱きつき中の1枚絵（ワニ＋主人公）用。主人公の部分（彩度の低い灰色・紫）にだけ、
// 汚れ率 contamination に応じてマーブルのペンキを乗せる。ワニのピンクには触らない。

uniform float contamination = 0.0;
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
	COLOR = base;
	if (base.a > 0.0) {
		vec3 c = base.rgb;
		float mx = max(c.r, max(c.g, c.b));
		float mn = min(c.r, min(c.g, c.b));
		float sat = mx > 0.0 ? (mx - mn) / mx : 0.0;
		// ワニ（明るいピンク・黄色）以外 = 主人公の灰色・紫・黒
		// 主人公 = 灰色（低彩度）か、青〜紫（青が赤より強い）。ワニのピンク・濃い赤紫・黄色は赤が強いので除外される
		bool is_cat = (sat < 0.28 && mx > 0.12) || (c.b >= c.r && c.b > c.g && mx > 0.12);
		if (is_cat) {
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
