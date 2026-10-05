class_name Art
extends RefCounted
## 像素美术生成器
##
## 两条规则撑起所有"精细感"：
##   1. 所有东西都有 1px 暗色描边 —— 没有描边就是剪纸，不是像素画
##   2. 物体内部有 3 阶明暗（顶亮 / 中间本色 / 底暗），鱼再加腹部反荫
##
## 所有精灵都在小分辨率上画（1 像素 = 1 美术像素），再用最近邻整数倍放大。


# ================================================================= 通用

## 把 0/1/2 掩码渲染成带描边和明暗的图
## rows: 每行若干 [x0, x1, region]，region 1=本体 2=鳍
static func _render_mask(w: int, h: int, rows: Array, cuts: Array,
		body_col: Array, fin_col: Array, outline: Color) -> Array:
	var mask := PackedByteArray()
	mask.resize(w * h)
	for y in h:
		for x in w:
			mask[y * w + x] = 0
	for y in mini(rows.size(), h):
		for span in rows[y]:
			var x0: int = maxi(0, int(span[0]))
			var x1: int = mini(w - 1, int(span[1]))
			var reg: int = int(span[2]) if span.size() > 2 else 1
			for x in range(x0, x1 + 1):
				mask[y * w + x] = reg
	for c in cuts:
		var cx := int(c[0])
		var cy := int(c[1])
		if cx >= 0 and cx < w and cy >= 0 and cy < h:
			mask[cy * w + cx] = 0

	# 本体上下边界，用来算明暗
	var top := h
	var bot := -1
	for y in h:
		for x in w:
			if mask[y * w + x] == 1:
				top = mini(top, y)
				bot = maxi(bot, y)
	if bot <= top:
		bot = top + 1
	var span_y := float(bot - top)

	# 输出图比掩码四周各留 1px 给描边
	var img := Image.create(w + 2, h + 2, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var at := func(x: int, y: int) -> int:
		if x < 0 or x >= w or y < 0 or y >= h:
			return 0
		return mask[y * w + x]

	for y in h:
		for x in w:
			var r: int = at.call(x, y)
			if r != 0:
				# 本体：按上下位置取明暗档
				var c: Color
				if r == 1:
					var ty := float(y - top) / span_y
					if ty < 0.26:
						c = body_col[0]      # 顶亮
					elif ty < 0.74:
						c = body_col[1]      # 本色
					elif ty < 0.88:
						c = body_col[2]      # 底暗
					else:
						c = body_col[3]      # 腹部反荫（比本色浅）
				else:
					c = fin_col[0] if fin_col.size() < 2 else fin_col[1]
				img.set_pixel(x + 1, y + 1, c)
			else:
				# 空：四邻有实体就描边
				if at.call(x - 1, y) != 0 or at.call(x + 1, y) != 0 \
						or at.call(x, y - 1) != 0 or at.call(x, y + 1) != 0:
					img.set_pixel(x + 1, y + 1, outline)
	return [img, mask]


# ================================================================= 鱼

## spec:
##   w, h    画布尺寸
##   rows    每行 [[x0,x1,region], ...]
##   cuts    要挖掉的格子
##   bands   竖条纹 [[x0,x1], ...]
##   spots   圆斑 [[x,y,r], ...]
##   eye     [x, y, r]
static func fish(spec: Dictionary, pal: Dictionary) -> ImageTexture:
	var w: int = spec["w"]
	var h: int = spec["h"]
	var outline: Color = pal["outline"]
	var res := _render_mask(w, h, spec["rows"], spec.get("cuts", []),
		pal["body"], pal["fin"], outline)
	var img: Image = res[0]
	var mask: PackedByteArray = res[1]

	# 只有【本体格】才能上色。描边格 alpha 也是非零的，
	# 直接判 alpha 会把条纹涂到轮廓外面去。
	var is_body := func(x: int, y: int) -> bool:
		if x < 0 or y < 0 or x >= w or y >= h:
			return false
		return mask[y * w + x] != 0

	# 竖条纹（ clownfish 的白带）
	if spec.has("bands"):
		for b in spec["bands"]:
			var bx0 := int(b[0])
			var bx1 := int(b[1])
			var band_c: Color = pal["band"]
			for x in range(bx0, bx1 + 1):
				for y in h:
					if is_body.call(x, y):
						img.set_pixel(x + 1, y + 1, band_c)
			# 条纹两侧压一道暗边。用比轮廓稍浅的暗色，纯黑会把鱼压成一道黑杠
			var edge: Color = pal.get("band_edge", outline)
			for x in [bx0 - 1, bx1 + 1]:
				for y in h:
					if is_body.call(x, y):
						img.set_pixel(x + 1, y + 1, edge)

	# 圆斑
	if spec.has("spots"):
		for s in spec["spots"]:
			var sx := int(s[0])
			var sy := int(s[1])
			var sr := int(s[2])
			for dy in range(-sr, sr + 1):
				for dx in range(-sr, sr + 1):
					if dx * dx + dy * dy <= sr * sr:
						if is_body.call(sx + dx, sy + dy):
							img.set_pixel(sx + dx + 1, sy + dy + 1, pal["band"])

	# 眼睛：小黑瞳 + 一颗白高光，就这两点，多了就变熊猫
	if spec.has("eye"):
		var e: Array = spec["eye"]
		var ex := int(e[0])
		var ey := int(e[1])
		for dy in [-1, 0]:
			for dx in [-1, 0]:
				if is_body.call(ex + dx, ey + dy):
					img.set_pixel(ex + dx + 1, ey + dy + 1, pal["eye"])
		if is_body.call(ex - 1, ey - 1):
			img.set_pixel(ex, ey, Color(1, 1, 1, 0.95))

	return ImageTexture.create_from_image(img)


# ================================================================= 装饰

## 用字符画谱造一个带描边和明暗的精灵
## rows: 字符串数组，字符经 colors 映射（未映射 = 透明）
static func deco(rows: Array, colors: Dictionary, outline: Color,
		shade_top: float = 0.30, shade_bot: float = -0.26) -> ImageTexture:
	var h := rows.size()
	var w: int = (rows[0] as String).length()
	var mask := PackedByteArray()
	mask.resize(w * h)
	for y in h:
		var row: String = rows[y]
		for x in w:
			mask[y * w + x] = 1 if colors.has(row[x]) else 0

	var top := h
	var bot := -1
	for y in h:
		for x in w:
			if mask[y * w + x] == 1:
				top = mini(top, y)
				bot = maxi(bot, y)
	if bot <= top:
		bot = top + 1
	var span_y := float(bot - top)

	var img := Image.create(w + 2, h + 2, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var at := func(x: int, y: int) -> int:
		if x < 0 or x >= w or y < 0 or y >= h:
			return 0
		return mask[y * w + x]

	for y in h:
		for x in w:
			if mask[y * w + x] == 1:
				var t := float(y - top) / span_y
				var k := 0.0
				if t < 0.3:
					k = shade_top * (1.0 - t / 0.3)
				elif t > 0.7:
					k = shade_bot * ((t - 0.7) / 0.3)
				var c: Color = colors[rows[y][x]]
				img.set_pixel(x + 1, y + 1, Color(
					clampf(c.r + k, 0, 1), clampf(c.g + k, 0, 1), clampf(c.b + k, 0, 1)))
			else:
				if at.call(x - 1, y) != 0 or at.call(x + 1, y) != 0 \
						or at.call(x, y - 1) != 0 or at.call(x, y + 1) != 0:
					img.set_pixel(x + 1, y + 1, outline)
	return ImageTexture.create_from_image(img)


# ================================================================= 素材

## 细沙：双色抖动，出颗粒感
static func sand(w: int, h: int, c1: Color, c2: Color) -> ImageTexture:
	# 一格就是 1 个美术像素，交给调用方整数倍放大，抖动颗粒才看得见
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var bayer := [
		[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]
	]
	for y in h:
		for x in w:
			var b: int = bayer[y % 4][x % 4]
			# 越往下越暗，像沙子的阴影
			var k := -0.16 * (float(y) / float(maxi(h - 1, 1)))
			var c := c1 if b < 8 else c2
			img.set_pixel(x, y, Color(
				clampf(c.r + k, 0, 1), clampf(c.g + k, 0, 1), clampf(c.b + k, 0, 1)))
	return ImageTexture.create_from_image(img)


## 气泡
static func bubble(r: int) -> ImageTexture:
	var d := r * 2 + 1
	var img := Image.create(d, d, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in d:
		for x in d:
			var dx := float(x - r)
			var dy := float(y - r)
			var dist := sqrt(dx * dx + dy * dy)
			if dist <= float(r) - 0.4 and dist >= float(r) - 1.4:
				img.set_pixel(x, y, Color(0.85, 0.97, 1.0, 0.55))
	img.set_pixel(r - 1, r - 1, Color(1, 1, 1, 0.9))
	return ImageTexture.create_from_image(img)


## 纵向色带渐变（像素风不插值）
static func gradient(stops: Array) -> ImageTexture:
	var n: int = stops.size()
	var img := Image.create(1, n, false, Image.FORMAT_RGBA8)
	for y in n:
		var f := float(y) / float(n - 1) * float(n - 1)
		var i0 := int(floor(f))
		var i1 := mini(i0 + 1, n - 1)
		img.set_pixel(0, y, (stops[i0] as Color).lerp(stops[i1] as Color, f - float(i0)))
	return ImageTexture.create_from_image(img)


## 横向铺满 w、从 y 开始高 h 的渐变矩形
static func grad_rect(w: float, y: float, h: float, stops: Array) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = gradient(stops)
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	s.centered = false
	s.position = Vector2(0, y)
	# 贴图是 1×N，scale 是倍率，所以要除以 N
	s.scale = Vector2(w, h / float(stops.size()))
	return s


static func quad(w: float, y: float, h: float, c: Color) -> Polygon2D:
	var p := Polygon2D.new()
	p.polygon = PackedVector2Array([
		Vector2(0, y), Vector2(w, y), Vector2(w, y + h), Vector2(0, y + h)])
	p.color = c
	return p


static func sprite(tex: Texture2D, pos: Vector2, scale_px: int) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = tex
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	s.position = pos
	# 整数倍缩放，像素才不会被拉变形
	s.scale = Vector2(scale_px, scale_px)
	return s


## 站在地面上的精灵：pos_y 是【底边】而不是中心。
## 装饰如果按中心摆，一半会埋进沙子里。
## offset 负半高 = 把精灵原点挪到底边，这样摇曳是绕着根部转，不会整株平移。
static func standing(tex: Texture2D, base_y: float, scale_px: int) -> Sprite2D:
	var s := sprite(tex, Vector2(0, base_y), scale_px)
	s.offset = Vector2(0, -tex.get_height() * 0.5)
	return s
