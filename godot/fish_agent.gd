class_name FishAgent
extends AnimatedSprite2D

signal splashed()           # 入水那一下（dive 里第一次碰到水面）
## 一条鱼：朝目标点漫游，速度平滑，偶尔停下来发呆。
## 可以跟随另一条鱼（leader），按编队槽位游，用来做小鱼群。
## 逻辑坐标用浮点 pos，画的时候取整，像素永远落在网格上。

var pos := Vector2.ZERO
var vel := Vector2.ZERO
var target := Vector2.ZERO
var speed := 10.0
var home_x := -1.0          # >= 0 时只在 home_x ± roam 里活动（小丑鱼守着海葵）
var roam := 60.0
var zone := Vector2(0.0, 1008.0)   # 所在展区的 x 范围：鱼游不出自己那一区
var zone_i := 0             # 第几座馆
var species_id := ""        # catalog.gd 里的品种 id，存档就存这个
var seed_v := 0
var y_pref := 0.5           # 偏好水深：0 = 活动范围上沿，1 = 下沿
var rest := 0.0
var rest_chance := 0.3
var leader: FishAgent = null
var slot := Vector2.ZERO    # 跟随时相对 leader 的位置，x 负 = 在后面
var bob_phase := 0.0
var facing := 1.0
var bounds := Rect2()
var half := Vector2.ZERO
var rng := RandomNumberGenerator.new()

# ---- M2 钱：这条鱼攒钱、吃食
var rate := 1.0             # 每分钟产多少金币（catalog.gd 的 rate）
var credit := 0.0           # 攒到 1 就掉一枚金币
var fed := 0.0              # 刚吃过，产币加速，还剩多少秒
const FED_TIME := 120.0
const FED_BONUS := 1.0      # 吃到之后最多产双倍
var food_ref: Sprite2D = null
var has_lure := false
var lure := Vector2.ZERO

# ---- 新鱼入场：从水面上方落下来，扎进水里，减速停在落点，再开始自己游
const DIVE_FALL := 0.22     # 空中落到水面
const DIVE_SINK := 1.1      # 水下减速扎到落点
var diving := -1.0          # < 0 = 没在入场
var dive_from := Vector2.ZERO
var dive_to := Vector2.ZERO
var dive_surface := 0.0


func setup(tex: Texture2D, frames: int, fw: int, fh: int, seed_value: int) -> void:
	var sf := SpriteFrames.new()
	sf.set_animation_loop("default", true)
	sf.set_animation_speed("default", 6.0)
	for i in frames:
		var at := AtlasTexture.new()
		at.atlas = tex
		at.region = Rect2(i * fw, 0, fw, fh)
		sf.add_frame("default", at)
	sprite_frames = sf
	# 不居中 + 整数偏移：奇数宽的精灵居中会落在半像素上，最近邻采样会抖
	centered = false
	offset = Vector2(-(fw / 2), -(fh / 2))
	half = Vector2(fw, fh) * 0.5
	seed_v = seed_value
	rng.seed = seed_value
	bob_phase = rng.randf() * TAU
	frame = rng.randi() % frames
	play()


func set_bounds(r: Rect2) -> void:
	bounds = Rect2(r.position + half, r.size - half * 2.0)
	if not bounds.has_point(target):
		pick_target()


## 买来的鱼：从 from（水面上方）掉进来，停在 to。期间不受活动范围限制
func dive(from: Vector2, to: Vector2, surface: float) -> void:
	dive_from = from
	dive_to = to
	dive_surface = surface
	diving = 0.0
	pos = from
	facing = 1.0 if rng.randf() < 0.5 else -1.0
	position = pos.round()


func place(p: Vector2) -> void:
	pos = p
	pick_target()


## 被投食引过去：什么都不管，直奔那粒饵料
func feed() -> void:
	fed = FED_TIME
	rest = 0.0


## 刚吃过的一段时间产币加速，慢慢退回正常
func fed_mult() -> float:
	if fed <= 0.0:
		return 1.0
	return 1.0 + FED_BONUS * clampf(fed / FED_TIME, 0.0, 1.0)


## 盯着一粒饵料：目标每帧跟着它走（饵料在往下沉）
func chase(p: Vector2) -> void:
	lure = p
	rest = 0.0
	target = lure.clamp(bounds.position, bounds.end)


func pick_target() -> void:
	if has_lure:
		rest = 0.0
		target = lure.clamp(bounds.position, bounds.end)
		return
	var x: float
	if home_x >= 0.0:
		x = home_x + rng.randf_range(-roam, roam)
	else:
		# 倾向于游远一点：巡游感来自长距离的慢游，而不是原地打转
		var d := rng.randf_range(80.0, 320.0) * (1.0 if rng.randf() < 0.5 else -1.0)
		x = pos.x + d
		if x < bounds.position.x or x > bounds.end.x:
			x = pos.x - d
	var yp := clampf(y_pref + rng.randf_range(-0.3, 0.3), 0.0, 1.0)
	target = Vector2(x, lerpf(bounds.position.y, bounds.end.y, yp))
	target = target.clamp(bounds.position, bounds.end)


func _tick_dive(dt: float) -> void:
	var was_above := pos.y < dive_surface
	diving += dt
	if diving < DIVE_FALL:
		# 空中：自由落体，越落越快
		var k := diving / DIVE_FALL
		pos = Vector2(dive_from.x, lerpf(dive_from.y, dive_surface, k * k))
	else:
		# 水下：一头扎下去，水的阻力让它越来越慢，顺势往朝向那边滑一点
		var k := clampf((diving - DIVE_FALL) / DIVE_SINK, 0.0, 1.0)
		var e := 1.0 - pow(1.0 - k, 3.0)
		pos = Vector2(lerpf(dive_from.x, dive_to.x + facing * 10.0, e),
			lerpf(dive_surface, dive_to.y, e))
		if k >= 1.0:
			diving = -1.0
			vel = Vector2(facing * speed * 0.6, 0.0)
			pick_target()
	if was_above and pos.y >= dive_surface:
		splashed.emit()
	flip_h = facing < 0.0
	# 入水时尾巴拼命摆，慢下来才缓
	speed_scale = 2.2 if diving >= 0.0 else 1.0
	position = pos.round()


func tick(dt: float, t: float) -> void:
	if diving >= 0.0:
		_tick_dive(dt)
		return
	if fed > 0.0:
		fed = maxf(fed - dt, 0.0)
	var desired := Vector2.ZERO
	if leader and not has_lure:     # 鱼群里的跟班看见饵料也会离队去吃
		target = leader.pos + Vector2(slot.x * leader.facing, slot.y) \
			+ Vector2(sin(t * 0.7 + bob_phase), cos(t * 0.5 + bob_phase)) * 2.0
		target = target.clamp(bounds.position, bounds.end)
		var to := target - pos
		desired = to.limit_length(speed * 1.6) * clampf(to.length() / 6.0, 0.0, 1.0)
	elif rest > 0.0:
		rest -= dt
	else:
		var to := target - pos
		if to.length() < 4.0:
			if rng.randf() < rest_chance:
				rest = rng.randf_range(1.5, 4.5)
			pick_target()
		# 快到的时候放慢，停得柔和。看见饵料的鱼游得快一截，抢食的样子
		var sp := speed * (1.8 if has_lure else 1.0)
		desired = to.normalized() * sp * clampf(to.length() / 24.0, 0.3, 1.0)

	vel = vel.lerp(desired, 1.0 - exp(-1.3 * dt))
	pos += vel * dt
	pos = pos.clamp(bounds.position, bounds.end)

	# 转身要有回差，不然慢速时会左右抽搐
	if vel.x > 1.0:
		facing = 1.0
	elif vel.x < -1.0:
		facing = -1.0
	flip_h = facing < 0.0
	# 游得快尾巴摆得快；发呆时尾巴慢慢扇
	speed_scale = 0.35 + clampf(vel.length() / maxf(speed, 1.0), 0.0, 1.5) * 0.9
	position = (pos + Vector2(0.0, sin(t * 1.1 + bob_phase) * 1.2)).round()
