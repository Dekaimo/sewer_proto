shader_type canvas_item;
// 下水道の床：ペンキまみれのドロドロ床。ピクセル単位で量子化してドット絵になじませる。

uniform vec2 size = vec2(960.0, 110.0);
uniform float px = 1.0;   // 模様の1ドットの大きさ

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) { v += a * noise(p); p *= 2.0; a *= 0.5; }
	return v;
}

void fragment() {
	vec2 p = floor(UV * size / px) * px;
	float depth = p.y / size.y;                 // 0=奥 1=手前
	vec2 q = vec2(p.x / 60.0, p.y / (18.0 + 30.0 * depth));   // 奥ほど潰れて見える
	float flow = TIME * 0.03;
	float n = fbm(q + vec2(flow, 0.0));
	float m = fbm(q * 2.3 + vec2(3.1, -flow));

	vec3 base = mix(vec3(0.16, 0.17, 0.19), vec3(0.20, 0.21, 0.23), depth);
	// 床のペンキは古く濁った色にして、キャラより目立たないようにする
	vec3 pink = vec3(0.62, 0.24, 0.44);
	vec3 pink_dark = vec3(0.40, 0.15, 0.30);
	vec3 yellow = vec3(0.66, 0.57, 0.22);

	vec3 col = base;
	float puddle = smoothstep(0.50, 0.52, n);
	if (puddle > 0.5) {
		col = pink_dark;
		if (n > 0.55) col = pink;
		float swirl = sin(q.x * 9.0 + m * 9.0);
		if (n > 0.57 && swirl > 0.75) col = yellow;
		// てかり
		if (n > 0.6 && m > 0.7) col = vec3(0.80, 0.50, 0.66);
	} else if (n > 0.47) {
		col = mix(base, pink_dark, 0.35);   // 縁のにじみ
	}
	// 奥の境目を暗く
	col *= 0.75 + 0.25 * smoothstep(0.0, 0.25, depth);
	COLOR = vec4(col, 1.0);
}
