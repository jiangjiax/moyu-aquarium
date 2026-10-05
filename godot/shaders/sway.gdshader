shader_type canvas_item;
// 按像素行错位的摇摆：根部不动，越往上偏得越多，偏移量取整
// 比直接转 Sprite 好：旋转会把像素拧斜，这里每一行只是整格平移，网格永远是正的
// 贴图左右需要留出 amp 像素的空边（make_art.py 已经加了）

uniform vec2 tex_px = vec2(16.0, 32.0);
uniform float amp = 2.0;
uniform float speed = 0.7;
uniform float phase = 0.0;
uniform float wave = 0.10;       // 沿高度的波数：高的海草会像波浪一样扭

void fragment() {
	vec2 p = floor(UV * tex_px);
	float h = 1.0 - (p.y + 0.5) / tex_px.y;          // 根部 0，顶端 1
	float off = sin(TIME * speed + phase - p.y * wave) * amp * h * h;
	off = floor(off + 0.5);
	vec2 q = vec2(p.x - off, p.y);
	if (q.x < 0.0 || q.x >= tex_px.x) {
		discard;
	}
	COLOR = texture(TEXTURE, (q + 0.5) / tex_px);
}
