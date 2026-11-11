shader_type canvas_item;

// 汚れマスク（白=汚れ）。攻撃が当たった場所が白く塗られていく
uniform sampler2D dirt_mask : filter_nearest;
uniform vec4 pink : source_color = vec4(0.93, 0.33, 0.62, 1.0);
uniform vec4 pink_dark : source_color = vec4(0.72, 0.20, 0.47, 1.0);
uniform vec4 yellow : source_color = vec4(0.98, 0.85, 0.30, 1.0);

void fragment() {
	vec4 base = texture(TEXTURE, UV);
	float m = texture(dirt_mask, UV).r;
	// マーブル模様（ゆっくり流れる）
	float marble = sin(UV.x * 7.0 + UV.y * 15.0 + sin(UV.y * 9.0 + TIME * 0.8) * 2.2);
	vec4 paint = marble > 0.6 ? yellow : (marble < -0.7 ? pink_dark : pink);
	float a = step(0.2, m);
	COLOR = vec4(mix(base.rgb, paint.rgb, a), base.a);
}
