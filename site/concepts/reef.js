/* ═══════════════════════════════════════════════════════════════════════════
   reef.js · 概念页共用的水下交互引擎
   泡泡（鱼吐的 / 沙底冒的 / 按钮按出的）、戳破后的 watercolor 提示、
   鱼的行为扩展（roll 沙底翻滚 / graze 啄沙 / follow 追指针 / startle 炸开逃跑）。
   不引框架，不监听 scroll。鱼的行为挂在 Aquarium 自己的 update 上。
   ═══════════════════════════════════════════════════════════════════════════ */
(function (global) {
  'use strict';

  var A = global.Aquarium;
  var reduce = A.reduce;

  /* ------------------------------------------------------------------ 提示文案
     同一句 12 秒内不重复，不然满屏都是同一朵水彩。 */
  var TIPS = [
    '点水面撒饵，最近的鱼会先赶过来',
    '金币不用点，落到沙上 2.5 秒自己进钱包',
    '空格展开，Esc 收起，不出声不留窗口',
    '横向拖一下就能逛完整条缸',
    '每区容量 8 条，扩到 12 要 300 乘展区序号',
    '鱼吃饱之后两分钟产币翻倍',
    '离线最多按 8 小时结算',
    '深海区光柱全关，最贵的一条产币 150',
    '淡水没有珊瑚，那几张鱼图是改了色的',
    '点一条鱼，它会吐一串泡泡'
  ];
  var lastTip = -1, usedAt = {};

  function tipText() {
    var now = performance.now() / 1000, i;
    for (var k = 0; k < 24; k++) {
      i = (lastTip + 1 + k) % TIPS.length;
      if (i === lastTip) continue;
      if (usedAt[i] && now - usedAt[i] < 12) continue;
      lastTip = i; usedAt[i] = now;
      return TIPS[i];
    }
    return TIPS[(lastTip + 1) % TIPS.length];
  }

  /* ------------------------------------------------------------------ watercolor 提示
     三层径向渐变叠色 + screen 混合，纸纹用 4px 网点，洇开一次再淡掉。 */
  function tip(x, y, text) {
    if (reduce) return;
    var el = document.createElement('div');
    el.className = 'tip';
    el.style.setProperty('--x', Math.round(x) + 'px');
    el.style.setProperty('--y', Math.round(y) + 'px');
    el.innerHTML = '<i class="tip-blob"></i><span class="tip-txt px"></span>';
    el.querySelector('.tip-txt').textContent = text || tipText();
    document.body.appendChild(el);
    setTimeout(function () { el.remove(); }, 3400);
  }
  global.__reefTip = tip;

  /* ------------------------------------------------------------------ 泡泡层
     页面级泡泡画在一张 fixed 的 canvas 上。命中检测在 window 上做，
     所以泡泡挡不住任何点击。
     泡泡用项目里那三张像素圆（3x3 / 5x5 / 7x7，自带高光），
     不要拿 fillRect 画方块，那是像素圆该有的样子。 */
  var cv, cx, bubbles = [], pops = [], dpr = 1, W = 0, H = 0, BUB = null;

  function bubSprites() {
    if (BUB) return BUB;
    BUB = ['bubble_1', 'bubble_2', 'bubble_3'].map(function (n) { return rim(A.img(n)); }).filter(Boolean);
    return BUB;
  }

  /* 原图是浅色环，落在亮水上等于看不见。给每个不透明像素（alpha>=100）外面补一圈暗边，
     环还是环，泡还是透的，但深水亮水都读得出形状。 */
  function rim(im) {
    if (!im) return null;
    var w = im.width + 2, h = im.height + 2;
    var tmp = document.createElement('canvas');
    tmp.width = im.width; tmp.height = im.height;
    var tx = tmp.getContext('2d');
    tx.drawImage(im, 0, 0);
    var d;
    try { d = tx.getImageData(0, 0, im.width, im.height).data; } catch (e) { return im; }
    var c = document.createElement('canvas');
    c.width = w; c.height = h;
    var x = c.getContext('2d');
    var out = x.createImageData(w, h);
    var px, py, dx, dy, X, Y, o;
    for (py = 0; py < im.height; py++) {
      for (px = 0; px < im.width; px++) {
        if (d[(py * im.width + px) * 4 + 3] < 100) continue;   /* 中间那层 alpha 40 的玻璃不算 */
        for (dy = -1; dy <= 1; dy++) {
          for (dx = -1; dx <= 1; dx++) {
            X = px + dx + 1; Y = py + dy + 1;
            if (X < 0 || Y < 0 || X >= w || Y >= h) continue;
            o = (Y * w + X) * 4;
            if (out[o + 3] < 140) { out[o] = 6; out[o + 1] = 26; out[o + 2] = 34; out[o + 3] = 165; }
          }
        }
      }
    }
    x.putImageData(out, 0, 0);
    x.drawImage(im, 1, 1);
    return c;
  }

  function sizeCanvas() {
    dpr = Math.min(2, global.devicePixelRatio || 1);
    W = global.innerWidth; H = global.innerHeight;
    cv.width = W * dpr; cv.height = H * dpr;
    cv.style.width = W + 'px'; cv.style.height = H + 'px';
    cx.setTransform(dpr, 0, 0, dpr, 0, 0);
    cx.imageSmoothingEnabled = false;
  }

  function spawn(x, y, opts) {
    opts = opts || {};
    var sp = bubSprites();
    /* 有图就用图：按泡的大小挑一张，再乘一个整数倍放大，坐标全部对齐整格 */
    var idx = (opts.r || 4) < 3 ? 0 : (opts.r || 4) < 5 ? 1 : 2;
    var im = sp.length ? sp[idx % sp.length] : null;
    var k = opts.scale || (Math.random() < 0.25 ? 3 : 2);
    var size = im ? im.width * k : 6;
    bubbles.push({
      x: x, y: y,
      im: im, k: k, size: size,
      r: size / 2,
      sp: opts.sp || (10 + Math.random() * 16),
      wob: Math.random() * 6.28,
      hue: opts.hue || 0,
      born: performance.now()
    });
    if (bubbles.length > 160) bubbles.shift();
  }

  /* 一串泡：鱼吐泡、按钮按出的都是它 */
  function burst(x, y, n, opts) {
    n = n || 5;
    for (var i = 0; i < n; i++) {
      spawn(x + (Math.random() - 0.5) * 14, y + (Math.random() - 0.5) * 8, opts);
    }
  }
  /* 破泡的那一下：一圈像素环。整圈只落在整格上，不做抗锯齿。 */
  function popRing(x, y, r) {
    pops.push({ x: x, y: y, r0: r, t: 0 });
  }

  function pxRing(x, y, r, color) {
    cx.fillStyle = color;
    var n = Math.max(10, Math.round(r * 7));
    for (var i = 0; i < n; i++) {
      var a = (i / n) * Math.PI * 2;
      cx.fillRect(Math.round(x + Math.cos(a) * r), Math.round(y + Math.sin(a) * r), 2, 2);
    }
  }

  /* 环也是：先一层暗的再一层亮的，亮水上也看得见轮廓 */
  function ring2(x, y, r, alpha) {
    pxRing(x + 1, y + 1, r, 'rgba(6,26,34,' + (0.5 * alpha).toFixed(3) + ')');
    pxRing(x, y, r, 'rgba(226,246,250,' + (0.95 * alpha).toFixed(3) + ')');
  }

  function drawBubbles(dt) {
    cx.clearRect(0, 0, W, H);
    var i, b;
    for (i = bubbles.length - 1; i >= 0; i--) {
      b = bubbles[i];
      b.y -= b.sp * dt;
      b.x += Math.sin(performance.now() / 700 + b.wob) * 8 * dt;
      if (b.y < -12) { bubbles.splice(i, 1); continue; }
      var px = Math.round(b.x - b.size / 2), py = Math.round(b.y - b.size / 2);
      if (b.im) {
        cx.drawImage(b.im, 0, 0, b.im.width, b.im.height, px, py, b.size, b.size);
      } else {
        /* 图没到位之前先拿小方块顶着，总比没有强 */
        cx.fillStyle = 'rgba(207,238,242,0.26)';
        cx.fillRect(px, py, b.size, b.size);
      }
    }
    for (i = pops.length - 1; i >= 0; i--) {
      var p = pops[i];
      p.t += dt;
      var k2 = p.t / 0.28;
      if (k2 >= 1) { pops.splice(i, 1); continue; }
      ring2(p.x, p.y, Math.round(p.r0 + k2 * 18), 1 - k2);
    }
  }

  /* ------------------------------------------------------------------ 鱼的行为
     Aquarium 的 AI 靠 f.tx / f.ty / f.wait 驱动，想接管只要每帧改这三个值。
     画鱼的那段循环也接管一下，好加翻滚的压扁和惊掉的形变。 */
  var EMPTY = [];
  var origUpdate = A.Tank.prototype.update;
  var origPaint = A.Tank.prototype._paint;
  var pointer = { x: -999, y: -999, on: false, t: 0 };
  var tanks = [];

  A.Tank.prototype._reef = function (dt) {
    var H = this.artH, sand = A.sandTop(H) - 4;
    this.t_ = (this.t_ || 0) + dt;

    /* 沙底自己会冒慢泡 */
    if (Math.random() < dt * 2.2) {
      spawnArt(this, 6 + Math.random() * (this.zoneW - 12), sand, { sp: 6, r: 2 + Math.random() * 2 });
    }

    for (var i = 0; i < this.fishes.length; i++) {
      var f = this.fishes[i];
      f.behavior = f.behavior || 'roam';
      f.stateT = (f.stateT || 0) + dt;

      /* follow：追指针三秒。指针不在就站着不动。 */
      if (f.behavior === 'follow' && f.stateT < 3) {
        f.wait = 0; f.boost = 0.6;
        f.tx = f.px != null ? f.px : f.x;
        f.ty = f.py != null ? f.py : f.y;
        continue;
      }
      if (f.behavior !== 'roam' && f.stateT > (f.behavior === 'startle' ? 1.1 : f.behavior === 'roll' ? 2.6 : 1.8)) {
        f.behavior = 'roam'; f.stateT = 0; f.sq = 1; f.sqx = 1;
      }
      if (f.behavior === 'roam') {
        f.sq = 1; f.sqx = 1;
        /* 贴到沙底的鱼会自己开始翻滚或者嘴沙。没人点它也会动。 */
        if (f.y > sand - f.m[2] * 0.6 && Math.abs(f.vy) < 4) {
          if (Math.random() < dt * 0.22) { f.behavior = 'roll'; f.stateT = 0; f.rollDir = Math.random() < 0.5 ? 1 : -1; }
          else if (Math.random() < dt * 0.5) { f.behavior = 'graze'; f.stateT = 0; f.rollDir = Math.random() < 0.5 ? 1 : -1; }
        }
        continue;
      }

      var r = { x: f.x0 + 4, w: f.zoneW - 8 };
      if (f.behavior === 'startle') {
        f.wait = 0; f.boost = 1.4;
        var ax0 = f.sx == null ? f.x : f.sx, ay0 = f.sy == null ? f.y : f.sy;
        f.tx = f.x + (f.x - ax0) * 3;
        f.ty = f.y - 10;
        f.sx = f.x; f.sy = f.y;
        f.sqx = 1.18; f.sq = 0.82;
        if (f.stateT < dt * 2 && Math.random() < 0.6) {
          spawnArt(this, f.x, f.y, { sp: 14, r: 2, n: 2 });
        }
      } else if (f.behavior === 'roll') {
        /* 贴沙面横着滚。真旋转会把像素拧斜，所以用压扁 + 上下两格来演。 */
        f.wait = 0;
        f.ty = sand - f.m[2] * 0.34;
        if (f.x < r.x + 4 || f.x > r.x + r.w - 4 || Math.random() < dt * 0.5) {
          f.rollDir = -(f.rollDir || 1);
          f.tx = f.rollDir > 0 ? r.x + r.w - 6 : r.x + 6;
        }
        var q = Math.floor((this.t_ * 6 + f.bob) % 4) / 4;      /* 0,.25,.5,.75 四档 */
        f.sq = q < 0.25 ? 0.5 : q < 0.5 ? 0.75 : q < 0.75 ? 1 : 0.75;  /* 只在 0.25 的倍数上跳 */
        f.sqx = f.sq < 1 ? 1.25 : 1;
        if (Math.random() < dt * 3) spawnArt(this, f.x, sand, { sp: 5, r: 2 });
      } else if (f.behavior === 'graze') {
        f.wait = 0;
        f.ty = sand - f.m[2] * 0.75 + Math.sin(this.t_ * 5) * 1.5;
        f.tx = f.rollDir > 0 ? Math.min(f.x + 6, r.x + r.w - 6) : Math.max(f.x - 6, r.x + 6);
        if (Math.random() < dt * 4) spawnArt(this, f.x, sand, { sp: 7, r: 2 });
      }
    }
  };

  /* 缸内泡泡：走 tank 自己的 bubbles 数组，_paint 会画 */
  function spawnArt(tank, x, y, opts) {
    opts = opts || {};
    var n = opts.n || 1;
    for (var i = 0; i < n; i++) {
      tank.bubbles.push({
        x: x + (Math.random() - 0.5) * 6,
        y: y,
        wob: Math.random() * 6.28,
        sp: opts.sp || 10
      });
    }
    if (tank.bubbles.length > 40) tank.bubbles.shift();
  }

  A.Tank.prototype.update = function (dt) {
    this._reef(dt);
    origUpdate.call(this, dt);
  };

  /* 接管画鱼那一段，好加翻滚压扁。原来的循环先空跑一次。 */
  A.Tank.prototype._paint = function () {
    var keep = this.fishes;
    this.fishes = EMPTY;
    origPaint.call(this);
    this.fishes = keep;

    var ctx = this.ctx, s = this.scale, i;
    for (i = 0; i < this.fishes.length; i++) {
      var f = this.fishes[i], m = f.m, fw = m[1], fh = m[2];
      var cx0 = Math.round(f.x), cy0 = Math.round(f.y);
      ctx.save();
      ctx.translate(cx0 * s, cy0 * s);
      if (f.dir < 0) ctx.scale(-s, s); else ctx.scale(s, s);
      var sx = f.sqx || 1, sy = f.sq || 1;
      if (sx !== 1 || sy !== 1) ctx.scale(sx, sy);
      ctx.drawImage(f.img, f.frame * fw, 0, fw, fh, -fw / 2, -fh / 2, fw, fh);
      ctx.restore();
    }
  };

  /* ------------------------------------------------------------------ 建缸 */
  function tank(shell, zones, fish, opts) {
    opts = opts || {};
    var canvas = shell.querySelector('canvas');
    var t = new A.Tank(canvas, { zones: zones, fish: fish, onEarn: opts.onEarn, onBoost: opts.onBoost });
    A.addTank(t);
    tanks.push(t);

    /* 一页里可能挂七八只缸，只跑看得见的那几只。
       这里不用 IntersectionObserver 算位置，改成每 400ms 量一次矩形：
       观察器在多 canvas 的页面上容易推后，量矩形最稳，也不算 scroll 监听。 */
    var refresh = function () {
      if (opts.always) { t.visible = true; return; }
      var r = shell.getBoundingClientRect();
      t.visible = liveOf(shell) && r.bottom > -240 && r.top < global.innerHeight + 240;
    };
    refreshers.push(refresh);
    refresh();

    function fit() {
      var w = shell.clientWidth, h = shell.clientHeight;
      if (w < 2 || h < 2) return;
      var sc = opts.scale || Math.max(2, Math.min(5, Math.round(h / (opts.px || 84))));
      /* 满屏当背景的缸要够高，artH 的上限用 maxArtH 放开 */
      t.opts.maxArtH = opts.tall ? 240 : 150;
      t.resize(w, h, sc);
      /* 行内样式比样式表强，所以画布多大在这儿定死：
         默认铺满外壳；长缸那种要按真实像素宽排的，natural 让它用自己的尺寸。 */
      if (opts.natural && w > 700) {
        t.cv.style.width = (t.artW * t.scale) + 'px';
        t.cv.style.height = (t.artH * t.scale) + 'px';
      } else {
        t.cv.style.width = '100%';
        t.cv.style.height = '100%';
      }
    }
    fit();
    if (global.ResizeObserver) new ResizeObserver(fit).observe(shell);
    else global.addEventListener('resize', fit);

    /* 点水里：撒饵 + 戳鱼 + 戳泡泡 */
    canvas.addEventListener('pointerdown', function (ev) {
      var r = canvas.getBoundingClientRect();
      var ax = (ev.clientX - r.left) / r.width * t.artW;
      var ay = (ev.clientY - r.top) / r.height * t.artH;
      pointer.ax = ax; pointer.ay = ay; pointer.px = ax; pointer.py = ay; pointer.on = true;
      pointer.t = performance.now();

      /* 先看有没有泡泡 */
      var H = t.artH, hit = -1, bestD = 1e9, i;
      for (i = 0; i < t.bubbles.length; i++) {
        var b = t.bubbles[i];
        var by = b.y - (t.t * b.sp) % (H + 10);
        if (by < -8) by += H + 10;
        var d = Math.hypot(b.x - ax, by - ay);
        if (d < 7 && d < bestD) { bestD = d; hit = i; }
      }
      if (hit >= 0) {
        var hb = t.bubbles.splice(hit, 1)[0];
        var hy = hb.y - (t.t * hb.sp) % (H + 10);
        if (hy < -8) hy += H + 10;
        var sxr = hb.x / t.artW * r.width + r.left;
        var syr = hy / t.artH * r.height + r.top;
        popRingAt(sxr, syr, 8);
        tip(sxr, syr);
        return;
      }

      /* 再看有没有鱼 */
      for (i = 0; i < t.fishes.length; i++) {
        var f = t.fishes[i];
        if (Math.hypot(f.x - ax, f.y - ay) < f.m[1] * 0.6 + 5) {
          f.sx = f.x; f.sy = f.y;
          f.behavior = 'startle'; f.stateT = 0;
          for (var k = 0; k < 6; k++) {
            spawnArt(t, f.x, f.y, { sp: 16, r: 2, n: 1 });
          }
          burst(r.left + f.x / t.artW * r.width, r.top + f.y / t.artH * r.height, 3, { sp: 20, r: 2 });
          if (t.coins.length < 6) t.coins.push({ x: f.x, y: f.y - 2, ph: Math.random() * 6.28, life: 0, vy: -7 });
          return;
        }
      }

      /* 都没有就撒饵 */
      if (ay > A.sandTop(t.artH) - 2) ay = A.sandTop(t.artH) - 8;
      t.feed(ax, ay);
      var n = 3 + ((Math.random() * 3) | 0);
      burst(r.left + ax / t.artW * r.width, r.top + ay / t.artH * r.height, n, { sp: 12, r: 3 });
    });

    canvas.addEventListener('pointermove', function (ev) {
      var r = canvas.getBoundingClientRect();
      pointer.ax = (ev.clientX - r.left) / r.width * t.artW;
      pointer.ay = (ev.clientY - r.top) / r.height * t.artH;
      pointer.px = pointer.ax; pointer.py = pointer.ay;
      pointer.on = true;
    });
    canvas.addEventListener('pointerleave', function () { pointer.on = false; });

    return t;
  }

  function popRingAt(x, y, r) { popRing(x, y, r); }

  /* 页面级：鼠标在某元素附近点一下，从那儿冒一串泡 */
  function bubbly(el, n) {
    if (!el) return;
    el.addEventListener('pointerdown', function () {
      var r = el.getBoundingClientRect();
      burst(r.left + r.width / 2, r.top + r.height / 2, n || 5, { sp: 14, r: 3 });
    });
  }

  /* ------------------------------------------------------------------ 切节
     不监听 scroll：用观察器记住哪一节正在看，给它加 is-live。
     面板从水里浮上来靠 CSS 的阶梯擦除，同时从台沿真冒一串泡。 */
  var refreshers = [];
  function liveOf(el) {
    var s = el.closest ? el.closest('[data-terrace]') : null;
    return !s || s.classList.contains('is-live');
  }

  function sections(sel, onEnter) {
    var nodes = document.querySelectorAll(sel);
    if (!nodes.length) return;
    if (A.reduce || !('IntersectionObserver' in window)) {
      nodes.forEach(function (n) { n.classList.add('is-live'); });
      refreshers.forEach(function (f) { f(); });
      return;
    }
    var io = new IntersectionObserver(function (es) {
      var changed = false;
      es.forEach(function (e) {
        var live = e.isIntersecting && e.intersectionRatio > 0.3;
        if (live === e.target.classList.contains('is-live')) return;
        e.target.classList.toggle('is-live', live);
        changed = true;
        if (live && onEnter) onEnter(e.target);
      });
      if (changed) refreshers.forEach(function (f) { f(); });
    }, { threshold: [0, 0.15, 0.3, 0.6, 0.9] });
    nodes.forEach(function (n) { io.observe(n); });
  }

  /* ------------------------------------------------------------------ 起 */
  function boot() {
    cv = document.createElement('canvas');
    cv.id = 'bubbles';
    document.body.appendChild(cv);
    cx = cv.getContext('2d');
    sizeCanvas();
    global.addEventListener('resize', sizeCanvas);

    /* 戳页面上的泡泡 */
    global.addEventListener('pointerdown', function (ev) {
      var x = ev.clientX, y = ev.clientY, i;
      for (i = bubbles.length - 1; i >= 0; i--) {
        var b = bubbles[i];
        if (Math.hypot(b.x - x, b.y - y) < b.r + 6) {
          bubbles.splice(i, 1);
          popRing(x, y, b.r);
          tip(x, y);
          return;
        }
      }
    });

    var last = performance.now(), amb = 0;
    /* 开场先铺一层，不然前十几秒水里是空的 */
    for (var s0 = 0; s0 < 18; s0++) {
      spawn(Math.random() * W, Math.random() * H, { sp: 6 + Math.random() * 10, r: 3 + Math.random() * 4 });
    }
    function frame(now) {
      var dt = Math.min(0.05, (now - last) / 1000) || 0.016;
      last = now;
      /* 环境泡：整页慢慢往上冒，一次两三个，不然一屏里没几颗 */
      amb -= dt;
      if (amb <= 0) {
        amb = 0.45 + Math.random() * 0.8;
        var bx = Math.random() * global.innerWidth;
        var by = global.innerHeight + 8;
        spawn(bx, by, { sp: 7 + Math.random() * 9, r: 3 + Math.random() * 4 });
        spawn(bx + (Math.random() - 0.5) * 90, by, { sp: 7 + Math.random() * 9, r: 3 + Math.random() * 4 });
        if (Math.random() < 0.4) spawn(Math.random() * global.innerWidth, by, { sp: 7 + Math.random() * 9, r: 3 + Math.random() * 4 });
      }
      drawBubbles(dt);
      requestAnimationFrame(frame);
    }
    if (!reduce) requestAnimationFrame(frame);
    else { cv.remove(); }

    /* 素材到位之前 addTank 只画了一次空的，从这里开始每帧跑 */
    A.start();

    /* 位置量一遍：谁在屏里、谁那一节已经浮上来 */
    setInterval(function () { refreshers.forEach(function (f) { f(); }); }, 400);

    /* 导航当前节 */
    var links = {};
    document.querySelectorAll('[data-nav] a').forEach(function (a) {
      var id = a.getAttribute('href');
      if (id && id.charAt(0) === '#') links[id.slice(1)] = a;
    });
    if ('IntersectionObserver' in window && Object.keys(links).length) {
      var vis = {}, ids = Object.keys(links);
      var io = new IntersectionObserver(function (es) {
        es.forEach(function (e) { vis[e.target.id] = e.isIntersecting ? e.intersectionRatio : 0; });
        var best = null, bv = 0;
        ids.forEach(function (k) { if ((vis[k] || 0) > bv) { bv = vis[k]; best = k; } });
        ids.forEach(function (k) { links[k].classList.toggle('on', k === best); });
      }, { threshold: [0, 0.2, 0.5, 0.8], rootMargin: '-64px 0px -30% 0px' });
      ids.forEach(function (k) { var s = document.getElementById(k); if (s) io.observe(s); });
    }
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot);
  else boot();

  global.Reef = { tank: tank, tip: tip, burst: burst, bubbly: bubbly, sections: sections, TIPS: TIPS, tanks: tanks };
})(window);
