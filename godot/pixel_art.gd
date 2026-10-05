class_name PixelArt
extends RefCounted
## 玩法图标：金币、饵料，外加界面的九宫格框。
##
## 场景美术（鱼、珊瑚、水草）是 tools/ 的 Python 管线出的 PNG；这几个是几像素的
## 小东西，为它跑一遍生成管线不划算，就在这里用 Image 直接画。
## 画法还是像素画：一个格子一个像素，不抗锯齿。

static func _blank(w: int, h: int) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	return img


static func _px(img: Image, x: int, y: int, col: Color) -> void:
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, col)


## 在逻辑像素 (x, y) 上落一个 s × s 的方块，界面框按界面倍率放大时用
static func _block(img: Image, x: int, y: int, s: int, col: Color) -> void:
	for dy in s:
		for dx in s:
			_px(img, x * s + dx, y * s + dy, col)


static func _rect(img: Image, x: int, y: int, w: int, h: int, col: Color) -> void:
	for dy in h:
		for dx in w:
			_px(img, x + dx, y + dy, col)


static func _disc(img: Image, c: Vector2, r: float, col: Color) -> void:
	for y in img.get_height():
		for x in img.get_width():
			if Vector2(x + 0.5, y + 0.5).distance_to(c) <= r:
				_px(img, x, y, col)


## 一枚金币：外圈压深，币面提亮，左上留两点高光
static func coin() -> ImageTexture:
	var img := _blank(11, 11)
	var c := Vector2(5.5, 5.5)
	_disc(img, c, 5.0, Color(0.38, 0.24, 0.05))
	_disc(img, c, 4.0, Color(0.99, 0.79, 0.26))
	_disc(img, c, 2.0, Color(1.0, 0.94, 0.64))
	_px(img, 3, 3, Color(1, 1, 0.95))
	_px(img, 4, 3, Color(1, 1, 0.95))
	return ImageTexture.create_from_image(img)


## 饵料：三粒深棕小球，边缘一圈更深的轮廓
static func pellet() -> ImageTexture:
	var img := _blank(4, 4)
	_px(img, 1, 0, Color(0.72, 0.45, 0.20))
	_rect(img, 0, 1, 4, 2, Color(0.34, 0.20, 0.09))
	_px(img, 1, 1, Color(0.85, 0.58, 0.28))
	_px(img, 3, 1, Color(0.62, 0.38, 0.17))
	_px(img, 1, 3, Color(0.62, 0.38, 0.17))
	_px(img, 2, 3, Color(0.34, 0.20, 0.09))
	return ImageTexture.create_from_image(img)


## 界面用的九宫格框：阶梯切角 + 一像素描边 + 上沿一道高光、下沿一道压暗。
## notch 是切角级数（1 = 只切掉角上一格），s 是界面倍率，直接画成放大后的图，
## StyleBoxTexture 的边距按 1:1 贴，不会被拉糊。
static func box(fill: Color, border: Color, notch: int, s: int) -> ImageTexture:
	var m := notch + 2
	var n := m * 2 + 1
	var inside := func(x: int, y: int) -> bool:
		if x < 0 or y < 0 or x >= n or y >= n:
			return false
		return mini(x, n - 1 - x) + mini(y, n - 1 - y) >= notch
	var edge := func(x: int, y: int) -> bool:
		return inside.call(x, y) and not (inside.call(x - 1, y) and inside.call(x + 1, y)
			and inside.call(x, y - 1) and inside.call(x, y + 1))
	var hi := fill.lightened(0.16)
	var lo := fill.darkened(0.30)
	var img := _blank(n * s, n * s)
	for y in n:
		for x in n:
			if not inside.call(x, y):
				continue
			var col := fill
			if edge.call(x, y):
				col = border
			elif edge.call(x, y - 1):
				col = hi
			elif edge.call(x, y + 1):
				col = lo
			_block(img, x, y, s, col)
	return ImageTexture.create_from_image(img)
