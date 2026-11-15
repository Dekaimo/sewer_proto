shader_type canvas_item;
// 磔の場面（ワニ・猫・粘液・ドーベルマン）をまとめて描いた画を、床を支点に行ごとにずらしてしならせる。
// 上へ行くほど大きく曲がり（2乗）、真ん中は少し遅れて付いてくる（lag）。ずらしは整数ピクセルでドット絵を崩さない。
uniform float bend = 0.0;       // 先端（高さ height_px）での横ずれ（px）
uniform float lag = 0.0;        // 真ん中の遅れ（px）
uniform float sink = 0.0;       // 先端の沈み込み（px）
uniform float floor_px = 460.0;
uniform float height_px = 400.0;
uniform vec2 tex_size = vec2(560.0, 480.0);

void fragment() {
	vec2 px = floor(UV * tex_size);
	float h = max((floor_px - px.y) / height_px, 0.0);
	float off = bend * h * h + lag * sin(3.14159 * clamp(h, 0.0, 1.0));
	float dy = sink * h * h;
	vec2 src = vec2(px.x - floor(off + 0.5), px.y + floor(dy + 0.5));
	if (src.x < 0.0 || src.x >= tex_size.x || src.y < 0.0 || src.y >= tex_size.y) {
		COLOR = vec4(0.0);
	} else {
		COLOR = texture(TEXTURE, (src + 0.5) / tex_size);
	}
}
