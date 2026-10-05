"""鱼：轮廓手画（字符画 / 几何），花纹、明暗、描边、摆尾帧交给管线。

材质约定：
  B 身体  W 白带  K 深色花纹    —— 立体材质，共用一张距离场，花纹会跟着身体一起受光
  T 尾鳍  D 背鳍  A 臀鳍  P 胸鳍 —— 薄片材质，半透明
头朝右。摆尾 = 尾鳍以尾柄为轴横向压缩（侧视角里尾巴左右摆就是宽度在变）。
"""
from px_core import Grid, from_ascii, render, ramp, pad, sheet

SOLID = {"B", "W", "K", "Y"}
FRAMES = (1.0, 0.78, 0.55, 0.78)


def _eye(g, x, y, size=2):
    """深色瞳孔 + 左上一颗高光。高光用暖白不用纯白，否则像开了闪光灯"""
    dark = (24, 20, 30)
    for dy in range(size):
        for dx in range(size):
            g.fix[(x + dx, y + dy)] = dark
    g.fix[(x, y)] = (236, 240, 232)


def _band(g, cx, bulge, half_w, edge=True, y0=0, y1=None):
    """竖向弯曲的白带，中间往头部鼓。只画在身体上"""
    y1 = g.h if y1 is None else y1
    ys = [y for y in range(y0, y1) for x in range(g.w) if g.m[y][x] == "B"]
    if not ys:
        return
    top, bot = min(ys), max(ys)
    mid, half = (top + bot) / 2, max(1, (bot - top) / 2)
    for y in range(y0, y1):
        c = cx + bulge * (1 - ((y - mid) / half) ** 2)
        for x in range(g.w):
            if g.m[y][x] not in ("B", "W", "K"):
                continue
            d = abs(x + 0.5 - c)
            if d <= half_w:
                g.m[y][x] = "W"
            elif edge and d <= half_w + 1:
                g.m[y][x] = "K"


def _wag(g, root_x, s):
    """尾鳍以 root_x 为轴横向压缩到 s 倍"""
    out = Grid(g.w, g.h)
    out.fix = dict(g.fix)
    for y in range(g.h):
        for x in range(g.w):
            m = g.m[y][x]
            if m is None or m == "T":
                continue
            out.m[y][x] = m
            out.bias[y][x] = g.bias[y][x]
    for y in range(g.h):
        xs = [x for x in range(g.w) if g.m[y][x] == "T"]
        if not xs:
            continue
        lo = min(xs)
        nl = root_x - round((root_x - lo) * s)
        for x in range(nl, root_x + 1):
            src = root_x - round((root_x - x) / max(s, 0.01))
            if 0 <= src < g.w and g.m[y][src] == "T" and out.m[y][x] is None:
                out.m[y][x] = "T"
                out.bias[y][x] = g.bias[y][src]
    return out


def _frames(g, root_x, pal, alpha, **kw):
    imgs = [pad(render(_wag(g, root_x, s), pal, solid=SOLID, alpha=alpha, **kw))
            for s in FRAMES]
    return sheet(imgs)


# ---------------------------------------------------------------- 小丑鱼
CLOWN = [
    "...........DDDD.DDDD......",
    ".........DDDDDDDDDDDD.....",
    ".........BBBBBBBBBBBBB....",
    ".T.....BBBBBBBBBBBBBBBBB..",
    "TTT...BBBBBBBBBBBBBBBBBBB.",
    "TTTT.BBBBBBBBBBBBBBBBBBBBB",
    "TTTTTBBBBBBBBBBBBBBBBBBBBB",
    "TTTTTBBBBBBBBBBBBBBBBBBBBB",
    "TTTTTBBBBBBBBBBBBBBBBBBBBB",
    "TTTT.BBBBBBBBBBBBBBBBBBBBB",
    "TTT...BBBBBBBBBBBBBBBBBBB.",
    ".T.....BBBBBBBBBBBBBBBBB..",
    ".........BBBBBBBBBBBBB....",
    "...........AAAA..PPP......",
    "............AA....P.......",
]


def clownfish():
    g = from_ascii(CLOWN, {c: c for c in "BTDAP"})
    _band(g, 19.0, 0.8, 1.2)
    _band(g, 12.5, 1.0, 1.6)
    _band(g, 6.5, 0.0, 0.6)
    # 鳍边一圈黑，是小丑鱼的标志
    for y in range(g.h):
        for x in range(g.w):
            if g.m[y][x] in ("T", "D", "A", "P"):
                if any(g.get(x + dx, y + dy) is None
                       for dx, dy in ((0, 1), (0, -1), (1, 0), (-1, 0))) \
                        and (x < 2 or y <= 0 or y >= 13):
                    g.bias[y][x] = -2
    _eye(g, 22, 6)
    orange = ramp("#e8762e")
    pal = {"B": orange, "W": ramp("#efe9dc", dv=0.07, ds=0.02), "K": ramp("#2c1d26", dv=0.05),
           "T": orange, "D": orange, "A": orange, "P": ramp("#f0934a")}
    return _frames(g, 5, pal, {"T": 0.95, "D": 0.95, "A": 0.95, "P": 0.85})


# ---------------------------------------------------------------- 蓝倒吊
def blue_tang():
    w, h = 30, 19
    g = Grid(w, h)
    # 先铺一圈大一号的椭圆当背鳍+臀鳍，再把身体盖上去：鳍沿着背和腹连成一整圈
    g.ellipse(15.5, 9.5, 10.5, 9.2, "D")
    g.poly([(0, 1.5), (3, 4), (6.5, 8), (6.5, 11), (3, 15), (0, 17.5), (2.5, 9.5)], "T")
    g.ellipse(16.5, 9.5, 11.5, 7.0, "B")
    g.poly([(24, 6.5), (30, 8.8), (30, 10.2), (24, 12.5)], "B")
    for y in range(h):
        for x in range(w):
            if g.m[y][x] == "D" and y > 9:
                g.m[y][x] = "A"
    # 「调色板」纹：一个压扁的深色环，后端拖向尾柄
    for y in range(h):
        for x in range(w):
            if g.m[y][x] != "B":
                continue
            u, v = (x + 0.5 - 15.5) / 9.0, (y + 0.5 - 7.6) / 3.4
            ui, vi = (x + 0.5 - 16.5) / 5.6, (y + 0.5 - 7.4) / 1.6
            ring = u * u + v * v <= 1.0 and ui * ui + vi * vi > 1.0
            tail = 6 <= x <= 9 and 8 <= y <= 10
            if ring or tail:
                g.m[y][x] = "K"
    _eye(g, 24, 7)
    blue = ramp("#3d78cc", hue=0.015)
    yel = ramp("#f0c23c")
    pal = {"B": blue, "K": ramp("#1f2a52", dv=0.06), "T": yel,
           "D": ramp("#3466b4"), "A": ramp("#3466b4")}
    return _frames(g, 6, pal, {"T": 0.95, "D": 0.9, "A": 0.9})


# ---------------------------------------------------------------- 神仙鱼
def angelfish():
    w, h = 24, 30
    g = Grid(w, h)
    # 背鳍、臀鳍往后上/后下拖成长三角
    g.poly([(8, 11), (17, 9), (4, 0), (3, 1)], "D")
    g.poly([(8, 19), (17, 21), (4, 30), (3, 29)], "A")
    g.poly([(0, 9), (6, 13), (6, 17), (0, 21), (1.5, 15)], "T")
    g.ellipse(14.5, 15, 9.5, 7.2, "B")
    g.poly([(18, 11), (24, 14.2), (24, 15.8), (18, 19)], "B")
    # 三道竖纹：过眼、身中、尾柄
    for y in range(h):
        for x in range(w):
            if g.m[y][x] == "B" and (x in (19, 12, 13) or x == 6):
                g.m[y][x] = "K"
    for y in range(h):
        for x in range(w):
            if g.m[y][x] in ("D", "A") and x in (8, 9, 12, 13):
                g.bias[y][x] = -2
    _eye(g, 20, 13)
    g.fix[(20, 13)] = (236, 240, 232)
    silver = ramp("#d8d4c4", dv=0.1, ds=0.03)
    fin = ramp("#c9c8bc", dv=0.1)
    pal = {"B": silver, "K": ramp("#3b3a46", dv=0.06), "T": fin, "D": fin, "A": fin}
    return _frames(g, 5, pal, {"T": 0.8, "D": 0.82, "A": 0.82})


# ---------------------------------------------------------------- 蓝绿光鳃鱼（小群游）
CHROMIS = [
    ".....DDD....",
    "T..BBBBBBB..",
    "TTBBBBBBBBB.",
    "TTBBBBBBBBBB",
    "TTBBBBBBBBB.",
    "T..BBBBBBB..",
    ".....AA.....",
]


def chromis():
    g = from_ascii(CHROMIS, {c: c for c in "BTDA"})
    g.fix[(9, 2)] = (24, 20, 30)
    teal = ramp("#5ec2ae", hue=0.015)
    pal = {"B": teal, "T": ramp("#7fd3c0"), "D": teal, "A": teal}
    return _frames(g, 2, pal, {"T": 0.85, "D": 0.9, "A": 0.9}, depth=2.0)


# ---------------------------------------------------------------- 黄蝴蝶鱼
def butterfly():
    w, h = 22, 20
    g = Grid(w, h)
    g.poly([(5, 5), (15, 2), (16, 4), (6, 8)], "D")
    g.poly([(5, 15), (14, 18), (15, 16), (6, 12)], "A")
    g.poly([(0, 7), (4, 9), (4, 11), (0, 13), (1, 10)], "T")
    g.ellipse(11, 10, 7.8, 6.6, "B")
    g.poly([(16, 8), (21, 9.6), (21, 10.4), (16, 12.5)], "B")
    for y in range(h):
        for x in range(w):
            if g.m[y][x] == "B":
                # 过眼黑纹 + 尾部假眼
                if x in (15, 16) and y <= 12:
                    g.m[y][x] = "K"
                elif (x + 0.5 - 7) ** 2 + (y + 0.5 - 6) ** 2 <= 2.3:
                    g.m[y][x] = "K"
                elif x in (13, 14) and 5 <= y <= 15:
                    g.m[y][x] = "W"
    _eye(g, 16, 8, 1)
    yel = ramp("#f2c84a")
    pal = {"B": yel, "K": ramp("#2a2230", dv=0.05), "W": ramp("#ece6d4", dv=0.07),
           "T": ramp("#f5da86"), "D": yel, "A": yel}
    return _frames(g, 4, pal, {"T": 0.8, "D": 0.92, "A": 0.92})


ALL = {
    "clownfish": clownfish,
    "blue_tang": blue_tang,
    "angelfish": angelfish,
    "chromis": chromis,
    "butterfly": butterfly,
}
