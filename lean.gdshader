shader_type canvas_item;
// 磔の下半身：上ほど大きく横にずらして、傾いた上半身についていく（下の水たまりは動かない）
uniform float lean_px = 0.0;
uniform float top_v = 0.06;    // ずれが最大になる高さ（UV）
uniform float foot_v = 0.87;   // ここから下は動かない
uniform float appear = 1.0;

float bayer4(vec2 p) {
	int x = int(mod(p.x, 4.0));
	int y = int(mod(p.y, 4.0));
	float m[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return (m[x + y * 4] + 0.5) / 16.0;
}

void fragment() {
	float k = clamp((foot_v - UV.y) / (foot_v - top_v), 0.0, 1.0);
	float sh = floor(lean_px * k * k + 0.5);
	vec2 uv = UV - vec2(sh * TEXTURE_PIXEL_SIZE.x, 0.0);
	vec4 c = texture(TEXTURE, uv);
	if (c.a < 0.01) discard;
	if (appear < bayer4(floor(UV / TEXTURE_PIXEL_SIZE))) discard;
	COLOR = c;
}
