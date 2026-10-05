class_name Ui
extends RefCounted
## 界面零件：字体、面板、按钮。商店和 HUD 共用一套，看起来才像同一个东西。
##
## 全部走像素风，和缸里的鱼、珊瑚是一路的：
##   字体  缝合像素体 12px（fonts/，OFL-1.1）。只在 12 的整数倍上用，
##         fixed_size + 整数倍缩放，一个字形像素永远是 PX × PX 的方块，不抗锯齿。
##   面板  PixelArt.box() 画的九宫格：阶梯切角 + 一像素描边 + 上沿高光 / 下沿压暗。
##
## PX = 界面 1 像素占几个物理像素。Retina 下是 2，字就是 24 物理像素高。
## 界面不跟缸共用倍率：挂件缸是 3、展开缸是 6，界面要是跟着 6 走，商店一行放不下几个字。
## 界面自己保持一套倍率，所有零件都是它的整数倍，看起来就还是一张像素图。
##
## 注意：Godot 4.7 的 Font 上没有 font_size 属性，字号由消费方给——
## Theme.default_font_size 或 add_theme_font_size_override("font_size", n)。

const INK := Color(0.97, 0.96, 0.91)
const DIM := Color(0.66, 0.74, 0.77)
const GOLD := Color(1.0, 0.84, 0.42)
const LINE := Color(0.34, 0.55, 0.60)
const DEEP := Color(0.07, 0.13, 0.17, 0.92)
const SHADOW := Color(0.02, 0.05, 0.08, 0.85)

const FONT_BASE := 12        # 字体的原生像素高，字号只用它的整数倍

static var PX := 2
static var _font: FontFile


## main.gd 在一开始按屏幕缩放定一次。1x 屏就是 1，字 12 像素，正好是字体原生大小
static func setup(dpi: float) -> void:
	PX = maxi(1, roundi(dpi))


## 字号：n 倍字体原生高度。Ui.fs(1) = 正文，Ui.fs(2) = 大字
static func fs(n: int = 1) -> int:
	return FONT_BASE * PX * n


static func font() -> FontFile:
	if _font == null:
		_font = load("res://fonts/fusion-pixel-12px-zh_hans.woff2") as FontFile
		# 像素字：不抗锯齿、不 hinting、不做亚像素定位，只按 12 的整数倍放大
		_font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		_font.hinting = TextServer.HINTING_NONE
		_font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
		_font.fixed_size = FONT_BASE
		_font.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_INTEGER_ONLY
		_font.generate_mipmaps = false
		# 像素字库没收的字（生僻字、emoji）退到系统字体，至少不是豆腐块
		var fb := SystemFont.new()
		fb.font_names = PackedStringArray(["PingFang SC", "Hiragino Sans GB", "sans-serif"])
		fb.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		_font.fallbacks = [fb]
	return _font


static func theme_for() -> Theme:
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = fs(1)
	return t


## 九宫格像素框。notch 是切角级数，pad 是内容内边距（界面像素）
static func box(bg: Color, border: Color, notch: int = 1,
		pad := Vector2i(5, 3)) -> StyleBoxTexture:
	var s := StyleBoxTexture.new()
	var m := notch + 2
	s.texture = PixelArt.box(bg, border, notch, PX)
	s.set_texture_margin_all(m * PX)
	s.content_margin_left = pad.x * PX
	s.content_margin_right = pad.x * PX
	s.content_margin_top = pad.y * PX
	s.content_margin_bottom = pad.y * PX
	return s


static func panel() -> StyleBoxTexture:
	return box(DEEP, LINE, 2, Vector2i(8, 7))


static func make_button(text: String, w: int = 40) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w * PX, 18 * PX)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_stylebox_override("normal", box(Color(0.13, 0.26, 0.32, 0.95), LINE))
	b.add_theme_stylebox_override("hover", box(Color(0.20, 0.40, 0.46, 0.98), Color(0.45, 0.82, 0.86)))
	# 按下去字往下沉一个像素，像真的按钮
	var down := box(Color(0.09, 0.19, 0.24, 0.98), LINE)
	down.content_margin_top += PX
	down.content_margin_bottom -= PX
	b.add_theme_stylebox_override("pressed", down)
	b.add_theme_stylebox_override("disabled", box(Color(0.09, 0.12, 0.15, 0.6), Color(0.22, 0.28, 0.32, 0.7)))
	b.add_theme_color_override("font_color", INK)
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	b.add_theme_color_override("font_pressed_color", GOLD)
	b.add_theme_color_override("font_disabled_color", Color(0.45, 0.50, 0.54))
	b.add_theme_font_size_override("font_size", fs(1))
	return b


## size 是字体原生高度的倍数：1 正文，2 大字
static func label(text: String, size: int = 1, col: Color = INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", col)
	l.add_theme_font_size_override("font_size", fs(size))
	return l


## 给字压一道硬阴影（右下各一像素）。像素字不用描边，描边在整数倍缩放下会糊
static func shadow(l: Label) -> Label:
	l.add_theme_color_override("font_shadow_color", SHADOW)
	l.add_theme_constant_override("shadow_offset_x", PX)
	l.add_theme_constant_override("shadow_offset_y", PX)
	l.add_theme_constant_override("shadow_outline_size", 0)
	return l


static func hline() -> Control:
	var c := ColorRect.new()
	c.color = Color(LINE.r, LINE.g, LINE.b, 0.55)
	c.custom_minimum_size = Vector2(0, PX)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c
