shader_type canvas_item;
// 磔のワニの上半身：上の方だけ右へずらす（行ずらし、整数ドット）。
// スプライト自体を shift_px 右へ置き、腰に近い行ほど元の位置へ戻す。y_full より上は全部ずれ、y_zero（腰）でずれ 0。
uniform float shift_px = 0.0;
uniform float y_full = 110.0;
uniform float y_zero = 190.0;
uniform vec2 tex_size = vec2(256.0, 256.0);

void fragment() {
	float py = floor(UV.y * tex_size.y);
	float w = clamp((y_zero - py) / max(y_zero - y_full, 1.0), 0.0, 1.0);
	float back = floor(shift_px * (1.0 - w) + 0.5);
	float u = UV.x + back / tex_size.x;
	vec4 c = texture(TEXTURE, vec2(u, UV.y));
	if (u > 1.0) { c.a = 0.0; }
	COLOR = c;
}
