shader_type canvas_item;
// 把整块缸（玻璃框 + 水 + 鱼）一起裁出阶梯圆角。
// 不用九宫格去「贴」圆角——那样只圆了边框，四角里的水还是方的。
// 按美术像素（cell 个物理像素一格）整格地裁，不留软边：
// 切角的台阶和 frame.png 上沿的台阶是同一份（每行从外往里空 3、2、1、1 格），
// 四个角都这么切，外轮廓就是一圈干净的像素台阶。

uniform vec2 rect_size = vec2(100.0, 100.0);
uniform float cell = 3.0;

const int CUT[4] = int[](3, 2, 1, 1);

void fragment() {
	vec2 grid = floor(rect_size / cell);
	vec2 c = floor(UV * rect_size / cell);
	int ex = int(min(c.x, grid.x - 1.0 - c.x));
	int ey = int(min(c.y, grid.y - 1.0 - c.y));
	if (ey < 4 && ex < CUT[ey]) {
		COLOR.a = 0.0;
	}
}
