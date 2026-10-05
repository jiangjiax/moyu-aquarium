shader_type canvas_item;
// 圆角裁切：圆外 discard = 真透明
// 可以只圆上角（贴屏幕底边时用），下面两角保持直角，看起来才像「长在屏幕上」

uniform float radius : hint_range(0.0, 64.0) = 18.0;
uniform float radius_bottom : hint_range(0.0, 64.0) = 0.0;
uniform vec2 rect_size = vec2(640.0, 160.0);

float sd_round_box(vec2 p, vec2 half_size, vec2 r) {
	vec2 q = abs(p) - half_size + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - min(r.x, r.y);
}

void fragment() {
	vec2 half_size = rect_size * 0.5;
	vec2 center = vec2(rect_size.x * 0.5, rect_size.y * 0.5);
	vec2 r = vec2(radius, radius);
	// UV 的 y 往上、往下各算一次，取两个圆角 SDF 的较小值
	float d_top = sd_round_box(vec2(UV.x, 1.0 - UV.y) * rect_size - center, half_size, r);
	float d_bot = sd_round_box(vec2(UV.x, UV.y) * rect_size - center, half_size,
		vec2(radius, radius_bottom));
	if (max(d_top, d_bot) > 0.0) {
		discard;
	}
	COLOR = texture(TEXTURE, UV);
}
