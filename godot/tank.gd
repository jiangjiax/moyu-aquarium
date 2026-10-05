class_name Tank
extends Node2D
## 馆里的世界。坐标单位 = 美术像素，y = 0 是底座上沿，往上为负。
##
## 横向是三座展区，每区正好一屏宽：zone_w × [0] 是珊瑚礁、[1] 是淡水草缸、[2] 是深海。
## 每区自带水色、沙色、装饰和远景，风格一眼能分开。
##
## 分层（z_index 从后往前）：
##   -100 水体 shader（色带 + 光柱）
##    -95 远景礁岩（视差 0.25）  -90 近景礁岩（视差 0.5）
##    -60 后排装饰（偏水色，拉开景深）
##    -40 沙  -38 焦散
##    -20 中排装饰  10 鱼  20 前排装饰  30 气泡、浮游颗粒

const SAND_TOP := -11.0
const ART := "res://art/"
const ZONE_COUNT := 3

## 缸里最多同时摆多少枚金币，满了直接进钱包，不然深海区的鮟鱇鱼会把沙面埋了
const COIN_CAP := 24
## 金币落到沙上多久自己收进钱包。两种形态一样：展开时想点就点，不点也照样进钱包。
## 以前展开形态要等 90 秒，看着就像金币收不回来
const AUTO_TAKE := 2.5

signal coins_changed()
signal notice(text: String)

var world_w := 3024.0
var world_h := 150.0
var zone_w := 1008.0
var meta: Dictionary
var fishes: Array[FishAgent] = []
var anemones: Array[float] = []
var parallax: Array = []          # [节点, 视差系数, 基准 x]
var coins_fx: Array = []          # 掉在缸里的金币 {node, v, vx, vy, rest, t, ph}
var food: Array = []              # 沉下去的饵料 {node, rest, ph}
var zroots: Array[Control] = []   # 每区一个裁剪根，见 _zadd
var surface_y := -71.0            # 当前视口里的水面，新鱼从这里跳进来
var swim_top := -67.0             # 当前能游的最上沿，set_swim_area 给
var sfx: AudioStreamPlayer


## 每一区都先搭一个裁剪根，再把水、远景、沙、装饰往里挂。
## 为什么非要裁：水色和沙地都故意往外多铺一截（x0-64、x0-300），好让展区之间
## 过渡看不出缝。但三区是依次建的，后建的会盖在先建的上面——挂件形态正好一屏一区，
## 于是右边缘就硬生生多出一块别区的水色，像挂了扇黑门板。裁一下就没了。
func _build_zone_roots() -> void:
	for z in ZONE_COUNT:
		var root := Control.new()
		root.position = Vector2(zone_x0(z), -world_h)
		root.size = Vector2(zone_w, world_h + 2)
		root.clip_contents = true
		root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(root)
		zroots.append(root)


## 把节点收进第 z 区的裁剪根。节点自己的坐标是全缸坐标，进来时换算成区内坐标。
func _zadd(z: int, node: CanvasItem) -> void:
	node.position -= zroots[z].position
	zroots[z].add_child(node)


func build(one_screen_w: float, h: float) -> void:
	zone_w = one_screen_w
	world_h = h
	world_w = zone_w * ZONE_COUNT
	meta = JSON.parse_string(FileAccess.get_file_as_string(ART + "meta.json"))
	_build_zone_roots()
	for z in ZONE_COUNT:
		var x0 := zone_x0(z)
		_build_water(z, x0)
		_build_backdrop(z, x0)
		_build_sand(z, x0)
		_build_decor(z, x0)
	_build_fish()
	_build_particles()
	sfx = AudioStreamPlayer.new()
	sfx.volume_db = -6.0
	add_child(sfx)



func zone_x0(z: int) -> float:
	return zone_w * float(z)


func zone_at(x: float) -> int:
	return clampi(int(x / zone_w), 0, ZONE_COUNT - 1)


# ---------------------------------------------------------------- 每个展区的样子

## 三区一眼能分开，靠的就是这几组值。改风格只动这一个函数
##
## 珊瑚礁亮蓝绿、淡水暖绿、深海近乎全黑。淡水没有珊瑚，深海没有阳光：
## 深海的光全靠浮游生物自己亮，所以光柱和焦散都关掉。
static func _style(z: int) -> Dictionary:
	match z:
		1:
			return {
				"water": [Color(0.78, 0.87, 0.60), Color(0.58, 0.76, 0.45),
					Color(0.42, 0.64, 0.35), Color(0.30, 0.52, 0.29)],
				"ray": 0.05,
				"caustic": 0.09,
				"sand": Color(0.93, 0.88, 0.70),
				"back": Color(0.50, 0.82, 0.52, 0.42),
				"back2": Color(0.56, 0.86, 0.55, 0.66),
				"decor_tint": Color(0.94, 1.0, 0.90),
				"step": 78.0,
				"groups": {
					"weed": [["kelp_a", -9, "back"], ["kelp_b", 4, "back"],
						["rock_m", 2, "mid"]],
					"plant": [["kelp_b", -7, "back"], ["kelp_a", 6, "back"],
						["grass_b", -17, "mid"], ["rock_s", 15, "front"]],
					# 草缸的大石头，石头顶上长草
					"boulder": [["rock_xl", 0, "mid"], ["grass_a", -13, "mid"],
						["grass_b", 14, "mid"], ["shell", 24, "front"]],
					"bush": [["kelp_a", -11, "back"], ["kelp_b", 9, "back"],
						["rock_l", 0, "mid"], ["grass_a", 19, "mid"]],
					"bits": [["rock_xs", 0, "mid"], ["grass_b", 8, "mid"]],
				},
				"seq": ["weed", "plant", "bits", "boulder", "bush", "plant",
					"boulder", "weed", "bits", "bush", "boulder", "plant"],
			}
		2:
			return {
				"water": [Color(0.10, 0.17, 0.32), Color(0.07, 0.13, 0.25),
					Color(0.05, 0.09, 0.19), Color(0.03, 0.05, 0.12)],
				"ray": 0.0,          # 深海没有阳光，光全靠鱼自己
				"caustic": 0.0,
				"sand": Color(0.30, 0.34, 0.44),
				"back": Color(0.16, 0.22, 0.34, 0.5),
				"back2": Color(0.20, 0.26, 0.38, 0.75),
				"decor_tint": Color(0.40, 0.46, 0.60),
				"step": 112.0,      # 摆得疏，深海就该空
				"groups": {
					# 海葵在这里改头换面：整体压成冷青，看不出是海葵，像发光的管虫
					"garden": [["anemone", 0, "mid"], ["rock_xl", 10, "back"],
						["rock_xs", -16, "front"]],
					"dark": [["rock_l", 0, "mid"], ["rock_m", -15, "mid"]],
					"spire": [["rock_xl", 0, "mid"], ["rock_s", 15, "front"],
						["rock_xs", -13, "front"]],
					"whip": [["fan_s", 2, "back"], ["rock_m", 12, "mid"],
						["rock_xs", -11, "front"]],
					"silt": [["rock_m", 0, "mid"]],
				},
				"seq": ["garden", "silt", "dark", "spire", "silt", "whip",
					"dark", "silt", "spire", "silt", "garden", "dark"],
			}
	return {
		"water": [Color(0.56, 0.80, 0.79), Color(0.40, 0.70, 0.73),
			Color(0.29, 0.60, 0.68), Color(0.22, 0.49, 0.59)],
		"ray": 0.07,
		"caustic": 0.16,
		"sand": Color(1, 1, 1),
		"back": Color(1, 1, 1, 0.5),
		"back2": Color(1, 1, 1, 0.75),
		"decor_tint": Color(1, 1, 1),
		"step": 72.0,
		"groups": {
			"reef": [["coral_big", -16, "back"], ["rock_xl", 4, "mid"],
				["grass_a", 26, "mid"], ["coral_pink", -30, "mid"],
				["rock_xs", 30, "front"]],
			"kelp": [["kelp_a", -7, "back"], ["kelp_b", 5, "back"],
				["rock_m", 0, "mid"], ["grass_b", -14, "front"]],
			"home": [["anemone", 0, "mid"], ["rock_s", -14, "mid"],
				["shell", 15, "front"]],
			"fan": [["fan", -2, "back"], ["brain", 10, "mid"],
				["grass_b", -12, "mid"]],
			"garden": [["coral_coral", -8, "mid"], ["fan_s", 9, "back"],
				["brain_l", 22, "mid"], ["rock_s", 4, "front"],
				["starfish", -22, "front"]],
			"bits": [["rock_xs", 0, "mid"], ["grass_b", 7, "mid"]],
		},
		"seq": ["kelp", "reef", "bits", "home", "fan", "garden", "bits", "kelp",
			"home", "reef", "bits", "fan", "garden", "home", "kelp", "reef"],
	}


# ---------------------------------------------------------------- 水与远景

func _build_water(z: int, x0: float) -> void:
	var st := _style(z)
	var r := ColorRect.new()
	r.position = Vector2(x0 - 64, -world_h)
	r.size = Vector2(zone_w + 128, world_h + 2)
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/water.gdshader")
	m.set_shader_parameter("rect_px", r.size)
	var pal: Array = st["water"]
	m.set_shader_parameter("c_surface", pal[0])
	m.set_shader_parameter("c_upper", pal[1])
	m.set_shader_parameter("c_mid", pal[2])
	m.set_shader_parameter("c_deep", pal[3])
	m.set_shader_parameter("ray_strength", st["ray"])
	r.material = m
	r.z_index = -100
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_zadd(z, r)


func _tiled(z: int, tex_name: String, x: float, y: float, w: float) -> Sprite2D:
	var tex: Texture2D = load(ART + tex_name)
	var s := Sprite2D.new()
	s.texture = tex
	s.centered = false
	s.region_enabled = true
	s.region_rect = Rect2(0, 0, w, tex.get_height())
	s.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	s.position = Vector2(x, y)
	_zadd(z, s)
	return s


func _build_backdrop(z: int, x0: float) -> void:
	var st := _style(z)
	# 远的一层：翻转 + 更淡 + 更高，和近的一层错开，不会看出是同一张图
	var far := _tiled(z, "backdrop.png", x0 - 200, SAND_TOP - 40, zone_w + 400)
	far.flip_h = true
	far.modulate = st["back"]
	far.z_index = -95
	parallax.append([far, 0.25, far.position.x, z])
	var near := _tiled(z, "backdrop.png", x0 - 300, SAND_TOP - 30, zone_w + 600)
	near.region_rect.position.x = 97 + z * 61
	near.modulate = st["back2"]
	near.z_index = -90
	parallax.append([near, 0.5, near.position.x, z])


func _build_sand(z: int, x0: float) -> void:
	var st := _style(z)
	var sand := _tiled(z, "sand.png", x0 - 64, SAND_TOP - 2, zone_w + 128)
	sand.modulate = st["sand"]
	sand.z_index = -40
	if float(st["caustic"]) <= 0.0:
		return
	var c := ColorRect.new()
	c.position = Vector2(x0 - 64, SAND_TOP - 1)
	c.size = Vector2(zone_w + 128, 10)
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/caustics.gdshader")
	m.set_shader_parameter("rect_px", c.size)
	m.set_shader_parameter("strength", st["caustic"])
	c.material = m
	c.z_index = -38
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_zadd(z, c)


# ---------------------------------------------------------------- 装饰

func _build_decor(z: int, x0: float) -> void:
	var st := _style(z)
	var decor_tint: Color = st["decor_tint"]
	var groups: Dictionary = st["groups"]
	var seq: Array = st["seq"]
	var step: float = st["step"]
	var n := maxi(3, int(zone_w / step))
	var dx := zone_w / float(n)
	for i in n:
		var key: String = seq[i % seq.size()]
		# 黄金比例抖动：间距疏密自然，但每次运行都一样
		var jitter := fmod(float(i) * 0.618, 1.0) - 0.5
		var cx := x0 + roundf(dx * (float(i) + 0.5) + jitter * dx * 0.35)
		for item in groups[key]:
			_place(z, item[0], cx + float(item[1]), item[2], decor_tint, i)
		if key == "home":
			anemones.append(cx)


func _place(z: int, name: String, x: float, layer: String, tint: Color, idx: int) -> void:
	var info: Dictionary = meta["decor"][name]
	var tex: Texture2D = load(ART + "deco_%s.png" % name)
	var s := Sprite2D.new()
	s.texture = tex
	s.centered = false
	var sink: float = {"back": 1.0, "mid": 3.0, "front": 5.0}[layer]
	s.position = Vector2(roundf(x - float(info["w"]) * 0.5), SAND_TOP + sink - float(info["h"]))
	s.z_index = int({"back": -60, "mid": -20, "front": 20}[layer])
	# 后排往水色里褪一点，前后自然就分开了
	s.modulate = tint * (Color(0.80, 0.90, 0.94) if layer == "back" else Color(1, 1, 1))
	if info["sway"]:
		var m := ShaderMaterial.new()
		m.shader = preload("res://shaders/sway.gdshader")
		m.set_shader_parameter("tex_px", Vector2(info["w"], info["h"]))
		var tall := name.begins_with("kelp")
		m.set_shader_parameter("amp", 2.4 if tall else 1.2)
		m.set_shader_parameter("speed", 0.55 if tall else 0.8)
		m.set_shader_parameter("wave", 0.09 if tall else 0.25)
		m.set_shader_parameter("phase", x * 0.037 + float(idx))
		s.material = m
	_zadd(z, s)


# ---------------------------------------------------------------- 鱼

## 巡游参数：速度、偏好水深、发呆概率
const SPECIES := {
	"clownfish": {"speed": 7.0, "y": 0.85, "rest": 0.5},
	"blue_tang": {"speed": 12.0, "y": 0.45, "rest": 0.15},
	"angelfish": {"speed": 5.5, "y": 0.3, "rest": 0.4},
	"butterfly": {"speed": 8.5, "y": 0.6, "rest": 0.3},
	"chromis": {"speed": 9.0, "y": 0.4, "rest": 0.0},
}


func _make_fish(sp: Dictionary, seed_value: int) -> FishAgent:
	var art := String(sp["art"])
	var info: Dictionary = meta["fish"][art]
	var f := FishAgent.new()
	f.setup(load(ART + "fish_%s.png" % art), int(info["frames"]), int(info["w"]),
		int(info["h"]), seed_value)
	var move: Dictionary = SPECIES[art]
	f.speed = float(move["speed"]) * f.rng.randf_range(0.85, 1.15)
	f.y_pref = float(move["y"])
	f.rest_chance = float(move["rest"])
	f.species_id = String(sp["id"])
	f.rate = float(sp["rate"])
	# 同一个鱼图在不同展区可以是不同品种：淡水、深海的鱼暂时是珊瑚礁的图改了色
	f.modulate = sp.get("tint", Color(1, 1, 1))
	f.z_index = 10 + fishes.size() % 7
	add_child(f)
	fishes.append(f)
	return f


## 鱼按存档来。第一次开档（或者认不出的品种）跳过，剩下的照旧摆好
func _build_fish() -> void:
	var leaders := {}
	var seats := {}
	var rng := RandomNumberGenerator.new()
	for rec in Array(Save.data.get("fish", [])):
		if typeof(rec) != TYPE_DICTIONARY:
			continue
		var sp := Catalog.find(String(rec.get("id", "")))
		if sp.is_empty():
			continue
		var z := int(rec.get("z", 0))
		var f := _make_fish(sp, int(rec.get("seed", rng.randi())))
		f.zone_i = z
		f.zone = Vector2(zone_x0(z), zone_x0(z) + zone_w)
		f.set_bounds(_swim_rect(z, -world_h + 20.0))
		var x := float(rec.get("x", 0.0))
		if x <= 0.0:
			# 存档里没记位置（第一次开）：散在沙上方，别挤成一堆
			x = f.zone.x + zone_w * (0.12 + 0.76 * rng.randf())
		var y := float(rec.get("y", 0.0))
		if y >= 0.0:
			y = SAND_TOP - 6.0 - rng.randf() * (world_h * 0.30)
		f.home_x = -1.0
		f.place(Vector2(x, y))
		if f.species_id == "clownfish" and z == 0:
			# 小丑鱼守海葵：把家定在最近的那丛上
			var ax := _nearest_anemone(x)
			if ax >= 0.0:
				f.home_x = ax
				f.roam = 40.0
				f.place(Vector2(ax, SAND_TOP - 14.0))
		if bool(sp.get("school", false)):
			if leaders.has(z):
				f.leader = leaders[z]
				var k: int = seats[z]
				seats[z] = k + 1
				f.slot = Vector2(-9.0 - 8.0 * (k / 2) - f.rng.randf() * 3.0,
					(-5.0 if k % 2 == 0 else 5.0) + f.rng.randf_range(-2.0, 2.0))
				f.place(f.leader.pos + f.slot)
			else:
				leaders[z] = f
				seats[z] = 0


## 商店买鱼：从水面上方「扑通」跳进来，落在 x 这一竖线上。
## x 由 main 给——正对着镜头看得见的那一截中间，不然鱼出生在商店背后，买了等于没看见。
func add_fish(id: String, z: int, x: float) -> FishAgent:
	var sp := Catalog.find(id)
	if sp.is_empty():
		return null
	var f := _make_fish(sp, randi())
	f.zone_i = z
	f.zone = Vector2(zone_x0(z), zone_x0(z) + zone_w)
	f.set_bounds(_swim_rect(z, swim_top))
	x = clampf(x, f.zone.x + 24.0, f.zone.y - 24.0)
	var land_y := minf(surface_y + 34.0, SAND_TOP - 16.0)
	f.dive(Vector2(x, surface_y - f.half.y * 2.0 - 6.0), Vector2(x, land_y), surface_y)
	f.splashed.connect(_splash.bind(f), CONNECT_ONE_SHOT)
	Save.data["fish"].append({"id": id, "z": z, "x": x, "y": land_y, "seed": f.seed_v})
	return f


## 鱼碰到水面那一下：响一声，水面溅起几滴水，身后拖一串气泡
func _splash(f: FishAgent) -> void:
	sfx.stream = Sfx.splash()
	sfx.play()
	var at := Vector2(f.pos.x, surface_y)
	# 水面紧贴着视口上沿，水花往上溅会被玻璃框挡掉，所以水花压得很低、往两边甩，
	# 再加一圈往两边推开的波纹，一眼看得出「有东西掉进来了」
	_ripple(at, 14.0, 0.8)
	var drop_tex: Texture2D = load(ART + "dust.png")
	for i in 8:
		var d := Sprite2D.new()
		d.texture = drop_tex
		d.centered = false
		d.z_index = 31
		d.position = at.round()
		add_child(d)
		var side := -1.0 if i % 2 == 0 else 1.0
		var reach := side * (3.0 + float(i / 2) * 3.5)
		var peak := 3.0 - float(i / 2) * 0.5
		var tw := create_tween()
		tw.tween_method(func(k: float):
			d.position = (at + Vector2(reach * k, -peak * 4.0 * k * (1.0 - k))).round(),
			0.0, 1.0, 0.35 + 0.05 * float(i / 2))
		tw.tween_callback(d.queue_free)
	var bubbles := ["bubble_1.png", "bubble_2.png", "bubble_1.png", "bubble_3.png", "bubble_1.png"]
	for i in bubbles.size():
		var b := Sprite2D.new()
		b.texture = load(ART + bubbles[i])
		b.centered = false
		b.z_index = 30
		b.modulate.a = 0.0
		var p := at + Vector2(randf_range(-4.0, 4.0), 6.0 + 5.0 * float(i))
		b.position = p.round()
		add_child(b)
		var tw := create_tween()
		tw.tween_interval(0.10 * float(i))
		tw.tween_property(b, "modulate:a", 0.9, 0.05)
		tw.tween_property(b, "position", (p + Vector2(0, -10.0 - 3.0 * float(i))).round(), 0.9)
		tw.parallel().tween_property(b, "modulate:a", 0.0, 0.9).set_delay(0.3)
		tw.tween_callback(b.queue_free)


func _swim_rect(z: int, top: float) -> Rect2:
	return Rect2(Vector2(zone_x0(z) + 4.0, top), Vector2(zone_w - 8.0, SAND_TOP - 1.0 - top))


func _nearest_anemone(x: float) -> float:
	var best := -1.0
	var bd := 1e9
	for a in anemones:
		if zone_at(a) != 0:
			continue
		var d: float = absf(a - x)
		if d < bd:
			bd = d
			best = a
	return best


## 收起 / 展开换的是视口高度，能游的水深跟着变
func set_swim_area(top: float, surface: float) -> void:
	swim_top = top
	surface_y = surface
	for f in fishes:
		f.set_bounds(_swim_rect(f.zone_i, top))


## 存档要记每条鱼现在在哪
func sync_save() -> void:
	var out := []
	for f in fishes:
		out.append({"id": f.species_id, "z": f.zone_i,
			"x": f.pos.x, "y": f.pos.y, "seed": f.seed_v})
	Save.data["fish"] = out



# ---------------------------------------------------------------- 粒子

func _particles(tex: String, amount: int, life: float, box: Vector2, pos: Vector2,
		vel: Vector2, alpha: float, tint: Color = Color(1, 1, 1),
		vis: float = 200.0) -> GPUParticles2D:
	var p := GPUParticles2D.new()
	p.texture = load(ART + tex)
	p.amount = amount
	p.lifetime = life
	p.preprocess = life
	p.position = pos
	p.randomness = 1.0
	p.modulate = tint
	p.visibility_rect = Rect2(-vis, -world_h * 2, vis * 2, world_h * 3)
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = Vector3(box.x, box.y, 0)
	m.direction = Vector3(0, -1, 0)
	m.spread = 6.0
	m.initial_velocity_min = vel.x
	m.initial_velocity_max = vel.y
	m.gravity = Vector3.ZERO
	# 湍流：气泡上浮时左右轻轻晃，小颗粒随水慢慢漂
	m.turbulence_enabled = true
	m.turbulence_noise_strength = 1.0
	m.turbulence_noise_scale = 4.0
	m.turbulence_noise_speed_random = 0.3
	m.turbulence_influence_min = 0.02
	m.turbulence_influence_max = 0.06
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.12, Color(1, 1, 1, alpha))
	g.add_point(0.85, Color(1, 1, 1, alpha))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	m.color_ramp = gt
	p.process_material = m
	p.z_index = 30
	add_child(p)
	return p


func _build_particles() -> void:
	for z in ZONE_COUNT:
		var x0 := zone_x0(z)
		var deep := z == 2
		# 几串从礁石缝里冒出来的气泡。深海是热液，气泡少而慢
		var n := maxi(2, int(zone_w / 300.0))
		for i in n:
			var x := x0 + zone_w * (float(i) + 0.3 + fmod(i * 0.618, 0.4)) / float(n)
			var v := Vector2(6, 9) if deep else Vector2(9, 12)
			_particles("bubble_1.png", 4, 13.0, Vector2(1, 0),
				Vector2(x, SAND_TOP - 2), v, 0.9)
			_particles("bubble_2.png", 2, 15.0, Vector2(1, 0),
				Vector2(x + 2, SAND_TOP - 2), v * 0.8, 0.8)
		# 零星的大气泡，满区随机
		_particles("bubble_3.png", maxi(2, int(zone_w / 250.0)), 18.0,
			Vector2(zone_w * 0.5, 0), Vector2(x0 + zone_w * 0.5, SAND_TOP),
			Vector2(6, 9), 0.6, Color(1, 1, 1), zone_w * 0.6)
		# 浮游颗粒：几乎不动，只是让水看起来有体积。深海的这些是发光的浮游生物，
		# 但深海底色几乎全黑，粒子只要稍亮一点就变成悬在半空的灰方块，所以压得很低。
		var dust := _particles("dust.png", int(zone_w / 12.0), 24.0,
			Vector2(zone_w * 0.5, world_h * 0.5), Vector2(x0 + zone_w * 0.5, -world_h * 0.5),
			Vector2(0.2, 1.2), 0.3 if not deep else 0.75,
			Color(1, 1, 1) if not deep else Color(0.30, 0.54, 0.60), zone_w * 0.6)
		dust.z_index = 25


# ---------------------------------------------------------------- 金币

## 成鱼自己攒钱，攒够一枚就掉在缸里，落到沙上一会儿自己进钱包，想点也可以点
func _credit(f: FishAgent, dt: float) -> void:
	f.credit += f.rate / 60.0 * dt * f.fed_mult()
	var guard := 0
	while f.credit >= 1.0 and guard < 3:
		f.credit -= 1.0
		_spawn_coin(f.pos)
		guard += 1


func _coins_in(z: int) -> int:
	var n := 0
	for c in coins_fx:
		if zone_at((c["node"] as Sprite2D).position.x) == z:
			n += 1
	return n


func _spawn_coin(at: Vector2) -> void:
	var z := zone_at(at.x)
	if _coins_in(z) >= COIN_CAP:
		Save.add_coins(1.0)          # 缸里摆不下了，直接进钱包
		coins_changed.emit()
		return
	var n := Sprite2D.new()
	n.texture = PixelArt.coin()
	n.centered = false
	n.z_index = 22
	n.position = at.round()
	add_child(n)
	coins_fx.append({"node": n, "v": 1.0, "vx": randf_range(-5.0, 5.0), "vy": -16.0,
		"rest": false, "t": 0.0, "ph": randf() * TAU})


func _update_coins(dt: float, t: float) -> void:
	for i in range(coins_fx.size() - 1, -1, -1):
		var c: Dictionary = coins_fx[i]
		var n: Sprite2D = c["node"]
		if not bool(c["rest"]):
			c["vy"] = float(c["vy"]) + 44.0 * dt
			var p := n.position + Vector2(float(c["vx"]) + sin(t * 3.0 + float(c["ph"])) * 5.0,
				float(c["vy"])) * dt
			if p.y >= SAND_TOP - 1.0:
				p.y = SAND_TOP - 1.0
				c["rest"] = true
				c["t"] = 0.0
			n.position = p.round()
		else:
			c["t"] = float(c["t"]) + dt
			n.position.y = roundf(SAND_TOP - 1.0 + sin(t * 3.0 + float(c["ph"])) * 0.5)
			if float(c["t"]) > AUTO_TAKE:
				_collect(i)


## 收钱：进钱包，币自己往上飞一下淡掉
func _collect(i: int) -> void:
	var c: Dictionary = coins_fx[i]
	coins_fx.remove_at(i)
	Save.add_coins(float(c["v"]))
	coins_changed.emit()
	var n: Sprite2D = c["node"]
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(n, "position", n.position + Vector2(0, -14), 0.45)
	tw.tween_property(n, "modulate:a", 0.0, 0.45)
	tw.chain().tween_callback(n.queue_free)


## 水面上往两边推开的一道波纹。reach 是推多远（格），dur 是多久散掉
func _ripple(at: Vector2, reach: float, dur: float) -> void:
	for side in [-1.0, 1.0]:
		var r := ColorRect.new()
		r.color = Color(0.93, 0.98, 0.97, 0.9)
		r.size = Vector2(2, 1)
		r.position = (at + Vector2(-1, 1)).round()
		r.z_index = 31
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(r)
		var tw := create_tween()
		tw.tween_method(func(k: float):
			var w := roundf(2.0 + reach * 0.35 * k)
			r.size = Vector2(w, 1)
			r.position = (at + Vector2((3.0 + reach * k) * side - (w if side < 0.0 else 0.0), 1.0)).round()
			r.color.a = 0.9 * (1.0 - k),
			0.0, 1.0, dur).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tw.tween_callback(r.queue_free)


# ---------------------------------------------------------------- 投食

## 饵料的物理：从水面撒下去，先在水面上浮一小会儿（表面张力托着），然后开始沉。
## 水里是「重力 - 线性阻力」：一开始加速，很快到终端速度匀速往下，
## 边沉边左右晃（晃的幅度随下沉速度走，刚入水和落底时几乎不晃）。落到沙上就停住。
const FOOD_FLOAT := 0.45      # 在水面上浮多久才开始沉（秒）
const FOOD_G := 36.0          # 水里的有效重力（扣掉浮力），格/秒²
const FOOD_DRAG := 2.6        # 线性阻力系数：终端速度 = G / DRAG ≈ 14 格/秒
const FOOD_SWAY := 4.0        # 左右晃的最大速度（格/秒）

## 点在水里哪儿都行，饵料从这一竖线的水面撒下去——投食是从上面撒，不是凭空出现在水中间
func drop_food(x: float, _y: float) -> void:
	var z := zone_at(x)
	var n := Sprite2D.new()
	n.texture = PixelArt.pellet()
	n.centered = false
	n.z_index = 8
	var p := Vector2(clampf(x, zone_x0(z) + 6.0, zone_x0(z) + zone_w - 6.0) - 2.0, surface_y)
	n.position = p.round()
	add_child(n)
	food.append({"node": n, "pos": p, "vy": 0.0, "t": 0.0, "rest": false, "ph": randf() * TAU})
	_ripple(p + Vector2(2, 0), 5.0, 0.5)


## 饵料 4×4，碰撞按中心算
func _food_center(p: Dictionary) -> Vector2:
	return Vector2(p["pos"]) + Vector2(2, 2)


func _update_food(dt: float, t: float) -> void:
	for i in range(food.size() - 1, -1, -1):
		var p: Dictionary = food[i]
		var n: Sprite2D = p["node"]
		p["t"] = float(p["t"]) + dt
		if not bool(p["rest"]) and float(p["t"]) > FOOD_FLOAT:
			var vy: float = p["vy"]
			vy += (FOOD_G - FOOD_DRAG * vy) * dt
			var pos: Vector2 = p["pos"]
			var sway := sin(t * 2.3 + float(p["ph"])) * FOOD_SWAY * clampf(vy / 10.0, 0.0, 1.0)
			pos += Vector2(sway, vy) * dt
			if pos.y >= SAND_TOP - 3.0:
				pos.y = SAND_TOP - 3.0     # 半埋在沙面上
				vy = 0.0
				p["rest"] = true
			p["vy"] = vy
			p["pos"] = pos
			n.position = pos.round()
		# 鱼碰到饵料就吃：按身体的包围盒算，不按中心点距离。
		# 以前按中心距离算，高个子的神仙鱼中心离沙面 17 格，沉到底的饵料它永远够不着
		var c := _food_center(p)
		var eater: FishAgent = null
		for f in fishes:
			if f.diving >= 0.0:
				continue
			var d := (c - f.pos).abs()
			if d.x <= f.half.x * 0.6 + 2.0 and d.y <= f.half.y + 3.0:
				eater = f
				break
		if eater != null:
			eater.feed()
			_pop(c)
			food.remove_at(i)
			n.queue_free()
	# 分工：每粒饵料找一条最近的鱼，一条鱼只盯一粒。盯上了之后每帧跟着饵料走——
	# 饵料在往下沉，只记住它刚撒下来的位置的话，鱼会游到半空一个空点上干等
	for f in fishes:
		if f.has_lure and not _food_alive(f.food_ref):
			f.has_lure = false
			f.food_ref = null
		if f.has_lure:
			f.chase(f.food_ref.position + Vector2(2, 2))
			continue
		if f.diving >= 0.0:
			continue
		var best: Sprite2D = null
		var bd := 1e9
		for p in food:
			var n2: Sprite2D = p["node"]
			if zone_at(n2.position.x) != f.zone_i:
				continue          # 鱼游不出自己那一区，隔壁区的饵料够不着，别让它贴着边干着急
			var d := f.pos.distance_to(n2.position)
			if d < bd:
				bd = d
				best = n2
		if best != null and bd < 460.0:
			f.food_ref = best
			f.has_lure = true
			f.chase(best.position + Vector2(2, 2))


func _food_alive(n: Sprite2D) -> bool:
	if not is_instance_valid(n):
		return false
	for p in food:
		if p["node"] == n:
			return true
	return false


## 吃到东西冒个泡
func _pop(at: Vector2) -> void:
	var n := Sprite2D.new()
	n.texture = load(ART + "bubble_1.png")
	n.centered = false
	n.z_index = 9
	n.position = at.round()
	add_child(n)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(n, "position", n.position + Vector2(0, -9.0), 0.6)
	tw.tween_property(n, "modulate:a", 0.0, 0.6)
	tw.chain().tween_callback(n.queue_free)


# ---------------------------------------------------------------- 点击

## 展开形态点一下：先看是不是点到了金币，不是就往水里丢一粒饵料
func click(p: Vector2) -> void:
	for i in range(coins_fx.size() - 1, -1, -1):
		var n: Sprite2D = coins_fx[i]["node"]
		if n.position.distance_to(p) < 8.0:
			_collect(i)
			return
	if p.y >= SAND_TOP - 2.0 or p.y <= -world_h:
		return
	drop_food(p.x, p.y)


# ---------------------------------------------------------------- 每帧

func tick(dt: float, t: float, cam_left: float) -> void:
	for f in fishes:
		f.tick(dt, t)
		_credit(f, dt)
	_update_food(dt, t)
	_update_coins(dt, t)
	for p in parallax:
		# 视差：镜头动 1，远景只动系数那么多。节点在裁剪根里，用区内坐标算
		var node: Node2D = p[0]
		node.position.x = roundf(float(p[2]) + (cam_left - zone_x0(int(p[3]))) * (1.0 - float(p[1])))

