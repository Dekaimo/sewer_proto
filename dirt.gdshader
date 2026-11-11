shader_type canvas_item;
// キャラの汚れ。dirt_mask の赤 = ペンキの厚み（0〜1）。
// ・元絵の明暗を残して立体感を保つ（ベタ塗りにしない）
// ・輪郭線は暗いまま残す
// ・汚れの縁は濃い色で縁取り、厚いところはてかる

uniform sampler2D dirt_mask : filter_nearest;
uniform vec4 pink : source_color = vec4(1.0, 0.30, 0.66, 1.0);
uniform vec4 pink_dark : source_color = vec4(0.58, 0.14, 0.38, 1.0);
uniform vec4 yellow : source_color = vec4(1.0, 0.90, 0.20, 1.0);

void fragment() {
	vec4 base = texture(TEXTURE, UV);
	float m = texture(dirt_mask, UV).r;
	if (m < 0.05 || base.a == 0.0) {
		COLOR = base;
	} else {
		vec2 px = TEXTURE_PIXEL_SIZE;
		vec2 p = floor(UV / px);
		float lum = dot(base.rgb, vec3(0.30, 0.59, 0.11));
		// マーブル（ピクセル単位でゆっくり流れる）
		float marble = sin(p.x * 0.33 + p.y * 0.62 + sin(p.y * 0.27 + p.x * 0.11 + TIME * 0.6) * 2.6);
		vec3 paint = marble > 0.6 ? yellow.rgb : pink.rgb;
		if (marble < -0.8) paint = mix(pink.rgb, pink_dark.rgb, 0.5);
		// 元絵の明暗で塗り分けて、体の丸みを残す
		vec3 col = paint * (0.82 + 0.45 * lum);   // 彩度高め（ペンキが主役）
		// 汚れの縁（となりが汚れていない）は濃い色で縁取る
		float mn = min(
			min(texture(dirt_mask, UV + vec2(px.x, 0.0)).r, texture(dirt_mask, UV - vec2(px.x, 0.0)).r),
			min(texture(dirt_mask, UV + vec2(0.0, px.y)).r, texture(dirt_mask, UV - vec2(0.0, px.y)).r));
		if (mn < 0.05) col = pink_dark.rgb * (0.95 + 0.4 * lum);
		// 厚いところは元絵の明るい部分がてかりになる
		if (m > 0.75 && lum > 0.37 && mn >= 0.05 && marble > 0.2 && marble < 0.6) col = mix(col, vec3(1.0, 0.86, 0.94), 0.55);
		// 輪郭線（暗い画素）は暗いまま残す
		if (lum < 0.08) col = mix(base.rgb, pink_dark.rgb * 0.5, 0.45);
		// 薄い汚れは下地が透ける
		col = mix(base.rgb, col, clamp(0.6 + m, 0.0, 1.0));
		COLOR = vec4(col, base.a);
	}
}
