/* 摸鱼水族馆 · 介绍站的行为层
   只做四件事：把缸挂上去、进场、点击撒饵、窄屏退化。
   没有 window scroll 监听。滚动相关的动效全部交给 CSS 滚动时间线或 IntersectionObserver。 */
(function () {
  'use strict';

  document.documentElement.classList.add('js');
  window.addEventListener('error', function(e){ document.title='ERR '+e.message+' @'+(e.lineno||'?')+':'+(e.filename||'').split('/').pop(); });

  var A = window.Aquarium;
  var clamp = function (v, a, b) { return v < a ? a : v > b ? b : v; };

  /* ---------------------------------------------------------- 进场
     全部交给 IntersectionObserver，没有 scroll 监听。图片多一层「擦玻璃」揭幕。 */
  function reveal() {
    var groups = [
      ['.sec-head', 0], ['.roster-col', 1], ['.track-step', 2],
      ['.bento .cell', 3], ['.mile', 4], ['.run-in > *', 5], ['.cmds .cmd', 6],
      ['.stack-in > *', 7]
    ];
    var nodes = [];
    groups.forEach(function (g) {
      document.querySelectorAll(g[0]).forEach(function (el, i) {
        var wipe = el.tagName === 'IMG' || el.classList.contains('shot') || el.classList.contains('cell-shot');
        el.classList.add(wipe ? 'wipe' : 'reveal', 'd' + Math.min(i, 4));
        nodes.push(el);
      });
    });
    /* 图所在的格子自己淡入，图片再擦出来 */
    document.querySelectorAll('.cell-shot').forEach(function (c) { c.classList.add('reveal'); nodes.push(c); });

    if (A.reduce || !('IntersectionObserver' in window)) {
      nodes.forEach(function (n) { n.classList.add('in'); });
      return;
    }
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        if (e.isIntersecting) { e.target.classList.add('in'); io.unobserve(e.target); }
      });
    }, { rootMargin: '0px 0px -10% 0px', threshold: 0.08 });
    nodes.forEach(function (n) { io.observe(n); });
  }

  /* ---------------------------------------------------------- 导航高亮
     用观察器记下当前这一屏是哪一节，不监听 scroll。 */
  function navWatch() {
    var links = {};
    document.querySelectorAll('.links a').forEach(function (a) {
      links[a.getAttribute('href').slice(1)] = a;
    });
    var ids = Object.keys(links);
    if (!ids.length || !('IntersectionObserver' in window)) return;
    var on = function (id) {
      ids.forEach(function (k) { links[k].classList.toggle('on', k === id); });
    };
    var vis = {};
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) { vis[e.target.id] = e.isIntersecting ? e.intersectionRatio : 0; });
      var best = null, bestV = 0;
      ids.forEach(function (k) { if ((vis[k] || 0) > bestV) { bestV = vis[k]; best = k; } });
      if (best) on(best);
    }, { threshold: [0, 0.15, 0.35, 0.6, 0.9], rootMargin: '-64px 0px -40% 0px' });
    ids.forEach(function (k) { var s = document.getElementById(k); if (s) io.observe(s); });
  }

  /* ---------------------------------------------------------- 跑道
     十一条鱼滚一遍。把内容复制一份接在后面，接缝才看不出来。 */
  function marquee() {
    var track = document.querySelector('.marquee-track');
    if (!track) return;
    track.innerHTML += track.innerHTML;
  }

  /* ---------------------------------------------------------- 钱包 HUD */
  var wallet = 0, boostT = 0;

  function mmss(s) {
    var m = Math.floor(s / 60), r = Math.floor(s % 60);
    return m + ':' + (r < 10 ? '0' : '') + r;
  }

  function bindHud(shell) {
    if (shell.dataset.hud) return null;
    shell.dataset.hud = '1';
    var hud = document.createElement('div');
    hud.className = 'tank-hud';
    hud.innerHTML = '<span class="px hud-wallet"><img src="assets/icon/coin.png" alt="" width="11" height="11"><b data-wallet>0</b></span>' +
      '<span class="px hud-boost" data-boost hidden>产币翻倍 <b data-boost-t>2:00</b></span>';
    shell.appendChild(hud);
    return hud;
  }

  var walletEls = [], boostEls = [];
  function pushHud(hud) {
    if (!hud) return;
    walletEls.push(hud.querySelector('[data-wallet]'));
    boostEls.push(hud.querySelector('[data-boost]'));
  }

  function onEarn() {
    wallet += 1;
    for (var i = 0; i < walletEls.length; i++) walletEls[i].textContent = wallet;
  }
  function onBoost() {
    boostT = 120;
    for (var i = 0; i < boostEls.length; i++) {
      boostEls[i].hidden = false;
      boostEls[i].querySelector('[data-boost-t]').textContent = mmss(boostT);
    }
  }
  setInterval(function () {
    if (boostT <= 0) return;
    boostT = Math.max(0, boostT - 1);
    for (var i = 0; i < boostEls.length; i++) {
      boostEls[i].querySelector('[data-boost-t]').textContent = mmss(boostT);
      if (boostT === 0) boostEls[i].hidden = true;
    }
  }, 1000);

  /* ---------------------------------------------------------- 挂缸 */
  /* 开局那 8 条对着实机截图点过数：蓝倒吊、小丑鱼、蝴蝶鱼 ×2、神仙鱼、小丑鱼 ×2、神仙鱼 */
  var REEF = ['blue_tang', 'clownfish', 'butterfly', 'butterfly', 'angelfish', 'clownfish', 'clownfish', 'angelfish'];

  function fit(shell, tank, cssW, cssH, scale) {
    tank.resize(cssW, cssH, scale);
  }

  function makeTank(canvas, zones, fish, interactive) {
    var tank = new A.Tank(canvas, {
      zones: zones,
      fish: fish,
      onEarn: onEarn,
      onBoost: onBoost
    });
    A.addTank(tank);
    if (interactive) {
      canvas.addEventListener('pointerdown', function (ev) {
        var r = canvas.getBoundingClientRect();
        var ax = (ev.clientX - r.left) / r.width * tank.artW;
        var ay = (ev.clientY - r.top) / r.height * tank.artH;
        if (ay > A.sandTop(tank.artH) - 2) ay = A.sandTop(tank.artH) - 8;
        tank.feed(ax, ay);
      });
    }
    return tank;
  }

  function layout() {
    var vw = window.innerWidth;
    var mobile = vw < 768;

    /* hero */
    var heroShell = document.querySelector('[data-tank="hero"]');
    var heroCv = document.getElementById('tank-hero');
    if (heroShell && heroCv) {
      pushHud(heroShell.querySelector('.tank-hud'));
      var hw = heroShell.clientWidth, hh = heroShell.clientHeight;
      if (hw > 0) fit(heroShell, heroTank, hw, hh, clamp(Math.round(hh / 84), 2, 5));
    }

    /* 三座馆的长缸 */
    var panShell = document.querySelector('[data-tank="pan"]');
    var panCv = document.getElementById('tank-pan');
    if (panShell && panCv && !mobile) {
      var panel = panShell.parentElement.getBoundingClientRect().width || vw;
      var ph = panShell.clientHeight;
      if (ph > 0) fit(panShell, panTank, panel * 3, ph, clamp(Math.round(ph / 128), 2, 5));
    }

    /* 投一次饵 */
    var miniShell = document.querySelector('[data-tank="mini"]');
    var miniCv = document.getElementById('tank-mini');
    if (miniShell && miniCv) {
      var mw = miniShell.clientWidth, mh = miniShell.clientHeight;
      if (mw > 0) fit(miniShell, miniTank, mw, mh, clamp(Math.round(mh / 70), 2, 4));
    }

    /* 窄屏：长缸退化成三只小缸 */
    layoutStack(mobile);
  }

  var mobileTanks = [];
  function layoutStack(mobile) {
    var host = document.getElementById('zone-stack');
    if (mobile && !host) {
      host = document.createElement('div');
      host.id = 'zone-stack';
      host.className = 'zone-stack wrap';
      var desc = [
        ['珊瑚礁区', '亮蓝绿，有阳光光柱。鹿角珊瑚、脑珊瑚、扇珊瑚、海葵。开局自带 8 条。', ['blue_tang', 'clownfish', 'butterfly', 'butterfly', 'angelfish', 'clownfish', 'clownfish', 'angelfish']],
        ['淡水草缸区', '暖绿，光柱很淡。水草丛生，石头顶上长草，没有珊瑚。开局空着。', ['guppy', 'neon', 'neon', 'neon', 'discus']],
        ['深海区', '近黑。光柱和焦散全关，礁石压成冷青，摆得疏。开局空着。', ['lantern', 'lantern', 'jelly', 'angler']]
      ];
      desc.forEach(function (d, i) {
        var item = document.createElement('div');
        item.className = 'zone-item reveal';
        item.innerHTML = '<div class="tank-shell" data-tank="m' + i + '"><canvas class="tank"></canvas></div>' +
          '<p class="zname">' + d[0] + '</p><p>' + d[1] + '</p>';
        host.appendChild(item);
        var cv = item.querySelector('canvas');
        var fish = {}; fish[i] = d[2];
        var t = makeTank(cv, [i], fish, true);
        mobileTanks.push({ shell: item.querySelector('.tank-shell'), tank: t });
      });
      document.getElementById('zones').appendChild(host);
      if ('IntersectionObserver' in window && !A.reduce) {
        var io = new IntersectionObserver(function (es) {
          es.forEach(function (e) { if (e.isIntersecting) { e.target.classList.add('in'); io.unobserve(e.target); } });
        }, { threshold: 0.1 });
        Array.prototype.forEach.call(host.children, function (c) { io.observe(c); });
      } else {
        Array.prototype.forEach.call(host.children, function (c) { c.classList.add('in'); });
      }
    }
    if (!mobile) return;
    mobileTanks.forEach(function (m) {
      if (m.shell.clientWidth > 0) fit(m.shell, m.tank, m.shell.clientWidth, m.shell.clientHeight, clamp(Math.round(m.shell.clientHeight / 76), 2, 4));
    });
  }

  /* ---------------------------------------------------------- 只在看得见的时候跑 */
  function observe() {
    if (!('IntersectionObserver' in window)) { A.start(); return; }
    var io = new IntersectionObserver(function (es) {
      es.forEach(function (e) {
        var cv = e.target.querySelector ? e.target.querySelector('canvas') : e.target;
        if (!cv || !cv.__tank) return;
        cv.__tank.visible = e.isIntersecting;
      });
    }, { rootMargin: '120px' });
    document.querySelectorAll('.tank-shell').forEach(function (s) { io.observe(s); });
    A.start();
  }

  /* ---------------------------------------------------------- 起 */
  var heroTank, panTank, miniTank;

  function init() {
    reveal();
    navWatch();
    marquee();

    /* 横向长缸：支持滚动驱动动画就用钉住平移，否则原地不动 + 文字照读。
       降级动效时也走退化版——不然说明文字会全叠在钉住的那一屏上。 */
    var reduced = window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches;
    if (reduced || !(window.CSS && CSS.supports && CSS.supports('animation-timeline', 'view()'))) {
      document.documentElement.classList.add('no-pan');
    }

    A.boot(function () {
      heroTank = makeTank(document.getElementById('tank-hero'), [0], { 0: REEF }, true);
      var fish = { 0: REEF, 1: ['guppy', 'neon', 'neon', 'neon', 'discus'], 2: ['lantern', 'lantern', 'jelly', 'angler'] };
      panTank = makeTank(document.getElementById('tank-pan'), [0, 1, 2], fish, false);
      miniTank = makeTank(document.getElementById('tank-mini'), [0], { 0: ['clownfish', 'butterfly', 'blue_tang', 'angelfish'] }, true);

      [heroTank, panTank, miniTank].forEach(function (t) { t.cv.__tank = t; });
      document.querySelectorAll('.tank-shell').forEach(function (s) {
        var cv = s.querySelector('canvas');
        if (cv && cv.__tank) return;
      });

      layout();
      window.addEventListener('resize', debounce(layout, 160));
      if (window.ResizeObserver) {
        var ro = new ResizeObserver(debounce(layout, 160));
        document.querySelectorAll('.tank-shell').forEach(function (s) { ro.observe(s); });
      }
      bindHud(document.querySelector('[data-tank="mini"]'));
      pushHud(document.querySelector('[data-tank="mini"] .tank-hud'));
      observe();
      document.documentElement.classList.add('ready');
    });
  }

  function debounce(fn, ms) {
    var id;
    return function () { clearTimeout(id); id = setTimeout(fn, ms); };
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
  else init();
})();
