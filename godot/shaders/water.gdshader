shader_type canvas_item;
// 水体：分档色带 + Bayer 抖动过渡 + 缓慢移动的斜光柱
// 挂在一个铺满整个世界的 ColorRect 上，UV * rect_px = 世界像素坐标，天然对齐像素网格

uniform vec2 rect_px = vec2(1008.0, 160.0);
uniform vec4 c_surface : source_color = vec4(0.56, 0.80, 0.79, 1.0);
uniform vec4 c_upper : source_color = vec4(0.40, 0.70, 0.73, 1.0);
uniform vec4 c_mid : source_color = vec4(0.29, 0.60, 0.68, 1.0);
uniform vec4 c_deep : source_color = vec4(0.22, 0.49, 0.59, 1.0);
// 各色停在哪个高度（0 = 顶，1 = 底）
uniform vec3 stops = vec3(0.35, 0.62, 1.0);
uniform float bands = 14.0;          // 色带档数，档越少越「像素」
uniform float ray_strength = 0.07;
uniform float time_scale = 1.0;

float bayer4(vec2 p) {
	int x = int(mod(p.x, 4.0));
	int y = int(mod(p.y, 4.0));
	int m[16] = int[](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[y * 4 + x]) + 0.5) / 16.0;
}

vec3 water(float t) {
	if (t < stops.x) return mix(c_surface.rgb, c_upper.rgb, t / stops.x);
	if (t < stops.y) return mix(c_upper.rgb, c_mid.rgb, (t - stops.x) / (stops.y - stops.x));
	return mix(c_mid.rgb, c_deep.rgb, (t - stops.y) / (stops.z - stops.y));
}

void fragment() {
	vec2 p = floor(UV * rect_px);
	float t = p.y / rect_px.y;
	// 先量化到 bands 档，再用抖动决定落在上一档还是下一档
	float f = t * bands;
	float lo = floor(f);
	float q = (f - lo) > bayer4(p) ? lo + 1.0 : lo;
	vec3 col = water(clamp(q / bands, 0.0, 1.0));

	// 斜光柱：两组不同周期的正弦叠加，慢慢漂移，越往下越淡
	float tm = TIME * time_scale;
	float s = p.x + p.y * 0.45;
	float ray = sin(s * 0.021 + tm * 0.07) * 0.6 + sin(s * 0.047 - tm * 0.05 + 1.7) * 0.4;
	ray = smoothstep(0.55, 0.95, ray) * (1.0 - t * 0.85);
	// 光柱也只取两档 + 抖动，保持像素感
	float r = ray * 2.0;
	float rl = floor(r);
	r = (r - rl) > bayer4(p + vec2(2.0, 1.0)) ? rl + 1.0 : rl;
	col += vec3(0.85, 1.0, 0.95) * ray_strength * r;

	COLOR = vec4(col, 1.0);
}
