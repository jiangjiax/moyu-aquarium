class_name Save
extends RefCounted
## 存档：user://aquarium.json，一个 Dictionary 走 JSON。
##
## 存什么：钱包、每区的容量、每条鱼（品种 / 展区 / 位置）、上次关掉的时间
## （下次开的时候按它算离线收益）。自动保存：改动时 + 每 15 秒 + 退出时。

const PATH := "user://aquarium.json"
const AUTOSAVE_EVERY := 15.0
const OFFLINE_CAP_MIN := 480.0        # 离线最多算 8 小时，PRD「实现建议」

## 开局阵容：珊瑚礁区 8 条，正好等于初始容量。
## M1 是写死的 11 条（没有存档、没有上限），M2 起阵容由存档决定，
## 换成 8 条是为了不撞容量上限，第一眼看起来不会明显变空。
const START_FISH := [
	"clownfish", "clownfish", "blue_tang", "angelfish",
	"butterfly", "butterfly", "chromis", "chromis",
]

static var data := {}


static func default_data() -> Dictionary:
	var zones := []
	for z in Catalog.ZONES:
		zones.append({"cap": Catalog.BASE_CAP})
	return {"v": 1, "coins": 0.0, "saved_at": 0.0, "zones": zones, "fish": []}


## 读存档。第一次开（或者文件坏了）就开一缸新的。
## 返回 {"fresh": bool, "minutes": 离线多少分钟, "earned": 补了多少金币}
static func load_file() -> Dictionary:
	if not FileAccess.file_exists(PATH):
		data = default_data()
		_seed_start()
		flush()
		return {"fresh": true, "minutes": 0.0, "earned": 0.0}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("存档读不出来，开一缸新的")
		data = default_data()
		_seed_start()
		flush()
		return {"fresh": true, "minutes": 0.0, "earned": 0.0}
	data = parsed
	# 补齐缺的字段，容错手改坏 / 旧版本
	var d := default_data()
	for k in d.keys():
		if not data.has(k):
			data[k] = d[k]
	if Array(data["zones"]).size() != Catalog.ZONES:
		data["zones"] = d["zones"]
	return {"fresh": false, "minutes": 0.0, "earned": 0.0}


## 离线收益：在 tank 造好鱼之前调，用存档里的鱼表直接算
static func settle_offline() -> Dictionary:
	var rate := 0.0
	for rec in Array(data.get("fish", [])):
		if typeof(rec) != TYPE_DICTIONARY:
			continue
		rate += float(Catalog.find(String(rec.get("id", ""))).get("rate", 0.0))
	var last := float(data.get("saved_at", 0.0))
	var minutes := 0.0
	var earned := 0.0
	if last > 0.0:
		minutes = minf(maxf(Time.get_unix_time_from_system() - last, 0.0) / 60.0, OFFLINE_CAP_MIN)
		earned = floor(rate * minutes)
		if earned > 0.0:
			data["coins"] = float(data["coins"]) + earned
	return {"minutes": minutes, "earned": earned}


## 自检用的内存开关：置了 true 就一次盘都不写。
## --coins / --unlock / --zone 改的是内存值，但退出和定时存档照样会 flush，
## 结果自检完退出一次，玩家真的存档就被写脏了（我实测被写进 900 金币 + 淡水区解锁）。
static var readonly := false


static func flush() -> void:
	if readonly:
		return
	data["saved_at"] = Time.get_unix_time_from_system()
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		push_warning("存档写不进去：", error_string(FileAccess.get_open_error()))
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()


static func _seed_start() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260928
	var fish := []
	for id in START_FISH:
		fish.append({"id": id, "z": 0, "x": 0.0, "y": 0.0, "seed": rng.randi()})
	data["fish"] = fish


# ---------------------------------------------------------------- 读写的几层壳

static func zone(z: int) -> Dictionary:
	return data["zones"][z]


static func cap(z: int) -> int:
	return int(zone(z)["cap"])


static func set_cap(z: int, v: int) -> void:
	zone(z)["cap"] = v


## 这一区现在几条鱼（只数还认得的品种）
static func count(z: int) -> int:
	var n := 0
	for rec in Array(data.get("fish", [])):
		if typeof(rec) == TYPE_DICTIONARY and int(rec.get("z", 0)) == z \
				and not Catalog.find(String(rec.get("id", ""))).is_empty():
			n += 1
	return n


static func coins() -> float:
	return float(data.get("coins", 0.0))


static func add_coins(v: float) -> void:
	data["coins"] = maxf(coins() + v, 0.0)


static func spend(v: int) -> bool:
	if coins() < float(v):
		return false
	data["coins"] = coins() - float(v)
	return true


## 全馆每分钟产多少金币
static func rate() -> float:
	var r := 0.0
	for rec in Array(data.get("fish", [])):
		if typeof(rec) != TYPE_DICTIONARY:
			continue
		r += float(Catalog.find(String(rec.get("id", ""))).get("rate", 0.0))
	return r
