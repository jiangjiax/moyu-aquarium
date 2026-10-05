shader_type canvas_item;
render_mode blend_add;
// 沙面焦散：两层扭曲网格取最小值 = 水波折射出的亮纹，只在沙层上方几行出现
// 叠加混合，只提亮不压暗

uniform vec2 rect_px = vec2(1008.0, 14.0);
uniform vec4 tint : source_color = vec4(1.0, 0.97, 0.82, 1.0);
uniform float strength = 0.16;
uniform float time_scale = 1.0;

float cell(vec2 p, float tm) {
	vec2 q = p + vec2(sin(p.y * 0.9 + tm), cos(p.x * 0.7 - tm * 0.8)) * 0.6;
	vec2 g = abs(fract(q) - 0.5);
	return min(g.x, g.y);
}

void fragment() {
	vec2 p = floor(UV * rect_px);
	float tm = TIME * time_scale * 0.35;
	// 横向拉长，贴合斜视沙面的透视
	vec2 u = vec2(p.x / 9.0, p.y / 3.2);
	float c = min(cell(u, tm), cell(u * 1.37 + 3.1, -tm * 1.2));
	float line = step(c, 0.075);
	// 沙面往下逐渐看不见
	float fade = 1.0 - smoothstep(0.1, 0.9, UV.y);
	COLOR = vec4(tint.rgb * strength * line * fade, 1.0);
}
