extends Node2D
## 摸鱼水族馆 M2：钱能赚了
##
## 渲染：整缸先画进一个【美术像素分辨率】的 SubViewport（1 格 = 1 像素），
## 再按整数倍放大贴到窗口上。光效、粒子、摇摆都在这张小图上算，永远对齐像素网格。
##
## 形态：
##   挂件  整屏宽（一屏 = 一个展区），贴在屏幕底边。除了左上角的小按钮，整条都是
##         点击穿透的；鼠标移上来会自动变淡。每 20 秒镜头移到下一个展区。
##   展开  屏幕中间的大窗，像素放大一倍，能看到上层的水；右边是商店。
##         三个展区开局全开，左右拖动 / 触控板横滑就过去了。点水面投食、点金币收起来。
##         空格 / Esc 收起。
##   两种形态金币都是落到沙上一会儿自己进钱包。

const STRIP_ROWS := 80       # 挂件高度（美术像素）
const WORLD_ROWS := 150      # 世界总高度
const BASE := 6              # 底座厚度（在 y = 0 以下）
const EXPAND_RATIO := 0.72
const RIM := 3               # 缸顶玻璃唇边
const FADE_HOVER := 0.2
const TOUR_SEC := 20.0       # 挂件形态每隔多久换一个展区
const CLICK_SLOP := 7.0      # 按下到松开挪过几个物理像素以内算「点」，不算拖
const CLICK_TIME := 0.4

# 留白：四周都留一截，避开 Dock 和程序栏，缸边也不会贴着屏幕边
const MARGIN_X := 30         # 挂件形态左右各留这么多物理像素
const MARGIN_BOTTOM := 16    # 挂件形态离屏幕底边
const TAB_H := 46            # 挂件形态顶部给按钮留的一条（按钮挂在这条里，不在缸里）
const EXPAND_MARGIN := 30    # 展开形态四周留白
const ICON := 13              # 展开/收起图标的边长（美术像素，art/icon_*.png）

enum Mode { STRIP, EXPAND }

var mode: int = Mode.STRIP
var px_strip := 3            # 挂件形态 1 美术像素 = 几个物理像素
var px := 3
var btn_side := 45           # 挂耳边长（物理像素）= (图标 + 两边各 1 格) × px_strip
var zone_w := 1008.0         # 一个展区 = 一屏宽
var world_w := 3024.0

var vp: SubViewport
var tank: Tank
var cam: Camera2D
var frame: NinePatchRect
var display: TextureRect
var btn: Button
var round_mat: ShaderMaterial
var tex_expand: Texture2D
var tex_collapse: Texture2D
var shop: Shop

var coin_box: HBoxContainer
var coin_num: Label
var toast: Label

var fade := 1.0
var cam_left := 0.0
var cam_goal := 0.0
var tour_i := 0
var tour_t := 0.0
var dragging := false
var pressed := false
var press_pos := Vector2.ZERO
var press_t := 0.0
var save_t := 0.0
var toast_t := 0.0

var shot_path := ""
var shot_wait := 3.0
var shot_mode := "strip"
var _zone_arg := -1
var _coins_arg := -1.0
var _buy_arg := ""
var _usable := Rect2i()


## usable rect 用来躲 Dock 和菜单栏。以前一边用整屏位置一边用 usable 宽度，
## Dock 在左边时缸就被压在 Dock 底下了。
func _read_screen_rect() -> void:
	var s := DisplayServer.get_primary_screen()
	_usable = DisplayServer.screen_get_usable_rect(s)


func _ready() -> void:
	_parse_args()
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_TRANSPARENT, true)
	get_viewport().transparent_bg = true

	var boot := Save.load_file()
	_dev_args()
	var offline := Save.settle_offline()

	var dpi := DisplayServer.screen_get_scale(DisplayServer.get_primary_screen())
	# Retina 2x 下 3 物理像素一格（1.5pt）：比 2 细腻，比 4 不占地方
	px_strip = maxi(2, roundi(1.5 * dpi))
	btn_side = (ICON + 2) * px_strip
	Ui.setup(dpi)
	_read_screen_rect()
	if _usable.size.x <= 0:
		# headless 下拿不到屏幕，给个 MacBook 的宽度兜底
		_usable = Rect2i(0, 0, 3024, 1900)
	# 展区宽 = 去掉左右留白、Dock 之后能放下多少整格。取整到整格，右边缘就不会
	# 多出一截下一区的阴影——以前就是这里多露了 60 多格，看着像挂了块黑门板。
	zone_w = float(maxi(64, floori(float(_usable.size.x - 2 * MARGIN_X) / float(px_strip))))
	world_w = zone_w * Tank.ZONE_COUNT

	vp = SubViewport.new()
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	vp.snap_2d_transforms_to_pixel = true
	vp.snap_2d_vertices_to_pixel = true
	add_child(vp)

	tank = Tank.new()
	vp.add_child(tank)
	tank.build(zone_w, WORLD_ROWS)
	tank.coins_changed.connect(_update_hud)
	tank.notice.connect(_toast)

	cam = Camera2D.new()
	cam.anchor_mode = Camera2D.ANCHOR_MODE_FIXED_TOP_LEFT
	vp.add_child(cam)
	cam.make_current()

	var layer := CanvasLayer.new()
	vp.add_child(layer)
	frame = NinePatchRect.new()
	frame.texture = load("res://art/frame.png")
	frame.patch_margin_left = 6
	frame.patch_margin_right = 6
	frame.patch_margin_top = 6
	frame.patch_margin_bottom = 6
	frame.draw_center = false
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(frame)

	display = TextureRect.new()
	display.texture = vp.get_texture()
	display.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	display.stretch_mode = TextureRect.STRETCH_SCALE
	display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 圆角裁在 display 上：玻璃框、水、鱼一起被裁，四角的水不会露成方的
	round_mat = ShaderMaterial.new()
	round_mat.shader = load("res://shaders/round.gdshader")
	display.material = round_mat
	add_child(display)

	_build_button()
	_build_hud()
	_build_shop()
	_update_hud()
	if bool(boot["fresh"]):
		_toast("点右上角展开，点水面投食、点金币收钱")
	elif int(offline["earned"]) > 0:
		_toast("你不在的 %s，赚了 %d 金币" % [_ago(float(offline["minutes"])),
			int(offline["earned"])])
	elif int(offline["minutes"]) >= 5.0:
		_toast("你不在的 %s，鱼自己游了一会儿" % _ago(float(offline["minutes"])))
	_apply_mode(shot_mode)
	if not shot_path.is_empty():
		_run_shot()


## 自检用：--coins=500 假装钱包里有这些钱
func _dev_args() -> void:
	if not shot_path.is_empty() or _coins_arg >= 0.0 or not _buy_arg.is_empty():
		Save.readonly = true          # 自检截图一律不落盘，别把玩家存档写脏
	if _coins_arg >= 0.0:
		Save.data["coins"] = _coins_arg
	if _zone_arg >= 0:
		tour_i = clampi(_zone_arg, 0, Tank.ZONE_COUNT - 1)


func _ago(minutes: float) -> String:
	if minutes < 60.0:
		return "%d 分钟" % int(minutes)
	return "%.1f 小时" % (minutes / 60.0)


func _parse_args() -> void:
	for a in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.split("=")
		if kv.size() < 2:
			continue
		match kv[0]:
			"--shot": shot_path = kv[1]
			"--wait": shot_wait = float(kv[1])
			"--mode": shot_mode = kv[1]
			"--zone": _zone_arg = int(kv[1])
			"--coins": _coins_arg = float(kv[1])
			"--buy": _buy_arg = kv[1]



func _build_button() -> void:
	tex_expand = load("res://art/icon_expand.png")
	tex_collapse = load("res://art/icon_collapse.png")
	var hud_layer := CanvasLayer.new()
	add_child(hud_layer)
	# 突出的一个小挂耳：浮在缸左上角外面，不挤在缸里面。底色比缸亮一点，
	# 鼠标移上去会发一下光，不然贴边底边的小方块根本注意不到。
	# 挂耳按缸的倍率画（px_strip），图标 13 格正好放大整数倍，和缸是同一套网格。
	btn = Button.new()
	btn.focus_mode = Control.FOCUS_NONE
	btn.icon = tex_expand
	btn.expand_icon = true
	btn.custom_minimum_size = Vector2(btn_side, btn_side)
	btn.add_theme_stylebox_override("normal", _btn_box(
		Color(0.16, 0.30, 0.36, 0.92), Color(0.40, 0.72, 0.78, 0.85)))
	btn.add_theme_stylebox_override("hover", _btn_box(
		Color(0.28, 0.52, 0.58, 0.98), Color(0.70, 0.95, 0.98, 1.0)))
	btn.add_theme_stylebox_override("pressed", _btn_box(
		Color(0.11, 0.22, 0.27, 0.98), Color(0.55, 0.85, 0.90, 0.9)))
	btn.pressed.connect(func(): _apply_mode("strip" if mode == Mode.EXPAND else "expand"))
	hud_layer.add_child(btn)


## 挂耳的底：像素框，内边距正好一格，图标撑满剩下的 13 × 13 格
func _btn_box(bg: Color, border: Color) -> StyleBoxTexture:
	var s := StyleBoxTexture.new()
	s.texture = PixelArt.box(bg, border, 1, px_strip)
	s.set_texture_margin_all(3 * px_strip)
	s.set_content_margin_all(px_strip)
	return s


## 钱包：两种形态都看得见。挂件形态也只能看这个数 —— 挂着的没人点金币
func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	coin_box = HBoxContainer.new()
	coin_box.add_theme_constant_override("separation", 3 * Ui.PX)
	coin_box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	coin_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	coin_box.grow_vertical = Control.GROW_DIRECTION_END
	coin_box.offset_right = -(MARGIN_X + 16)
	coin_box.offset_left = -(MARGIN_X + 160)
	coin_box.offset_top = TAB_H + 10
	coin_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(coin_box)

	var icon := TextureRect.new()
	icon.texture = PixelArt.coin()
	icon.custom_minimum_size = Vector2(11, 11) * Ui.PX    # 金币 11 格，整数倍放大
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	coin_box.add_child(icon)

	coin_num = Ui.shadow(Ui.label("0", 1, Ui.GOLD))
	coin_num.mouse_filter = Control.MOUSE_FILTER_IGNORE
	coin_box.add_child(coin_num)

	# 字色给实色，淡出只走 modulate。以前字色 alpha 是 0，只剩描边，提示成了一行灰字
	toast = Ui.shadow(Ui.label("", 1, Ui.INK))
	toast.modulate.a = 0.0
	toast.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	toast.grow_vertical = Control.GROW_DIRECTION_BEGIN
	toast.offset_left = -420
	toast.offset_right = 420
	toast.offset_top = -76
	toast.offset_bottom = -40
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(toast)


func _update_hud() -> void:
	if is_instance_valid(coin_num):
		coin_num.text = Catalog.money(Save.coins())
	if is_instance_valid(shop):
		shop.refresh()


func _toast(text: String) -> void:
	if not is_instance_valid(toast):
		return
	toast.text = text
	toast.modulate.a = 1.0
	toast_t = 4.0


## 商店只在展开形态出现。买完 / 解锁完由 shop.changed 收回来
func _build_shop() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	shop = Shop.new()
	shop.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	shop.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	shop.offset_right = -(EXPAND_MARGIN + 16)
	shop.offset_left = -(EXPAND_MARGIN + 16 + 160 * Ui.PX)
	shop.offset_top = EXPAND_MARGIN + 52
	shop.changed.connect(_on_shop_changed)
	shop.noticed.connect(_toast)
	shop.zone_picked.connect(_go_zone)
	layer.add_child(shop)


func _on_shop_changed(fish_id: String) -> void:
	if not fish_id.is_empty():
		var z := shop.zone_i
		if tank.zone_at(cam_goal + _view_w() * 0.5) != z:
			_go_zone(z)
		# 落点正对着看得见的那一截水的中间（商店挡住的右边不算）
		var left := clampf(cam_goal, 0.0, maxf(world_w - vp.size.x, 0.0))
		tank.add_fish(fish_id, z, left + _view_w() * 0.5)
		_toast("%s 跳进%s了" % [Catalog.find(fish_id).get("name", fish_id),
			Catalog.ZONE_NAME[z]])
	tank.sync_save()
	Save.flush()
	_update_hud()



# ---------------------------------------------------------------- 形态

func _apply_mode(next: String) -> void:
	_read_screen_rect()
	var usable := _usable
	var win: Vector2i
	var rows: int
	if next.begins_with("expand"):
		mode = Mode.EXPAND
		px = px_strip * 2
		rows = WORLD_ROWS
		# 四周留白后再居中，不贴屏幕边
		win = Vector2i(usable.size.x - 2 * EXPAND_MARGIN, rows * px)
		DisplayServer.window_set_size(win)
		DisplayServer.window_set_position(usable.position + (usable.size - win) / 2)
		vp.size = Vector2i(ceili(float(win.x) / px), rows)
		cam_goal = zone_w * float(tour_i)
		cam_left = clampf(cam_goal, 0.0, maxf(world_w - vp.size.x, 0.0))
		shop.zone_i = tour_i
		shop.refresh()        # 不刷新的话页签还停在上次那一区
		tour_t = 0.0
		tank.set_swim_area(BASE - WORLD_ROWS + RIM + 8.0, BASE - WORLD_ROWS + RIM + 1.0)
		btn.icon = tex_collapse
		Engine.max_fps = 60
		# 展开形态要能点、能拖：关掉穿透
		DisplayServer.window_set_mouse_passthrough(PackedVector2Array())
		shop.visible = true
		_toast("左右拖动去别的展区，点水面投食")
	else:
		mode = Mode.STRIP
		px = px_strip
		rows = STRIP_ROWS
		# 宽度扣掉 Dock 和菜单栏（usable），再留 MARGIN_X。
		# 位置也从 usable 起算，不然 Dock 在左边时缸会被压在 Dock 底下。
		win = Vector2i(int(zone_w) * px + 2 * MARGIN_X,
			TAB_H + rows * px + MARGIN_BOTTOM)
		DisplayServer.window_set_size(win)
		DisplayServer.window_set_position(Vector2i(usable.position.x + MARGIN_X,
			usable.position.y + usable.size.y - MARGIN_BOTTOM - win.y))
		# 挂件形态正好一屏 = 一个展区，镜头停在哪一区就看得见哪一区
		vp.size = Vector2i(int(zone_w), rows)
		# 收起时停在展开时看的那一区：tour_i 在滑动 / 点页签时已经跟着更新了
		cam_goal = zone_w * float(tour_i)
		cam_left = cam_goal
		tank.set_swim_area(BASE - STRIP_ROWS + RIM + 4.0, BASE - STRIP_ROWS + RIM + 1.0)
		btn.icon = tex_expand
		shop.visible = false
		# 挂着看一天，30 帧足够，省电
		Engine.max_fps = 30
	# 缸在窗口里的位置：挂件形态缩在留白里，展开形态占满（留白已经算进窗口了）
	var origin := Vector2.ZERO if mode == Mode.EXPAND else Vector2(0, TAB_H)
	display.position = origin
	display.size = Vector2(vp.size * px)
	# frame 在 SubViewport 里，坐标是美术像素，永远贴着 (0,0)，不能用窗口坐标
	frame.position = Vector2.ZERO
	frame.size = Vector2(vp.size)

	# 挂耳突出在缸的左上角外侧：挂件形态坐在顶部留白里，展开形态骑在缸边上
	var b := Vector2(btn_side, btn_side)
	if mode == Mode.STRIP:
		btn.position = Vector2(4, TAB_H - btn_side + 12)
	else:
		btn.position = Vector2(10, 4)
	btn.size = b

	round_mat.set_shader_parameter("rect_size", display.size)
	round_mat.set_shader_parameter("cell", float(px))

	if mode == Mode.STRIP:
		# 整条都穿透，只留挂耳那一小块能点
		var r := Rect2(btn.position, btn.size)
		DisplayServer.window_set_mouse_passthrough(PackedVector2Array([
			r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]))
	_update_camera()
	# 切换时淡入一下，窗口尺寸跳变就不那么生硬
	display.modulate.a = 0.0
	create_tween().tween_property(display, "modulate:a", fade, 0.35)


func _update_camera() -> void:
	# 视口底边 = 底座底边
	cam.position = Vector2(roundf(cam_left), BASE - vp.size.y)


## 窗口坐标 → 缸里的坐标。display 就在 (0,0)，放大 px 倍，所以除回来就是
func _to_world(p: Vector2) -> Vector2:
	return p / float(px) + cam.position


## 展开形态里没被商店挡住的那一截有多宽（美术像素）
func _view_w() -> float:
	if mode != Mode.EXPAND or not shop.visible:
		return float(vp.size.x)
	var shop_px := float(EXPAND_MARGIN + 16 + 160 * Ui.PX)
	return maxf(float(vp.size.x) - shop_px / float(px), 64.0)


## 镜头推到第 z 区，商店跟着切过去
func _go_zone(z: int) -> void:
	tour_i = z
	tour_t = 0.0
	cam_goal = zone_w * float(z)
	shop.zone_i = z
	shop.refresh()


## 手动滑镜头：镜头直接跟手，巡游计时清零，商店跟着当前看的那一区
func _slide(dx_art: float) -> void:
	cam_left = clampf(cam_left + dx_art, 0.0, maxf(world_w - vp.size.x, 0.0))
	cam_goal = cam_left
	tour_t = 0.0
	var z := tank.zone_at(cam_left + _view_w() * 0.5)
	if z != shop.zone_i:
		tour_i = z
		shop.zone_i = z
		shop.refresh()



# ---------------------------------------------------------------- 主循环

func _process(delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0

	# 自动存档：钱在变、位置在变，隔一会儿落一次盘
	save_t += delta
	if save_t >= Save.AUTOSAVE_EVERY:
		save_t = 0.0
		tank.sync_save()
		Save.flush()

	if toast_t > 0.0:
		toast_t -= delta
		if toast_t < 1.0:
			toast.modulate.a = toast_t

	if mode == Mode.EXPAND:
		if pressed:
			press_t += delta
		# 不拖的时候按馆巡游（和挂件形态同一套逻辑）。拖过、滑过、点过都会清零，
		# 20 秒没人碰才动，不会一边看一边被拽走
		tour_t += delta
		if tour_t >= TOUR_SEC:
			tour_t = 0.0
			_tour_next()
		cam_left = lerpf(cam_left, cam_goal, 1.0 - exp(-1.1 * delta))
		cam_left = clampf(cam_left, 0.0, maxf(world_w - vp.size.x, 0.0))
		_update_camera()
	else:
		tour_t += delta
		if tour_t >= TOUR_SEC:
			tour_t = 0.0
			_tour_next()
		# 换个展区的时候镜头慢慢推过去，停住的时候一动不动
		cam_left = lerpf(cam_left, cam_goal, 1.0 - exp(-1.1 * delta))
		_update_hover(delta)

	tank.tick(delta, t, cam_left)


## 三座馆按顺序绕一圈。镜头换馆时顺便把商店切到同一馆，
## 不然会出现「镜头在淡水区、商店写着珊瑚礁区」。
func _tour_next() -> void:
	_go_zone((tour_i + 1) % Tank.ZONE_COUNT)



## 鼠标进到缸的范围就变淡：窗口是穿透的，但还是能看见后面的内容
func _update_hover(delta: float) -> void:
	var m := DisplayServer.mouse_get_position()
	var wr := Rect2i(DisplayServer.window_get_position(), DisplayServer.window_get_size())
	var local := Vector2(m - wr.position)
	var over_btn := Rect2(btn.position, btn.size).grow(4).has_point(local)
	var goal := FADE_HOVER if wr.has_point(m) and not over_btn else 1.0
	if not shot_path.is_empty():
		goal = 1.0          # 自检截图不受鼠标位置影响
	fade = lerpf(fade, goal, 1.0 - exp(-8.0 * delta))
	if not get_tree().get_processed_tweens().size():
		display.modulate.a = fade


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE:
				_apply_mode("strip" if mode == Mode.EXPAND else "expand")
			KEY_ESCAPE:
				if mode == Mode.EXPAND:
					_apply_mode("strip")
			KEY_P:
				_save_shot("res://shots/manual.png")
	elif mode == Mode.EXPAND:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			dragging = event.pressed
			if event.pressed:
				pressed = true
				press_pos = event.position
				press_t = 0.0
			elif pressed:
				# 挪过几个像素就是拖镜头，不算点。点不动就别当拖，拖完别当点
				var moved: Vector2 = (event as InputEventMouseButton).position - press_pos
				if moved.length() <= CLICK_SLOP and press_t <= CLICK_TIME:
					tank.click(_to_world(event.position))
				pressed = false
				tour_t = 0.0
		elif event is InputEventMouseButton and event.pressed:
			# 鼠标滚轮：竖滚、横滚都当横向滑
			match event.button_index:
				MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_LEFT:
					_slide(-24.0 * event.factor)
				MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_RIGHT:
					_slide(24.0 * event.factor)
		elif event is InputEventPanGesture:
			# 触控板两指横滑
			_slide(event.delta.x * 4.0)
		elif event is InputEventMouseMotion and dragging:
			_slide(-event.relative.x / px)


## 退出前落一次盘，不然最后这十几秒的鱼和钱白攒
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_EXIT_TREE:
		if is_instance_valid(tank):
			tank.sync_save()
		Save.flush()



# ---------------------------------------------------------------- 自检截图

func _run_shot() -> void:
	if not _buy_arg.is_empty():
		# --buy=clownfish：第 1 秒假装在商店买下一条，用来截入水的那几帧
		await get_tree().create_timer(1.0).timeout
		_on_shop_changed(_buy_arg)
		await get_tree().create_timer(maxf(shot_wait - 1.0, 0.0)).timeout
	else:
		await get_tree().create_timer(shot_wait).timeout
	await _save_shot(shot_path)
	await get_tree().create_timer(0.2).timeout
	get_tree().quit()


func _save_shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	# 垫一层中灰，看得出哪里是真透明
	var bg := Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8)
	bg.fill(Color(0.55, 0.57, 0.60))
	bg.blend_rect(img, Rect2i(0, 0, img.get_width(), img.get_height()), Vector2i.ZERO)
	var abs_path := ProjectSettings.globalize_path(path)
	bg.save_png(abs_path)
	print("SHOT_SAVED:", abs_path, " ", img.get_width(), "x", img.get_height())
