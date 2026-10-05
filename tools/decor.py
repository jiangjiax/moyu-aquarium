"""装饰与环境：程序化生成形状，统一交给 px_core 上色。

种子固定，每次生成结果一样；想换长相就换种子。
"""
import math
import random
from PIL import Image
from px_core import Grid, render, ramp, pad, hx

# 水色：整条缸的调子由这几个颜色定。偏青绿、低饱和，看久了不累
WATER_TOP = "#7cc4c8"
WATER_MID = "#4a9aad"
WATER_DEEP = "#2f7390"


def _noise1(seed, n=6):
    rnd = random.Random(seed)
    parts = [(rnd.uniform(0.6, 1.0) / (k + 1), rnd.uniform(0, math.tau), k + 1) for k in range(n)]
    return lambda t: sum(a * math.sin(f * t + p) for a, p, f in parts)


# ---------------------------------------------------------------- 礁石
def rock(w, h, seed, base="#8a8f98", moss=True):
    g = Grid(w, h)
    nz = _noise1(seed, 5)
    cx, rx, ry = w / 2, w / 2 - 0.5, h - 0.5
    for y in range(h):
        for x in range(w):
            a = math.atan2(-(y + 0.5 - h), (x + 0.5 - cx) / rx * ry)
            r = 1.0 + 0.10 * nz(a * 2.0)
            u, v = (x + 0.5 - cx) / rx, (y + 0.5 - h) / ry
            if u * u + v * v <= r * r:
                g.set(x, y, "R")
    rnd = random.Random(seed + 7)
    # 石头表面的裂纹和凹坑：暗一档的短线
    for _ in range(max(2, w // 8)):
        x, y = rnd.randrange(2, w - 2), rnd.randrange(h // 3, h)
        for i in range(rnd.randint(2, 4)):
            if g.get(x, y) == "R":
                g.bias[y][x] = -1
            x += rnd.choice((-1, 1))
            y += rnd.choice((0, 1))
    if moss:
        for x in range(w):
            for y in range(h):
                if g.get(x, y) == "R":
                    if rnd.random() < 0.8 and (x + seed) % 7 < 5:
                        g.set(x, y, "M")
                        if rnd.random() < 0.5 and g.get(x, y + 1) == "R":
                            g.set(x, y + 1, "M")
                    break
    pal = {"R": ramp(base, dv=0.1, hue=0.03, ds=0.02), "M": ramp("#6fae5c", dv=0.1)}
    return pad(render(g, pal, dither={"R"}, depth=4.0, vert=0.3, bottom_inside=True), b=0)


# ---------------------------------------------------------------- 鹿角珊瑚
def branch_coral(w, h, seed, base="#e98aa0"):
    g = Grid(w, h)
    rnd = random.Random(seed)

    def grow(x, y, ang, length, thick, depth):
        for i in range(int(length)):
            x += math.cos(ang) * 0.8
            y += math.sin(ang) * 0.8
            # 往上长的趋势：枝条会慢慢翘起来
            ang += (-math.pi / 2 - ang) * 0.06 + rnd.uniform(-0.08, 0.08)
            g.disc(x, y, thick, "C")
            if depth < 3 and i in (int(length * 0.35), int(length * 0.7)):
                side = 1 if (i + depth + seed) % 2 else -1
                grow(x, y, ang + side * rnd.uniform(0.7, 1.0), length * 0.55,
                     max(0.55, thick - 0.15), depth + 1)
        g.disc(x, y, thick + 0.35, "C", bias=1)

    for i, a0 in enumerate((-2.2, -1.57, -0.95)):
        grow(w / 2 + (i - 1) * 2, h - 0.5, a0 + rnd.uniform(-0.1, 0.1),
             h * (0.8 if i == 1 else 0.6), 0.8, 0)
    pal = {"C": ramp(base, hue=0.03)}
    return pad(render(g, pal, depth=1.3, vert=0.3, bottom_inside=True), b=0)


# ---------------------------------------------------------------- 脑珊瑚
def brain_coral(w, h, seed, base="#94c35e"):
    g = Grid(w, h)
    g.ellipse(w / 2, h, w / 2 - 0.3, h - 0.2, "C")
    rnd = random.Random(seed)
    ph = [rnd.uniform(0, 6) for _ in range(4)]
    for y in range(h):
        for x in range(w):
            if g.get(x, y) == "C":
                # 迷宫纹 = 两组正弦的零值等高线
                v = math.sin(x * 0.9 + ph[0] + math.sin(y * 0.7 + ph[1]) * 1.6) + \
                    math.sin(y * 1.1 + ph[2] + math.sin(x * 0.5 + ph[3]) * 1.3)
                if abs(v) < 0.35:
                    g.bias[y][x] = -1
    pal = {"C": ramp(base, hue=0.03)}
    return pad(render(g, pal, depth=5.0, vert=0.3, bottom_inside=True), b=0)


# ---------------------------------------------------------------- 扇珊瑚
def sea_fan(w, h, seed, base="#b07cc6"):
    g = Grid(w, h)
    rnd = random.Random(seed)
    tips = []

    def grow(x, y, ang, length, depth):
        for _ in range(int(length)):
            x += math.cos(ang)
            y += math.sin(ang)
            ang += rnd.uniform(-0.15, 0.15)
            g.set(int(x), int(y), "C")
        tips.append((x, y))
        if depth < 4:
            for s in (-1, 1):
                grow(x, y, ang + s * rnd.uniform(0.3, 0.6), length * 0.72, depth + 1)

    g.line(w / 2, h - 1, w / 2, h - 3, "C")
    for a0 in (-2.2, -1.57, -0.95):
        grow(w / 2, h - 3, a0, h * 0.36, 2)
    # 横向细网：扇面上稀疏的连接
    for y in range(h):
        row = [x for x in range(w) if g.get(x, y)]
        if len(row) > 1 and y % 4 == 0:
            for x in range(row[0], row[-1] + 1):
                if (x + y) % 2 == 0:
                    g.set(x, y, "C", bias=-1, only_empty=True)
    pal = {"C": ramp(base, hue=0.03)}
    return pad(render(g, pal, depth=1.0, vert=0.6, bottom_inside=True, alpha={"C": 0.95}), b=0)


# ---------------------------------------------------------------- 海葵
def anemone(w, h, seed, base="#e9a0b4", tip="#f6d2dc"):
    g = Grid(w, h)
    rnd = random.Random(seed)
    base_h = max(3, h // 4)
    n = 7
    for i in range(n):
        t = (i + 0.5) / n
        ang = -math.pi / 2 + (t - 0.5) * 2.0
        x, y = w / 2 + (t - 0.5) * w * 0.4, h - base_h
        L = (h - base_h) * rnd.uniform(0.75, 1.0)
        for k in range(int(L)):
            x += math.cos(ang)
            y += math.sin(ang)
            ang += 0.09 * math.sin(k * 0.8 + i)
            g.disc(x, y, 0.9, "A")
        g.disc(x, y, 1.1, "P")
    g.ellipse(w / 2, h, w * 0.3, base_h, "S")
    pal = {"S": ramp("#c7707e"), "A": ramp(base), "P": ramp(tip, dv=0.06)}
    return pad(render(g, pal, depth=1.2, vert=0.45, bottom_inside=True), b=0)


# ---------------------------------------------------------------- 海草（高，会摆）
def kelp(w, h, seed, base="#5fae6e"):
    g = Grid(w, h)
    rnd = random.Random(seed)
    cx = w / 2
    ph = rnd.uniform(0, 6)
    for y in range(h - 1, 1, -1):
        t = (h - y) / h
        x = cx + math.sin(t * 5 + ph) * 1.5 * t
        g.set(int(round(x)), y, "S")
        # 叶片：交替长在两侧，往上斜
        if (h - y) % 5 == 2 and y > 3:
            side = 1 if ((h - y) // 5) % 2 else -1
            L = int(3 + 3 * math.sin(t * math.pi))
            for k in range(1, L + 1):
                g.set(int(round(x + side * k)), y - k // 2, "L")
                g.set(int(round(x + side * k)), y - k // 2 + 1, "L", only_empty=True)
    g.disc(cx + math.sin(5 + ph) * 1.5, 2.5, 1.2, "L")
    pal = {"S": ramp("#4f9a5c"), "L": ramp(base, hue=0.03)}
    return pad(render(g, pal, solid={"S"}, depth=1.0, vert=0.3, bottom_inside=True), b=0)


# ---------------------------------------------------------------- 矮草丛
def grass(w, h, seed, base="#79bf6a"):
    g = Grid(w, h)
    rnd = random.Random(seed)
    for i in range(w // 2 + 2):
        x = rnd.uniform(1, w - 2)
        L = rnd.uniform(h * 0.45, h)
        lean = rnd.uniform(-0.35, 0.35) + (x - w / 2) / w * 0.6
        for k in range(int(L)):
            t = k / L
            g.set(int(round(x + lean * k * (0.5 + t))), h - 1 - k, "G",
                  bias=1 if t > 0.75 else (-1 if t < 0.2 else 0))
    pal = {"G": ramp(base, hue=0.03)}
    return pad(render(g, pal, depth=1.0, vert=0.7, bottom_inside=True), b=0)


# ---------------------------------------------------------------- 小物：贝壳、海星
def starfish():
    g = Grid(9, 6)
    for i in range(5):
        a = -math.pi / 2 + i * math.tau / 5
        g.line(4, 3, 4 + math.cos(a) * 4, 3 + math.sin(a) * 2.6, "S")
    g.disc(4.5, 3.5, 1.3, "S")
    return pad(render(g, {"S": ramp("#e89a5c")}, depth=1.5), b=0)


def shell():
    g = Grid(7, 5)
    g.ellipse(3.5, 5, 3.4, 4.6, "S")
    for y in range(5):
        for x in range(7):
            if g.get(x, y) and x % 2 == 0:
                g.bias[y][x] = -1
    return pad(render(g, {"S": ramp("#efd9c4", dv=0.08)}, depth=2.0, bottom_inside=True), b=0)


# ---------------------------------------------------------------- 沙
def sand_tile(w=128, h=14):
    """可横向平铺的沙层。上沿有起伏，颗粒用两档抖动 + 零星的深浅碎石"""
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    px = img.load()
    r = ramp("#e6d3a3", n=5, dv=0.07, hue=0.02)
    rnd = random.Random(3)
    edge = [2.0 + 1.2 * math.sin(x / w * math.tau * 2) + 0.6 * math.sin(x / w * math.tau * 5 + 1)
            for x in range(w)]
    for x in range(w):
        top = int(round(edge[x]))
        for y in range(top, h):
            d = y - top
            i = 3 if d == 0 else (2 if d < 4 else 1 if d < 9 else 0)
            # 相邻档之间用棋盘抖动过渡
            if d in (3, 4, 8, 9) and (x + y) % 2 == 0:
                i += 1 if d in (4, 9) else 0
            if rnd.random() < 0.05:
                i = max(0, i - 1)
            elif rnd.random() < 0.03:
                i = min(4, i + 1)
            px[x, y] = r[min(4, i)] + (255,)
    # 碎石子
    for _ in range(w // 10):
        x, y = rnd.randrange(w), rnd.randrange(6, h)
        c = ramp(rnd.choice(["#9a8f86", "#b8a48c", "#c98f78"]), n=3)
        px[x, y] = c[1] + (255,)
        if x + 1 < w:
            px[x + 1, y] = c[2] + (255,)
    return img


# ---------------------------------------------------------------- 远景礁岩剪影
def backdrop_tile(w=256, h=46, seed=11):
    """远处的礁岩：一团团圆鼓鼓的岩块叠出来的剪影，只用比水色暗一点的两档，不描边。
    越远越融进水里，所以只看得出形，看不出细节。"""
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    px = img.load()
    rnd = random.Random(seed)
    wr = ramp(WATER_MID, n=5, dv=0.045, hue=0.01, ds=0.02)
    top = [h] * w
    # 岩块：横向可平铺，所以按 x 取模画
    for _ in range(26):
        cx = rnd.uniform(0, w)
        r = rnd.uniform(5, 16)
        cy = h - rnd.uniform(0, 12)
        for dx in range(-int(r) - 1, int(r) + 2):
            x = int(cx + dx) % w
            yy = cy - math.sqrt(max(0.0, r * r - dx * dx)) * 0.8
            top[x] = min(top[x], int(yy))
    # 远处的海草剪影
    for _ in range(7):
        x0 = rnd.randrange(w)
        L = rnd.randint(10, 22)
        ph = rnd.uniform(0, 6)
        for k in range(L):
            x = int(x0 + math.sin(k * 0.3 + ph) * 1.2) % w
            top[x] = min(top[x], h - 8 - k) if k == L - 1 else top[x]
            px[x, max(0, h - 8 - k)] = wr[1] + (255,)
    for x in range(w):
        for y in range(max(0, top[x]), h):
            d = y - top[x]
            # 顶上一两行稍亮（远处的光），往下更暗；交界棋盘格抖动
            i = 2 if d < 2 else 1
            if d >= 7 and ((x + y) % 2 == 0 or d >= 11):
                i = 0
            px[x, y] = wr[i] + (255,)
    return img


def dust():
    img = Image.new("RGBA", (1, 1), (236, 248, 240, 255))
    return img


# ---------------------------------------------------------------- 气泡
def bubble(r):
    d = r * 2 + 1
    img = Image.new("RGBA", (d, d), (0, 0, 0, 0))
    px = img.load()
    for y in range(d):
        for x in range(d):
            dist = math.hypot(x - r, y - r)
            if r - 0.9 <= dist <= r + 0.3:
                px[x, y] = (214, 240, 240, 200)
            elif dist < r - 0.9:
                px[x, y] = (200, 236, 238, 40)
    if r >= 2:
        px[r - 1, r - 1] = (250, 255, 250, 240)
    else:
        px[r, r] = (230, 250, 248, 230)
    return img


# ---------------------------------------------------------------- 玻璃缸框（九宫格）
def frame_ninepatch():
    """24x24，边距 6。上沿是玻璃唇边的两道高光，底座是深色木边。
    角是像素阶梯圆角，圆角外透明。"""
    S, M = 24, 6
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    px = img.load()
    glass_hi = (224, 246, 244, 235)
    glass = (150, 206, 214, 200)
    glass_dk = (70, 128, 146, 220)
    base_top = (58, 66, 92, 255)
    base = (40, 46, 68, 255)
    base_dk = (28, 32, 50, 255)
    corner = [3, 2, 1, 1, 0, 0]   # 每行从外往里空几格
    for y in range(S):
        for x in range(S):
            # 上沿
            if y < M:
                cut = corner[y] if (x < M or x >= S - M) else 0
                xe = x if x < S // 2 else S - 1 - x
                if xe < cut:
                    continue
            if y == 0 or (y == 1 and (x in (corner[1], S - 1 - corner[1]))):
                px[x, y] = glass_dk + ()
            elif y == 1:
                px[x, y] = glass_hi
            elif y == 2:
                px[x, y] = glass
            # 底座：从 S-M 开始
            if y >= S - M:
                yy = y - (S - M)
                px[x, y] = base_top if yy == 0 else (base if yy < M - 1 else base_dk)
                if yy == 1:
                    px[x, y] = (72, 82, 112, 255)
            # 两侧玻璃竖边
            if y >= 2 and y < S - M:
                xe = x if x < S // 2 else S - 1 - x
                if xe == 0:
                    px[x, y] = glass_dk
                elif xe == 1:
                    px[x, y] = glass_hi if x < S // 2 else glass
    return img


# ---------------------------------------------------------------- 按钮图标
def icon(kind):
    """13x13 的小圆钮：深色半透明底 + 四角箭头（展开）或向内箭头（收起）"""
    S = 13
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    px = img.load()
    for y in range(S):
        for x in range(S):
            d = math.hypot(x - 6, y - 6)
            if d <= 6.3:
                px[x, y] = (22, 44, 60, 190)
            if 5.4 < d <= 6.3:
                px[x, y] = (150, 206, 214, 200)
    fg = (228, 244, 240, 255)
    if kind == "expand":
        for (cx, cy, sx, sy) in ((3, 3, 1, 1), (9, 3, -1, 1), (3, 9, 1, -1), (9, 9, -1, -1)):
            for k in range(3):
                px[cx + sx * k, cy] = fg
                px[cx, cy + sy * k] = fg
    else:
        for (cx, cy, sx, sy) in ((5, 5, -1, -1), (7, 5, 1, -1), (5, 7, -1, 1), (7, 7, 1, 1)):
            for k in range(3):
                px[cx + sx * k, cy] = fg
                px[cx, cy + sy * k] = fg
    return img
