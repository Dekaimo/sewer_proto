shader_type canvas_item;
// 地中のもがき（生成したドット絵）を床のペンキになじませる。
// ・黒っぽい輪郭線は、床のドロドロの暗いピンクに置き換える（線をくっきりさせない）
// ・絵の下のほう（水たまり部分）は市松模様で抜いて、床のペンキに溶け込ませる
// ・全体の出方（appear）も市松で抜く：にじむように現れて、にじむように消える

uniform float fade_top = 0.76;   // この高さ（UVのy）から下を薄くしはじめる
uniform float fade_bot = 0.83;   // ここで完全に消える
uniform float appear = 1.0;

float bayer4(vec2 p) {
	int x = int(mod(p.x, 4.0));
	int y = int(mod(p.y, 4.0));
	int i = x + y * 4;
	float m[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return (m[i] + 0.5) / 16.0;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	if (c.a < 0.01) discard;
	float lum = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	// 生成のノイズ（灰色のもや）は消す
	float mx = max(c.r, max(c.g, c.b));
	float mn = min(c.r, min(c.g, c.b));
	if (mx - mn < 0.10 && lum > 0.22) discard;
	// 輪郭線（とても暗いピクセル）は床の暗いピンクへ
	if (lum < 0.13) c.rgb = mix(vec3(0.42, 0.10, 0.30), c.rgb, 0.25);
	vec2 px = floor(UV / TEXTURE_PIXEL_SIZE);
	float k = 1.0 - smoothstep(fade_top, fade_bot, UV.y);
	k *= appear;
	if (k < bayer4(px)) discard;
	COLOR = c;
}
