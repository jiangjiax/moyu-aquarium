class_name Catalog
extends RefCounted
## 品种表、价格表、扩建表。数值抄自 PRD 的「起步数值」，先跑起来再调。
##
## art 指向 tools/ 生成的那几张鱼图，tint 是在原图上叠的色。
## 淡水区和深海区暂时拿珊瑚礁的鱼改色顶一顶——M3 素材补齐真图之前，
## 这样玩法能先跑通，而且这一轮不需要跑 Python 管线，验收只靠 ./run.sh。

const ZONES := 3
const BASE_CAP := 8
const ZONE_NAME := ["珊瑚礁区", "淡水草缸区", "深海区"]
## 三区开局全开，不用解锁：左右滑就到。以前淡水 500、深海 3000 才能进

## 扩建：8 → 12 → 20，价格 = base × 展区序号（珊瑚礁 1、淡水 2、深海 3）
const CAP_STEP := [{"cap": 12, "price": 300}, {"cap": 20, "price": 1500}]

const SPECIES := [
	[ # 0 珊瑚礁区
		{"id": "clownfish", "name": "小丑鱼", "art": "clownfish",
			"tint": Color(1, 1, 1), "price": 10, "rate": 1.0},
		{"id": "chromis", "name": "银汉鱼", "art": "chromis", "school": true,
			"tint": Color(1, 1, 1), "price": 20, "rate": 2.0},
		{"id": "blue_tang", "name": "蓝倒吊", "art": "blue_tang",
			"tint": Color(1, 1, 1), "price": 50, "rate": 4.0},
		{"id": "angelfish", "name": "神仙鱼", "art": "angelfish",
			"tint": Color(1, 1, 1), "price": 200, "rate": 12.0},
		{"id": "butterfly", "name": "蝴蝶鱼", "art": "butterfly",
			"tint": Color(1, 1, 1), "price": 300, "rate": 20.0},
	],
	[ # 1 淡水草缸区 —— 全是珊瑚礁的鱼改的色（M3 换真图）
		{"id": "guppy", "name": "孔雀鱼", "art": "chromis",
			"tint": Color(0.78, 1.0, 0.55), "price": 80, "rate": 5.0},
		{"id": "neon", "name": "霓虹灯鱼", "art": "chromis", "school": true,
			"tint": Color(0.52, 0.94, 1.0), "price": 250, "rate": 12.0},
		{"id": "discus", "name": "七彩神仙", "art": "butterfly",
			"tint": Color(1.0, 0.80, 0.55), "price": 800, "rate": 35.0},
	],
	[ # 2 深海区 —— 同上，压暗压蓝
		{"id": "lantern", "name": "灯笼鱼", "art": "chromis", "school": true,
			"tint": Color(0.55, 0.78, 1.0), "price": 400, "rate": 20.0},
		{"id": "jelly", "name": "水母", "art": "butterfly",
			"tint": Color(0.70, 0.92, 1.0), "price": 1200, "rate": 50.0},
		{"id": "angler", "name": "鮟鱇鱼", "art": "angelfish",
			"tint": Color(0.42, 0.50, 0.74), "price": 4000, "rate": 150.0},
	],
]


static func list(z: int) -> Array:
	if z < 0 or z >= SPECIES.size():
		return []
	return SPECIES[z]


static func find(id: String) -> Dictionary:
	for z in SPECIES.size():
		for sp in SPECIES[z]:
			if String(sp["id"]) == id:
				return sp
	return {}


## 这一档扩建要多少钱，扩满了返回 -1
static func next_cap_price(z: int, cap: int) -> int:
	for step in CAP_STEP:
		if int(step["cap"]) > cap:
			return int(step["price"]) * (z + 1)
	return -1


## 下一档容量到哪，扩满了还是原样
static func next_cap(z: int, cap: int) -> int:
	for step in CAP_STEP:
		if int(step["cap"]) > cap:
			return int(step["cap"])
	return cap


static func money(v: float) -> String:
	return str(int(floor(v)))
