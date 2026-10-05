class_name Shop
extends PanelContainer
## 展开形态右边的商店：买鱼、扩建容量。
## 数值全在 catalog.gd，这里只管摆出来和点下去之后刷新。
##
## 一次只显示一个展区，跟着镜头走：滑到哪一区，商店就是哪一区。
## 点顶部页签也行，镜头会跟着推过去。买不了的地方按钮直接灰掉，
## 并且在行上写清楚差多少 —— 挂机游戏最怕的是让人猜为什么点不动。

signal changed()
signal noticed(text: String)
signal zone_picked(z: int)

var zone_i := 0
var _tabs: Array[Button] = []
var _body: VBoxContainer
var _title: Label
var _coin: Label


func _ready() -> void:
	theme = Ui.theme_for()
	add_theme_stylebox_override("panel", Ui.panel())
	custom_minimum_size = Vector2(160 * Ui.PX, 0)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 5 * Ui.PX)
	add_child(root)

	root.add_child(Ui.shadow(Ui.label("商店", 2, Ui.GOLD)))

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 3 * Ui.PX)
	root.add_child(bar)
	for z in Catalog.ZONES:
		var b := Ui.make_button(Catalog.ZONE_NAME[z].substr(0, 3), 46)
		b.pressed.connect(func(): zone_i = z; refresh(); zone_picked.emit(z))
		bar.add_child(b)
		_tabs.append(b)

	_coin = Ui.label("", 1, Ui.GOLD)
	root.add_child(_coin)
	root.add_child(Ui.hline())
	_title = Ui.label("", 1)
	root.add_child(_title)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 4 * Ui.PX)
	root.add_child(_body)


func refresh() -> void:
	for z in _tabs.size():
		var on := z == zone_i
		_tabs[z].add_theme_color_override("font_color", Ui.GOLD if on else Ui.DIM)
	_coin.text = "钱包 %s" % Catalog.money(Save.coins())
	if not is_instance_valid(_body):
		return
	for c in _body.get_children():
		_body.remove_child(c)     # 先摘下来，不然这一帧新旧两套叠在一起
		c.queue_free()
	_fill_fish()
	_fill_capacity()


# ---------------------------------------------------------------- 买鱼

func _fill_fish() -> void:
	var n := Save.count(zone_i)
	var cap := Save.cap(zone_i)
	_title.text = "%s · %d/%d 条" % [Catalog.ZONE_NAME[zone_i], n, cap]
	for sp in Catalog.list(zone_i):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4 * Ui.PX)
		var name_l := Ui.label(String(sp["name"]), 1)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_l)
		row.add_child(Ui.label("%s 金" % Catalog.money(float(sp["price"])), 1, Ui.DIM))
		var b := Ui.make_button("买", 26)
		var full := n >= cap
		var poor := Save.coins() < float(sp["price"])
		if full or poor:
			b.disabled = true
		b.pressed.connect(func(): _buy(String(sp["id"])))
		row.add_child(b)
		_body.add_child(row)
		if full:
			_body.add_child(Ui.label("满了，扩建一下", 1, Ui.DIM))


func _buy(id: String) -> void:
	var sp := Catalog.find(id)
	if sp.is_empty():
		return
	if Save.count(zone_i) >= Save.cap(zone_i):
		noticed.emit("%s 放不下了" % Catalog.ZONE_NAME[zone_i])
		return
	if not Save.spend(int(sp["price"])):
		noticed.emit("金币不够，还差 %d" % (int(sp["price"]) - int(Save.coins())))
		return
	changed.emit(String(sp["id"]))


# ---------------------------------------------------------------- 扩建

func _fill_capacity() -> void:
	_body.add_child(Ui.hline())
	var cap := Save.cap(zone_i)
	var next := Catalog.next_cap(zone_i, cap)
	if next <= cap:
		_body.add_child(Ui.label("容量已扩满（%d 条）" % cap, 1, Ui.DIM))
		return
	var price := Catalog.next_cap_price(zone_i, cap)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4 * Ui.PX)
	var l := Ui.label("容量 %d → %d 条" % [cap, next], 1)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	row.add_child(Ui.label("%s 金" % Catalog.money(price), 1, Ui.DIM))
	var b := Ui.make_button("扩建", 36)
	if Save.coins() < float(price):
		b.disabled = true
	b.pressed.connect(func(): _expand(next, price))
	row.add_child(b)
	_body.add_child(row)


func _expand(next: int, price: int) -> void:
	if not Save.spend(price):
		noticed.emit("金币不够，还差 %d" % (price - int(Save.coins())))
		return
	Save.set_cap(zone_i, next)
	noticed.emit("%s 扩到 %d 条" % [Catalog.ZONE_NAME[zone_i], next])
	changed.emit("")

