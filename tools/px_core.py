"""像素画核心：色带、距离场明暗、描边、出图。

所有素材走同一条管线：
  1. 生成器只决定「每个格子是什么材质」（Grid）
  2. 这里统一做明暗、描边、上色
所以全图光照方向一致、描边规则一致，看起来像同一个人画的。

ROUGH（默认开）：粗糙版。不算光照、不抖动、不做选择性描边——
每种材质平涂一个色，下半截压一档暗，外面统一描一圈近黑的边。鳍也不透明。
make_art.py --fine 关掉它，出回原来那套精细的。
"""
import colorsys
import math
from PIL import Image

# 左上方来光。屏幕 y 向下，所以 y 取负 = 从上面照下来
LIGHT = (-0.55, -0.8, 0.6)
_LN = math.sqrt(sum(c * c for c in LIGHT))
LIGHT = tuple(c / _LN for c in LIGHT)

ROUGH = True
ROUGH_INK = (30, 28, 38)       # 粗糙版的描边：所有东西一个色

BAYER4 = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]


def hx(s):
    s = s.lstrip("#")
    return tuple(int(s[i:i + 2], 16) / 255 for i in (0, 2, 4))


def _toward(h, target, amt):
    d = (target - h + 0.5) % 1.0 - 0.5
    if abs(d) <= amt:
        return target
    return (h + math.copysign(amt, d)) % 1.0


def ramp(base, n=5, dv=0.12, hue=0.022, ds=0.05):
    """以 base 为中间档的色带。暗部色相往蓝紫偏、亮部往暖黄偏（hue shift），
    暗部更饱和、亮部更淡。单纯调明度的色带会发灰发脏，这是像素画和「加黑加白」的区别。"""
    r, g, b = hx(base)
    h, s, v = colorsys.rgb_to_hsv(r, g, b)
    mid = (n - 1) / 2
    out = []
    for i in range(n):
        d = i - mid
        hh = _toward(h, 0.64 if d < 0 else 0.13, abs(d) * hue)
        ss = min(1.0, max(0.0, s - d * ds * (1.6 if d > 0 else 1.0)))
        vv = min(1.0, max(0.0, v + d * dv))
        out.append(tuple(int(round(c * 255)) for c in colorsys.hsv_to_rgb(hh, ss, vv)))
    return out


class Grid:
    """材质网格。m[y][x] = 材质名或 None；bias = 额外明暗档偏移；fix = 直接指定颜色"""

    def __init__(self, w, h):
        self.w, self.h = w, h
        self.m = [[None] * w for _ in range(h)]
        self.bias = [[0] * w for _ in range(h)]
        self.fix = {}

    def inside(self, x, y):
        return 0 <= x < self.w and 0 <= y < self.h

    def set(self, x, y, mat, bias=0, only_empty=False):
        if not self.inside(x, y):
            return
        if only_empty and self.m[y][x] is not None:
            return
        self.m[y][x] = mat
        self.bias[y][x] = bias

    def get(self, x, y):
        return self.m[y][x] if self.inside(x, y) else None

    def disc(self, cx, cy, r, mat, bias=0, only_empty=False):
        for y in range(int(cy - r - 1), int(cy + r + 2)):
            for x in range(int(cx - r - 1), int(cx + r + 2)):
                if (x + 0.5 - cx) ** 2 + (y + 0.5 - cy) ** 2 <= r * r:
                    self.set(x, y, mat, bias, only_empty)

    def ellipse(self, cx, cy, rx, ry, mat, bias=0, only_empty=False):
        for y in range(self.h):
            for x in range(self.w):
                if ((x + 0.5 - cx) / rx) ** 2 + ((y + 0.5 - cy) / ry) ** 2 <= 1.0:
                    self.set(x, y, mat, bias, only_empty)

    def poly(self, pts, mat, bias=0, only_empty=False):
        """多边形填充，按像素中心判断"""
        n = len(pts)
        for y in range(self.h):
            for x in range(self.w):
                px_, py_ = x + 0.5, y + 0.5
                ins = False
                j = n - 1
                for i in range(n):
                    xi, yi = pts[i]
                    xj, yj = pts[j]
                    if (yi > py_) != (yj > py_) and \
                            px_ < (xj - xi) * (py_ - yi) / (yj - yi) + xi:
                        ins = not ins
                    j = i
                if ins:
                    self.set(x, y, mat, bias, only_empty)

    def line(self, x0, y0, x1, y1, mat, bias=0, only_empty=False):
        n = int(max(abs(x1 - x0), abs(y1 - y0))) + 1
        for i in range(n + 1):
            t = i / n
            self.set(int(round(x0 + (x1 - x0) * t)), int(round(y0 + (y1 - y0) * t)),
                     mat, bias, only_empty)


def _dist(g, members, bottom_inside):
    """到形状边缘的倒角距离。bottom_inside：画布下边界算「里面」，
    站在沙上的装饰底边就不会被当成轮廓压暗。"""
    w, h = g.w, g.h
    big = 1e9
    d = [[big if g.m[y][x] in members else 0.0 for x in range(w)] for y in range(h)]

    def at(x, y):
        if 0 <= x < w and 0 <= y < h:
            return d[y][x]
        return big if (bottom_inside and y >= h and 0 <= x < w) else 0.0

    fwd = ((-1, 0, 1.0), (0, -1, 1.0), (-1, -1, 1.414), (1, -1, 1.414))
    bwd = ((1, 0, 1.0), (0, 1, 1.0), (1, 1, 1.414), (-1, 1, 1.414))
    for passes, ys, xs in ((fwd, range(h), range(w)),
                           (bwd, range(h - 1, -1, -1), range(w - 1, -1, -1))):
        for y in ys:
            for x in xs:
                if d[y][x]:
                    for dx, dy, c in passes:
                        v = at(x + dx, y + dy) + c
                        if v < d[y][x]:
                            d[y][x] = v
    return d


def render(g, pal, solid=None, depth=3.0, vert=0.35, dither=(), outline="auto",
           bottom_inside=False, alpha=None, levels=None):
    """把材质网格渲染成 RGBA 图。

    pal:    材质名 -> 色带（暗→亮）
    solid:  参与「立体」计算的材质集合（身体、条纹）；其余当薄片（鳍）只做竖向明暗
    depth:  距离场饱和距离，越大越「圆」
    vert:   竖向明暗占比（顶亮底暗）
    dither: 在相邻两档交界处做 Bayer 抖动的材质（石头、沙这类粗糙表面）
    alpha:  材质名 -> 不透明度（鳍半透明）
    """
    w, h = g.w, g.h
    mats = {g.m[y][x] for y in range(h) for x in range(w)} - {None}
    solid = set(solid) if solid is not None else mats
    thin = mats - solid
    alpha = alpha or {}
    levels = levels or {}
    dist_s = _dist(g, solid, bottom_inside) if solid else None
    dist_t = _dist(g, thin, bottom_inside) if thin else None

    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    px = img.load()

    def hgt(d, x, y):
        v = d[y][x] if 0 <= x < w and 0 <= y < h else 0.0
        return min(v, depth) / depth

    if ROUGH:
        return _render_rough(g, pal, outline)

    for y in range(h):
        for x in range(w):
            mat = g.m[y][x]
            if mat is None:
                continue
            if (x, y) in g.fix:
                c = g.fix[(x, y)]
                px[x, y] = c if len(c) == 4 else c + (255,)
                continue
            d = dist_s if mat in solid else dist_t
            # 距离场当高度图，梯度即法线；圆顶形状
            hz = lambda xx, yy: math.sqrt(max(0.0, 1 - (1 - hgt(d, xx, yy)) ** 2))
            nx = hz(x - 1, y) - hz(x + 1, y)
            ny = hz(x, y - 1) - hz(x, y + 1)
            nz = 0.9
            ln = math.sqrt(nx * nx + ny * ny + nz * nz)
            lam = max(0.0, (nx * LIGHT[0] + ny * LIGHT[1] + nz * LIGHT[2]) / ln)
            # 竖向：以该材质所在列的上下范围算
            ty = y / max(1, h - 1)
            k = (1 - vert) * lam + vert * (1 - ty)
            if mat in thin:
                k = 0.55 * k + 0.25
            r = pal[mat]
            n = levels.get(mat, len(r))
            f = k * (n - 0.01)
            i = int(f)
            if mat in dither and f - i > 0.5 and i + 1 < n:
                if (f - i - 0.5) * 32 > BAYER4[y % 4][x % 4]:
                    i += 1
            i = max(0, min(len(r) - 1, i + g.bias[y][x] + (len(r) - n) // 2))
            a = int(255 * alpha.get(mat, 1.0))
            px[x, y] = tuple(r[i]) + (a,)

    if outline:
        _outline(img, g, pal, outline)
    return img


def _render_rough(g, pal, outline):
    """平涂：中间档一个色，画布下 40% 压暗一档；bias（石头裂纹）照留，其余细节全不要"""
    img = Image.new("RGBA", (g.w, g.h), (0, 0, 0, 0))
    px = img.load()
    for y in range(g.h):
        for x in range(g.w):
            mat = g.m[y][x]
            if mat is None:
                continue
            if (x, y) in g.fix:
                c = g.fix[(x, y)]
                px[x, y] = c[:3] + (255,)
                continue
            r = pal[mat]
            i = len(r) // 2 - (1 if y / max(1, g.h - 1) > 0.6 else 0) + min(0, g.bias[y][x])
            px[x, y] = tuple(r[max(0, min(len(r) - 1, i))]) + (255,)
    if outline:
        for y in range(g.h):
            for x in range(g.w):
                if g.m[y][x] is None and any(
                        g.get(x + dx, y + dy) is not None
                        for dx, dy in ((0, 1), (0, -1), (1, 0), (-1, 0))):
                    px[x, y] = ROUGH_INK + (255,)
    return img


def _outline(img, g, pal, mode):
    """选择性描边：轮廓用相邻材质最暗色再压一档，而不是统一纯黑。
    受光的上沿用稍亮的描边（sel-out），轮廓就不会像贴纸一样硬。"""
    w, h = g.w, g.h
    px = img.load()
    add = []
    for y in range(h):
        for x in range(w):
            if g.m[y][x] is not None:
                continue
            nb = None
            for dx, dy in ((0, 1), (0, -1), (1, 0), (-1, 0)):
                m = g.get(x + dx, y + dy)
                if m is not None:
                    nb = (m, dx, dy)
                    if dy == 1:
                        break
            if nb is None:
                continue
            m, dx, dy = nb
            base = pal[m][0]
            if mode == "auto":
                # 下方有实体 = 这是上沿轮廓，受光
                top_edge = g.get(x, y + 1) is not None and g.get(x, y - 1) is None
                k = 0.78 if top_edge else 0.52
            else:
                k = mode
            c = tuple(int(v * k) for v in base)
            add.append((x, y, c))
    for x, y, c in add:
        px[x, y] = c + (255,)


def pad(img, l=1, t=1, r=1, b=1):
    out = Image.new("RGBA", (img.width + l + r, img.height + t + b), (0, 0, 0, 0))
    out.paste(img, (l, t))
    return out


def from_ascii(rows, legend):
    """字符画 -> Grid。legend: 字符 -> 材质名（或 (材质名, bias)）"""
    h = len(rows)
    w = max(len(r) for r in rows)
    g = Grid(w, h)
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch in legend:
                v = legend[ch]
                if isinstance(v, tuple):
                    g.set(x, y, v[0], v[1])
                else:
                    g.set(x, y, v)
    return g


def sheet(frames):
    w = max(f.width for f in frames)
    h = max(f.height for f in frames)
    out = Image.new("RGBA", (w * len(frames), h), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        out.paste(f, (i * w, 0))
    return out


def preview(images, path, scale=6, bg=(62, 128, 150)):
    """验收用：把一组图放大拼在水色背景上"""
    gap = 4
    W = sum(i.width for i in images) + gap * (len(images) + 1)
    H = max(i.height for i in images) + gap * 2
    out = Image.new("RGBA", (W, H), bg + (255,))
    x = gap
    for i in images:
        out.alpha_composite(i, (x, H - gap - i.height))
        x += i.width + gap
    out = out.resize((W * scale, H * scale), Image.NEAREST)
    out.save(path)
