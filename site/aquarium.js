/* 摸鱼水族馆 · 介绍站点的实时水族箱
 *
 * 这里没有重画一张美术图。水的四档色带、Bayer 抖动、斜光柱、沙面焦散、按像素行摇摆，
 * 全部照抄 godot/shaders/*.gdshader 和 godot/tank.gd 的 _style()。
 * 鱼、珊瑚、礁石、沙、远景、气泡全是 godot/art 里那批 PNG 原图。
 * 连珊瑚礁区开局那 8 条鱼是谁、价格多少，都对着 catalog.gd 抄的。
 */
(function (global) {
  'use strict';

  var ART = global.AQUARIUM_ART || 'assets/art/';   /* 换目录时用 window.AQUARIUM_ART 覆盖 */

  /* ---------------------------------------------------------------- 展区
   * 抄自 godot/tank.gd 的 _style(z)。改这里等于改游戏，改游戏请改那边。 */
  var ZONES = [
    {
      name: '珊瑚礁区',
      water: [[0.56, 0.80, 0.79], [0.40, 0.70, 0.73], [0.29, 0.60, 0.68], [0.22, 0.49, 0.59]],
      ray: 0.07, caustic: 0.16, sand: [1, 1, 1],
      back: [1, 1, 1, 0.5], back2: [1, 1, 1, 0.75],
      decorTint: [1, 1, 1], step: 72,
      groups: {
        reef: [['coral_big', -16, 'back'], ['rock_xl', 4, 'mid'], ['grass_a', 26, 'mid'],
               ['coral_pink', -30, 'mid'], ['rock_xs', 30, 'front']],
        kelp: [['kelp_a', -7, 'back'], ['kelp_b', 5, 'back'], ['rock_m', 0, 'mid'], ['grass_b', -14, 'front']],
        home: [['anemone', 0, 'mid'], ['rock_s', -14, 'mid'], ['shell', 15, 'front']],
        fan: [['fan', -2, 'back'], ['brain', 10, 'mid'], ['grass_b', -12, 'mid']],
        garden: [['coral_coral', -8, 'mid'], ['fan_s', 9, 'back'], ['brain_l', 22, 'mid'],
                 ['rock_s', 4, 'front'], ['starfish', -22, 'front']],
        bits: [['rock_xs', 0, 'mid'], ['grass_b', 7, 'mid']]
      },
      seq: ['kelp', 'reef', 'bits', 'home', 'fan', 'garden', 'bits', 'kelp',
            'home', 'reef', 'bits', 'fan', 'garden', 'home', 'kelp', 'reef']
    },
    {
      name: '淡水草缸区',
      water: [[0.78, 0.87, 0.60], [0.58, 0.76, 0.45], [0.42, 0.64, 0.35], [0.30, 0.52, 0.29]],
      ray: 0.05, caustic: 0.09, sand: [0.93, 0.88, 0.70],
      back: [0.50, 0.82, 0.52, 0.42], back2: [0.56, 0.86, 0.55, 0.66],
      decorTint: [0.94, 1.0, 0.90], step: 78,
      groups: {
        weed: [['kelp_a', -9, 'back'], ['kelp_b', 4, 'back'], ['rock_m', 2, 'mid']],
        plant: [['kelp_b', -7, 'back'], ['kelp_a', 6, 'back'], ['grass_b', -17, 'mid'], ['rock_s', 15, 'front']],
        boulder: [['rock_xl', 0, 'mid'], ['grass_a', -13, 'mid'], ['grass_b', 14, 'mid'], ['shell', 24, 'front']],
        bush: [['kelp_a', -11, 'back'], ['kelp_b', 9, 'back'], ['rock_l', 0, 'mid'], ['grass_a', 19, 'mid']],
        bits: [['rock_xs', 0, 'mid'], ['grass_b', 8, 'mid']]
      },
      seq: ['weed', 'plant', 'bits', 'boulder', 'bush', 'plant',
            'boulder', 'weed', 'bits', 'bush', 'boulder', 'plant']
    },
    {
      name: '深海区',
      water: [[0.10, 0.17, 0.32], [0.07, 0.13, 0.25], [0.05, 0.09, 0.19], [0.03, 0.05, 0.12]],
      ray: 0.0, caustic: 0.0, sand: [0.30, 0.34, 0.44],
      back: [0.16, 0.22, 0.34, 0.5], back2: [0.20, 0.26, 0.38, 0.75],
      decorTint: [0.40, 0.46, 0.60], step: 112,
      groups: {
        garden: [['anemone', 0, 'mid'], ['rock_xl', 10, 'back'], ['rock_xs', -16, 'front']],
        dark: [['rock_l', 0, 'mid'], ['rock_m', -15, 'mid']],
        spire: [['rock_xl', 0, 'mid'], ['rock_s', 15, 'front'], ['rock_xs', -13, 'front']],
        whip: [['fan_s', 2, 'back'], ['rock_m', 12, 'mid'], ['rock_xs', -11, 'front']],
        silt: [['rock_m', 0, 'mid']]
      },
      seq: ['garden', 'silt', 'dark', 'spire', 'silt', 'whip',
            'dark', 'silt', 'spire', 'silt', 'garden', 'dark']
    }
  ];

  /* 抄自 godot/art/meta.json */
  var DECOR = {
    rock_xl: [48, 23, 0, 0], rock_l: [36, 17, 0, 0], rock_m: [24, 12, 0, 0],
    rock_s: [14, 7, 0, 0], rock_xs: [9, 5, 0, 0], coral_big: [34, 41, 0, 0],
    coral_pink: [24, 31, 0, 0], coral_coral: [20, 25, 0, 0], brain: [22, 12, 0, 0],
    brain_l: [30, 16, 0, 0], fan: [32, 31, 1, 3], fan_s: [24, 21, 1, 3],
    anemone: [26, 15, 1, 3], kelp_a: [19, 59, 1, 3], kelp_b: [19, 45, 1, 3],
    grass_a: [20, 13, 1, 3], grass_b: [17, 10, 1, 3], starfish: [11, 7, 0, 0],
    shell: [9, 6, 0, 0]
  };

  /* 抄自 godot/catalog.gd 的 SPECIES，和 tank.gd 的 SPECIES 巡游参数 */
  var SPECIES = [
    { id: 'clownfish', name: '小丑鱼', art: 'clownfish', zone: 0, price: 10, rate: 1.0, speed: 7.0, yPref: 0.85, rest: 0.5, tint: [1, 1, 1] },
    { id: 'chromis', name: '银汉鱼', art: 'chromis', zone: 0, price: 20, rate: 2.0, speed: 9.0, yPref: 0.4, rest: 0.0, tint: [1, 1, 1], school: true },
    { id: 'blue_tang', name: '蓝倒吊', art: 'blue_tang', zone: 0, price: 50, rate: 4.0, speed: 12.0, yPref: 0.45, rest: 0.15, tint: [1, 1, 1] },
    { id: 'angelfish', name: '神仙鱼', art: 'angelfish', zone: 0, price: 200, rate: 12.0, speed: 5.5, yPref: 0.3, rest: 0.4, tint: [1, 1, 1] },
    { id: 'butterfly', name: '蝴蝶鱼', art: 'butterfly', zone: 0, price: 300, rate: 20.0, speed: 8.5, yPref: 0.6, rest: 0.3, tint: [1, 1, 1] },
    { id: 'guppy', name: '孔雀鱼', art: 'chromis', zone: 1, price: 80, rate: 5.0, speed: 9.0, yPref: 0.4, rest: 0.0, tint: [0.78, 1.0, 0.55] },
    { id: 'neon', name: '霓虹灯鱼', art: 'chromis', zone: 1, price: 250, rate: 12.0, speed: 9.0, yPref: 0.4, rest: 0.0, tint: [0.52, 0.94, 1.0], school: true },
    { id: 'discus', name: '七彩神仙', art: 'butterfly', zone: 1, price: 800, rate: 35.0, speed: 8.5, yPref: 0.6, rest: 0.3, tint: [1.0, 0.80, 0.55] },
    { id: 'lantern', name: '灯笼鱼', art: 'chromis', zone: 2, price: 400, rate: 20.0, speed: 9.0, yPref: 0.4, rest: 0.0, tint: [0.55, 0.78, 1.0], school: true },
    { id: 'jelly', name: '水母', art: 'butterfly', zone: 2, price: 1200, rate: 50.0, speed: 8.5, yPref: 0.6, rest: 0.3, tint: [0.70, 0.92, 1.0] },
    { id: 'angler', name: '鮟鱇鱼', art: 'angelfish', zone: 2, price: 4000, rate: 150.0, speed: 5.5, yPref: 0.3, rest: 0.4, tint: [0.42, 0.50, 0.74] }
  ];

  var FISH_META = {
    clownfish: [4, 28, 17], blue_tang: [4, 32, 21], angelfish: [4, 26, 32],
    butterfly: [4, 24, 22], chromis: [4, 14, 9]
  };

  var BY_ID = {};
  SPECIES.forEach(function (s) { BY_ID[s.id] = s; });

  /* ---------------------------------------------------------------- 小工具 */

  var BAYER = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5];
  function bayer(x, y) { return (BAYER[((y & 3) << 2) | (x & 3)] + 0.5) / 16; }
  function smoothstep(e0, e1, x) {
    var t = Math.min(1, Math.max(0, (x - e0) / (e1 - e0)));
    return t * t * (3 - 2 * t);
  }
  function mulberry(seed) {
    return function () {
      seed |= 0; seed = (seed + 0x6D2B79F5) | 0;
      var t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
      t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }
  function lerp(a, b, t) { return a + (b - a) * t; }
  function lerp3(a, b, t) {
    return [lerp(a[0], b[0], t), lerp(a[1], b[1], t), lerp(a[2], b[2], t)];
  }
  function mix4(a, b, t) {
    return [lerp(a[0], b[0], t), lerp(a[1], b[1], t), lerp(a[2], b[2], t), lerp(a[3], b[3], t)];
  }
  function clamp(v, a, b) { return v < a ? a : v > b ? b : v; }

  function makeCanvas(w, h) {
    var c = document.createElement('canvas');
    c.width = Math.max(1, Math.round(w));
    c.height = Math.max(1, Math.round(h));
    var x = c.getContext('2d');
    x.imageSmoothingEnabled = false;
    return c;
  }

  /* 资源只加载一次，全站共用一份 Image */
  var IMG = {};
  function img(name) { return IMG[name] || null; }
  function preload(names, then) {
    var left = names.length;
    if (!left) return then();
    names.forEach(function (n) {
      if (IMG[n]) { left--; return; }
      var im = new Image();
      im.onload = im.onerror = function () { IMG[n] = im; if (--left === 0) then(); };
      im.src = ART + n + '.png';
    });
  }

  /* 同一个鱼图在不同展区可以是不同品种：淡水、深海的鱼暂时是珊瑚礁的图改了色。
     所以染色结果要按 tint 缓存，不能直接画原图。 */
  function tintedFish(art, tint) {
    var key = 'fish:' + art + ':' + tint.join(',');
    if (IMG[key]) return IMG[key];
    var m = FISH_META[art];
    var c = makeCanvas(m[1] * m[0], m[2]);
    var x = c.getContext('2d');
    x.imageSmoothingEnabled = false;
    x.drawImage(img('fish_' + art), 0, 0);
    if (tint[0] !== 1 || tint[1] !== 1 || tint[2] !== 1) {
      var d = x.getImageData(0, 0, c.width, c.height), p = d.data;
      for (var i = 0; i < p.length; i += 4) {
        if (!p[i + 3]) continue;
        p[i] = p[i] * tint[0]; p[i + 1] = p[i + 1] * tint[1]; p[i + 2] = p[i + 2] * tint[2];
      }
      x.putImageData(d, 0, 0);
    }
    IMG[key] = c;
    return c;
  }

  /* 金币和饵料：几像素的小图标，游戏里是 pixel_art.gd 用 Image 直接画的，
     这里照着同一个画法再来一遍。 */
  function buildCoin() {
    var c = makeCanvas(11, 11), x = c.getContext('2d');
    var cx = 5.5, cy = 5.5;
    var disc = function (r, col) {
      x.fillStyle = col;
      for (var y = 0; y < 11; y++) for (var xx = 0; xx < 11; xx++) {
        if (Math.hypot(xx + 0.5 - cx, y + 0.5 - cy) <= r) x.fillRect(xx, y, 1, 1);
      }
    };
    disc(5.0, 'rgb(97,61,13)');
    disc(4.0, 'rgb(252,201,66)');
    disc(2.0, 'rgb(255,240,163)');
    x.fillStyle = 'rgb(255,255,242)';
    x.fillRect(3, 3, 1, 1); x.fillRect(4, 3, 1, 1);
    return c;
  }
  function buildPellet() {
    var c = makeCanvas(4, 4), x = c.getContext('2d');
    x.fillStyle = 'rgb(184,115,51)'; x.fillRect(1, 0, 1, 1);
    x.fillStyle = 'rgb(87,51,23)'; x.fillRect(0, 1, 4, 2);
    x.fillStyle = 'rgb(217,148,71)'; x.fillRect(1, 1, 1, 1);
    x.fillStyle = 'rgb(158,97,43)'; x.fillRect(3, 1, 1, 1);
    x.fillStyle = 'rgb(158,97,43)'; x.fillRect(1, 3, 1, 1);
    x.fillStyle = 'rgb(87,51,23)'; x.fillRect(2, 3, 1, 1);
    return c;
  }

  /* ---------------------------------------------------------------- 水体
   * godot/shaders/caustics.gdshader：两层扭曲网格取最小值，叠加混合，只提亮不压暗 */
  function paintCaustics(ctx, x0, y0, w, h, strength, t) {
    if (strength <= 0) return;
    var tm = t * 0.35;
    ctx.save();
    ctx.beginPath(); ctx.rect(x0, y0, w, h); ctx.clip();
    ctx.globalCompositeOperation = 'lighter';
    var cell = function (px, py, s) {
      var qx = px + Math.sin(py * 0.9 + s) * 0.6;
      var qy = py + Math.cos(px * 0.7 - s * 0.8) * 0.6;
      var gx = Math.abs((qx - Math.floor(qx)) - 0.5);
      var gy = Math.abs((qy - Math.floor(qy)) - 0.5);
      return Math.min(gx, gy);
    };
    for (var y = 0; y < h; y++) {
      var v = 1 - smoothstep(0.1, 0.9, y / h);
      if (v <= 0.01) continue;
      var a = strength * v;
      ctx.fillStyle = 'rgba(255,247,209,' + a.toFixed(3) + ')';
      for (var x = 0; x < w; x++) {
        var c = Math.min(cell(x / 9, y / 3.2, tm), cell(x / 12.33 + 3.1, y / 3.68, -tm * 1.2));
        if (c <= 0.075) ctx.fillRect(x0 + x, y0 + y, 1, 1);
      }
    }
    ctx.restore();
  }

  /* ---------------------------------------------------------------- 装饰摆放
   * 抄自 tank.gd 的 _build_decor / _place：黄金比例抖动，每个位置每次都一样。 */
  function layoutZone(z, zoneW) {
    var st = ZONES[z];
    var n = Math.max(3, Math.floor(zoneW / st.step));
    var dx = zoneW / n;
    var items = [];
    for (var i = 0; i < n; i++) {
      var key = st.seq[i % st.seq.length];
      var jitter = ((i * 0.618) % 1) - 0.5;
      var cx = Math.round(dx * (i + 0.5) + jitter * dx * 0.35);
      st.groups[key].forEach(function (it) {
        var info = DECOR[it[0]];
        if (!info) return;
        var sink = it[2] === 'back' ? 1 : it[2] === 'mid' ? 3 : 5;
        var tint = st.decorTint;
        var back = it[2] === 'back';
        items.push({
          name: it[0], w: info[0], h: info[1], sway: info[2], pad: info[3],
          x: Math.round(cx + it[1] - info[0] * 0.5), sink: sink, idx: i,
          layer: back ? -60 : it[2] === 'mid' ? -20 : 20,
          alpha: back ? 0.8 : 1,
          tint: back ? [tint[0] * 0.8, tint[1] * 0.9, tint[2] * 0.94] : tint
        });
      });
    }
    items.sort(function (a, b) { return a.layer - b.layer || a.x - b.x; });
    return items;
  }

  /* godot/shaders/sway.gdshader：根部不动，越往上偏得越多，每一行只做整格平移 */
  function drawSway(ctx, im, it, x, y, t) {
    var tall = it.name.indexOf('kelp') === 0;
    var amp = tall ? 2.4 : 1.2;
    var speed = tall ? 0.55 : 0.8;
    var wave = tall ? 0.09 : 0.25;
    var phase = x * 0.037 + it.idx;
    for (var row = 0; row < it.h; row++) {
      var h = 1 - (row + 0.5) / it.h;
      var off = Math.round(Math.sin(t * speed + phase - row * wave) * amp * h * h);
      if (!off) { ctx.drawImage(im, 0, row, it.w, 1, x, y + row, it.w, 1); continue; }
      var sx = clamp(-off, 0, it.w - 1), sw = it.w - Math.abs(off);
      if (sw <= 0) continue;
      ctx.drawImage(im, sx, row, sw, 1, x + off + (off > 0 ? 0 : 0), y + row, sw, 1);
    }
  }

  /* ---------------------------------------------------------------- 鱼 */
  function makeFish(sp, zone, x0, zoneW, artH, rnd) {
    if (!sp) return null;
    var m = FISH_META[sp.art];
    var f = {
      sp: sp, m: m, zone: zone, x0: x0, zoneW: zoneW,
      img: tintedFish(sp.art, sp.tint),
      x: x0 + zoneW * (0.15 + rnd() * 0.7),
      y: 0, vx: 0, vy: 0, dir: rnd() < 0.5 ? -1 : 1,
      speed: sp.speed * (0.85 + rnd() * 0.3),
      frame: 0, ft: rnd() * 4, tx: 0, ty: 0, wait: rnd() * 2.5,
      boost: 0, bob: rnd() * 6.28, rest: sp.rest
    };
    f.y = sandTop(artH) - 8 - rnd() * (artH * 0.3);
    f.tx = f.x; f.ty = f.y;
    return f;
  }
  function swimRect(f, artH) {
    return { x: f.x0 + 4, y: 4, w: f.zoneW - 8, h: sandTop(artH) - 1 - 4 };
  }
  function sandTop(artH) { return artH - 11; }

  function stepFish(f, dt, t, artH, food) {
    var r = swimRect(f, artH);
    f.wait -= dt;
    if (f.wait <= 0) {
      f.wait = 1.2 + Math.random() * 2.2;
      f.tx = r.x + Math.random() * r.w;
      f.ty = r.y + Math.random() * r.h * (1 - f.sp.yPref * 0.6) + 6;
      if (Math.random() < f.rest) { f.wait = 0.6 + Math.random(); f.tx = f.x; }
    }
    var gx = f.tx, gy = f.ty;
    var chasing = false;
    if (food) {
      var d = Math.hypot(food.x - f.x, food.y - f.y);
      if (d < 90) { gx = food.x; gy = food.y; chasing = true; f.boost = 1; }
    }
    f.boost = Math.max(0, f.boost - dt * 0.35);
    var dx = gx - f.x, dy = gy - f.y;
    var len = Math.hypot(dx, dy) || 1;
    var sp = f.speed * (chasing ? 1.9 : 1) * (1 + f.boost);
    var acc = chasing ? 5.5 : 1.9;
    f.vx += (dx / len) * sp * acc * dt;
    f.vy += (dy / len) * sp * acc * dt;
    var damp = Math.pow(0.02, dt);
    f.vx *= damp; f.vy *= damp;
    var vl = Math.hypot(f.vx, f.vy);
    if (vl > sp) { f.vx = f.vx / vl * sp; f.vy = f.vy / vl * sp; }
    f.x += f.vx * dt; f.y += f.vy * dt;
    f.bob += dt * 1.7;
    var gy2 = f.y + Math.sin(f.bob) * 0.6;
    if (f.x < r.x) { f.x = r.x; f.vx = Math.abs(f.vx); f.tx = r.x + r.w * (0.4 + Math.random() * 0.5); }
    if (f.x > r.x + r.w) { f.x = r.x + r.w; f.vx = -Math.abs(f.vx); f.tx = r.x + r.w * (0.1 + Math.random() * 0.4); }
    if (gy2 < r.y) { f.y = r.y; f.vy = Math.abs(f.vy); f.ty = r.y + r.h * (0.3 + Math.random() * 0.5); }
    if (gy2 > r.y + r.h) { f.y = r.y + r.h; f.vy = -Math.abs(f.vy); f.ty = r.y + 4 + Math.random() * 12; }
    if (Math.abs(f.vx) > 0.6) f.dir = f.vx > 0 ? 1 : -1;
    var spd = Math.hypot(f.vx, f.vy);
    f.ft += dt * (2 + spd * 0.9);
    if (f.ft >= 4) { f.ft -= 4; f.frame = (f.frame + 1) % f.m[0]; }
    f.speedNow = spd;
  }

  /* ---------------------------------------------------------------- 一只缸 */
  function Tank(canvas, opts) {
    this.cv = canvas;
    this.ctx = canvas.getContext('2d');
    this.opts = opts || {};
    this.zones = this.opts.zones || [0];
    this.fishPerZone = this.opts.fish || {};
    this.water = null; this.decor = null;
    this.fishes = []; this.food = []; this.coins = []; this.bubbles = [];
    this.coins_earned = 0; this.boostT = 0;
    this.visible = true; this.t = 0; this.layerT = 0; this.acc = 0;
    this.running = false;
    this.onEarn = this.opts.onEarn || null;
    this.onBoost = this.opts.onBoost || null;
  }

  Tank.prototype.resize = function (cssW, cssH, scale) {
    var zones = this.zones.length;
    this.scale = scale;
    this.zoneW = Math.max(120, Math.ceil(cssW / scale / zones));
    this.artH = Math.max(60, Math.min(this.opts.maxArtH || 150, Math.round(cssH / scale)));
    var artW = this.zoneW * zones;
    this.artW = artW;
    this.cv.width = artW * scale;
    this.cv.height = this.artH * scale;
    this.cv.style.width = this.cv.width + 'px';
    this.cv.style.height = this.cv.height + 'px';
    this.ctx.imageSmoothingEnabled = false;
    this.water = makeCanvas(artW, this.artH);
    this.decor = makeCanvas(artW, this.artH);
    this.wctx = this.water.getContext('2d');
    this.dctx = this.decor.getContext('2d');
    this.wctx.imageSmoothingEnabled = false;
    this.dctx.imageSmoothingEnabled = false;
    this.wctx.imageSmoothingEnabled = false;
    this._build();
    this.layerT = -1;
  };

  Tank.prototype._build = function () {
    var self = this;
    var rnd = mulberry(20260928);
    this.fishes = []; this.food = []; this.coins = []; this.bubbles = [];
    this.zones.forEach(function (z, zi) {
      var x0 = self.zoneW * zi;
      var list = self.fishPerZone[zi] || self.fishPerZone[z] || [];
      for (var i = 0; i < list.length; i++) {
        var f = makeFish(BY_ID[list[i]], z, x0, self.zoneW, self.artH, rnd);
        if (f) self.fishes.push(f);
      }
      for (var b = 0; b < 7; b++) {
        self.bubbles.push({
          x: x0 + 6 + rnd() * (self.zoneW - 12), y: rnd() * self.artH,
          r: 0.05 + rnd() * 0.06, sp: 5 + rnd() * 7, wob: rnd() * 6.28
        });
      }
    });
  };

  Tank.prototype._paintLayers = function () {
    var t = this.t, i, z, st, x0, zi;
    var W = this.artW, H = this.artH;
    this.wctx.clearRect(0, 0, W, H);
    this.dctx.clearRect(0, 0, W, H);

    /* 水：一次把整张铺满，每区写自己那一段列。
       putImageData 是裸写像素，不吃 clip——早先按区 clip 完再 putImageData，
       三区都写在 0 列上，最后剩的是最后一区的水色，整条长缸只剩左三分之一有水。 */
    var wbuf = this.wctx.createImageData(W, H);
    var wd = wbuf.data;
    for (zi = 0; zi < this.zones.length; zi++) {
      z = this.zones[zi]; st = ZONES[z]; x0 = this.zoneW * zi;
      var zw = this.zoneW;
      for (var y = 0; y < H; y++) {
        var ty = y / H;
        var base;
        if (ty < 0.35) base = lerp3(st.water[0], st.water[1], ty / 0.35);
        else if (ty < 0.62) base = lerp3(st.water[1], st.water[2], (ty - 0.35) / 0.27);
        else base = lerp3(st.water[2], st.water[3], (ty - 0.62) / 0.38);
        var row = y * W + x0;
        for (var x = 0; x < zw; x++) {
          var col = base;
          if (st.ray > 0) {
            var sx = x + x0, sy = y * 0.45;
            var ray = Math.sin((sx + sy) * 0.021 + t * 0.07) * 0.6 + Math.sin((sx + sy) * 0.047 - t * 0.05 + 1.7) * 0.4;
            ray = smoothstep(0.55, 0.95, ray) * (1 - ty * 0.85);
            var r = ray * 2, rl = Math.floor(r);
            r = (r - rl) > bayer(x + 2, y + 1) ? rl + 1 : rl;
            col = [col[0] + 0.85 * st.ray * r, col[1] + 1.0 * st.ray * r, col[2] + 0.95 * st.ray * r];
          }
          var o = (row + x) * 4;
          wd[o] = clamp(col[0], 0, 1) * 255;
          wd[o + 1] = clamp(col[1], 0, 1) * 255;
          wd[o + 2] = clamp(col[2], 0, 1) * 255;
          wd[o + 3] = 255;
        }
      }
    }
    this.wctx.putImageData(wbuf, 0, 0);

    /* 布景：远景、沙、装饰。这几层走 drawImage，clip 算数，逐区画 */
    for (zi = 0; zi < this.zones.length; zi++) {
      z = this.zones[zi]; st = ZONES[z]; x0 = this.zoneW * zi;
      var zw = this.zoneW;

      /* 远景两层：更远的那层翻转，和近的一层错开，看不出是同一张图 */
      var back = img('backdrop');
      if (back) {
        var d1 = this.dctx;
        d1.save();
        d1.beginPath(); d1.rect(x0, 0, zw, H); d1.clip();
        var s1 = mix4(st.back, [0, 0, 0, 0], 0);
        d1.globalAlpha = s1[3];
        var tintA = 'rgb(' + Math.round(s1[0] * 255) + ',' + Math.round(s1[1] * 255) + ',' + Math.round(s1[2] * 255) + ')';
        this._tile(d1, back, x0 - 200, sandTop(H) - 40, zw + 400, tintA, true);
        var s2 = st.back2;
        var tintB = 'rgb(' + Math.round(s2[0] * 255) + ',' + Math.round(s2[1] * 255) + ',' + Math.round(s2[2] * 255) + ')';
        this._tile(d1, back, x0 - 300 + (97 + z * 61) * 0, sandTop(H) - 30, zw + 600, tintB, false, 97 + z * 61);
        d1.restore();
      }

      /* 沙 */
      var sand = img('sand');
      if (sand) {
        var ds = this.dctx;
        ds.save();
        ds.beginPath(); ds.rect(x0, 0, zw, H); ds.clip();
        var sc = st.sand;
        var col = 'rgb(' + Math.round(sc[0] * 255) + ',' + Math.round(sc[1] * 255) + ',' + Math.round(sc[2] * 255) + ')';
        this._tile(ds, sand, x0 - 64, sandTop(H) - 2, zw + 128, col, false);
        paintCaustics(ds, x0, sandTop(H) - 1, zw, 10, st.caustic, t);
        ds.restore();
      }

      /* 装饰：back / mid / front 三层，越靠后越往水色里褪 */
      var items = layoutZone(z, zw);
      for (i = 0; i < items.length; i++) {
        var it = items[i];
        var im = img('deco_' + it.name);
        if (!im) continue;
        var dx = this.dctx;
        dx.save();
        dx.beginPath(); dx.rect(x0, 0, zw, H); dx.clip();
        dx.globalAlpha = it.alpha;
        var tt = it.tint;
        dx.fillStyle = 'rgb(' + Math.round(tt[0] * 255) + ',' + Math.round(tt[1] * 255) + ',' + Math.round(tt[2] * 255) + ')';
        var px = x0 + it.x, py = sandTop(H) + it.sink - it.h;
        if (it.sway) {
          var pad = it.pad;
          var tmp = makeCanvas(it.w, it.h);
          var tc = tmp.getContext('2d');
          tc.imageSmoothingEnabled = false;
          drawSway(tc, im, it, 0, 0, t);
          dx.drawImage(tmp, 0, 0, it.w, it.h, px - pad, py - 0, it.w, it.h);
        } else {
          dx.drawImage(im, px, py);
        }
        dx.restore();
      }
    }
  };

  Tank.prototype._tile = function (ctx, im, x, y, w, tint, flip, srcOff) {
    var iw = im.width;
    var off = srcOff || 0;
    ctx.save();
    ctx.beginPath(); ctx.rect(x, y, w, im.height); ctx.clip();
    var start = -((off % iw));
    for (var px = start; px < w; px += iw) {
      if (flip) {
        ctx.save();
        ctx.translate(x + px, y);
        ctx.scale(-1, 1);
        ctx.drawImage(im, 0, 0);
        ctx.restore();
      } else {
        ctx.drawImage(im, x + px, y);
      }
    }
    ctx.restore();
  };

  Tank.prototype._paint = function () {
    var ctx = this.ctx, s = this.scale, H = this.artH, i;
    ctx.save();
    ctx.imageSmoothingEnabled = false;
    ctx.clearRect(0, 0, this.cv.width, this.cv.height);
    ctx.drawImage(this.water, 0, 0, this.artW, H, 0, 0, this.artW * s, H * s);
    ctx.drawImage(this.decor, 0, 0, this.artW, H, 0, 0, this.artW * s, H * s);

    /* 气泡 */
    var bub = ['bubble_1', 'bubble_2', 'bubble_3'];
    for (i = 0; i < this.bubbles.length; i++) {
      var b = this.bubbles[i];
      var bi = bub[i % 3], im = img(bi);
      if (!im) continue;
      var sxp = b.x + Math.sin(this.t * 1.6 + b.wob) * 2.5;
      var syp = b.y - (this.t * b.sp) % (H + 10);
      if (syp < -8) syp += H + 10;
      ctx.drawImage(im, Math.round(sxp), Math.round(syp), im.width, im.height,
        Math.round(sxp * s), Math.round(syp * s), im.width * s, im.height * s);
    }

    /* 鱼 */
    for (i = 0; i < this.fishes.length; i++) {
      var f = this.fishes[i], m = f.m;
      var fw = m[1], fh = m[2];
      var dx = Math.round(f.x - fw / 2), dy = Math.round(f.y - fh / 2);
      ctx.save();
      ctx.translate((dx + fw / 2) * s, (dy + fh / 2) * s);
      if (f.dir < 0) ctx.scale(-s, s); else ctx.scale(s, s);
      ctx.drawImage(f.img, f.frame * fw, 0, fw, fh, -fw / 2, -fh / 2, fw, fh);
      ctx.restore();
    }

    /* 饵料 */
    var pel = IMG.__pellet;
    for (i = 0; i < this.food.length; i++) {
      var p = this.food[i];
      if (!pel) break;
      ctx.drawImage(pel, Math.round(p.x) * s, Math.round(p.y) * s, 4 * s, 4 * s);
    }
    /* 金币 */
    var coin = IMG.__coin;
    for (i = 0; i < this.coins.length; i++) {
      var c = this.coins[i];
      if (!coin) break;
      var wob = Math.sin(this.t * 6 + c.ph) * 0.5;
      ctx.drawImage(coin, Math.round(c.x - 5.5) * s, Math.round(c.y - 5.5 + wob) * s, 11 * s, 11 * s);
    }
    ctx.restore();
  };

  Tank.prototype.update = function (dt) {
    this.t += dt;
    if (this.t - this.layerT > 0.11) { this.layerT = this.t; this._paintLayers(); }
    var i, H = this.artH;
    /* 投下去的饵：先浮一下，再加速沉到终端速度，边沉边晃，落底停在沙上 */
    for (i = this.food.length - 1; i >= 0; i--) {
      var p = this.food[i];
      p.age += dt;
      if (p.age < 0.5) { p.y -= dt * 6; }
      else {
        p.vy = Math.min(9, p.vy + dt * 26);
        p.y += p.vy * dt;
        p.x += Math.sin(p.age * 7) * dt * 2.2;
      }
      var floorY = sandTop(H) - 4;
      if (p.y >= floorY) { p.y = floorY; p.vy = 0; }
    }
    /* 鱼 */
    for (i = 0; i < this.fishes.length; i++) {
      var f = this.fishes[i];
      var near = null, best = 1e9;
      for (var j = 0; j < this.food.length; j++) {
        var q = this.food[j];
        if (q.taken) continue;
        var d = Math.abs(q.x - f.x);
        if (d < best) { best = d; near = q; }
      }
      stepFish(f, dt, this.t, H, near);
      if (near) {
        var dd = Math.hypot(near.x - f.x, near.y - f.y);
        if (dd < (f.m[1] / 2 + 4) && !near.taken) {
          near.taken = true;
          this.coins.push({ x: near.x, y: near.y - 2, ph: Math.random() * 6.28, life: 0, vy: -7 });
          if (this.boostT <= 0) { this.boostT = 120; if (this.onBoost) this.onBoost(120); }
        }
      }
    }
    for (i = this.food.length - 1; i >= 0; i--) if (this.food[i].taken) this.food.splice(i, 1);
    /* 金币：两种形态金币落到沙上 2.5 秒都会自己进钱包 */
    for (i = this.coins.length - 1; i >= 0; i--) {
      var c = this.coins[i];
      c.life += dt;
      c.vy = Math.min(0, c.vy + dt * 22);
      c.y += c.vy * dt;
      if (c.y > sandTop(H) - 6) { c.y = sandTop(H) - 6; c.vy = 0; }
      if (c.life > 2.5) {
        this.coins_earned += 1;
        if (this.onEarn) this.onEarn(1, c.x, c.y);
        this.coins.splice(i, 1);
      }
    }
    if (this.boostT > 0) this.boostT = Math.max(0, this.boostT - dt);
  };

  Tank.prototype.feed = function (artX, artY) {
    this.food.push({ x: artX, y: Math.max(2, artY), vy: 0, age: 0, taken: false });
    if (this.food.length > 6) this.food.shift();
  };

  Tank.prototype.render = function (dt) {
    if (!this.water) return;          // 还没 resize，先别画
    this.update(dt);
    this._paint();
  };

  /* ---------------------------------------------------------------- 驱动 */
  var tanks = [];
  var reduce = global.matchMedia && global.matchMedia('(prefers-reduced-motion: reduce)').matches;
  var last = 0, raf = 0;

  function loop(now) {
    raf = requestAnimationFrame(loop);
    var dt = Math.min(0.05, (now - last) / 1000) || 0.016;
    last = now;
    for (var i = 0; i < tanks.length; i++) {
      if (tanks[i].visible) tanks[i].render(dt);
    }
  }
  function start() {
    if (raf || reduce) return;
    last = performance.now();
    raf = requestAnimationFrame(loop);
  }
  function stop() { if (raf) { cancelAnimationFrame(raf); raf = 0; } }

  function addTank(t) {
    tanks.push(t);
    if (!reduce) t.render(0.016);
    else t.render(0);
    return t;
  }

  function boot(then) {
    var names = ['backdrop', 'sand', 'bubble_1', 'bubble_2', 'bubble_3'];
    Object.keys(DECOR).forEach(function (k) { names.push('deco_' + k); });
    Object.keys(FISH_META).forEach(function (k) { names.push('fish_' + k); });
    preload(names, function () {
      IMG.__coin = buildCoin();
      IMG.__pellet = buildPellet();
      if (then) then();
    });
  }

  global.Aquarium = {
    ZONES: ZONES, SPECIES: SPECIES, BY_ID: BY_ID, FISH_META: FISH_META, DECOR: DECOR,
    Tank: Tank, addTank: addTank, boot: boot, start: start, stop: stop,
    sandTop: sandTop, img: img, reduce: reduce, mix4: mix4, lerp3: lerp3
  };
})(window);
