shader_type canvas_item;
// 粘液の幹を、なめらかにしならせる。行ごとに横へずらして描く（ドットは1px単位でずらすので崩れない）。
// 根元(t=0)は動かず、中ほど mid_off、上端 top_off（上半身と同じ）へ2次曲線でつなぐ。
uniform float v0 = 0.0;      // この絵の範囲（UVのy）の上端
uniform float v1 = 1.0;      // 下端
uniform float top_off = 0.0; // 上端のずれ（px）
uniform float mid_off = 0.0; // 中ほどのずれ（px、遅れて追いかける）
uniform float tex_w = 256.0;

void fragment() {
	float t = 1.0 - clamp((UV.y - v0) / max(v1 - v0, 1e-5), 0.0, 1.0);   // 0=根元 1=上端
	float off = 2.0 * (1.0 - t) * t * mid_off + t * t * top_off;
	off = floor(off + 0.5);
	vec2 uv = UV - vec2(off / tex_w, 0.0);
	COLOR = texture(TEXTURE, uv);
}
