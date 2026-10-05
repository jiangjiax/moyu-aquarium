/* ═══════════════════════════════════════════════════════════════════════════
   deck.js · 翻页、水面、泡泡

   舞台固定 1280×720，按窗口等比缩放，所以任何屏幕都是一张 16:9 幻灯片。
   翻页的动效和介绍站同一套语言：水面线拉开，内容从水里一格一格升上来，
   同时从画面下沿真冒一串泡。没有 scroll 监听，翻页就是切 class。
   ═══════════════════════════════════════════════════════════════════════════ */
(function () {
  'use strict';

  var stage = document.getElementById('stage');
  var slides = [].slice.call(document.querySelectorAll('.slide'));
  var dots = document.getElementById('dots');
  var now = document.getElementById('now');
  var title = document.getElementById('title');
  var total = document.getElementById('total');
  var i = 0;

  /* ── 缩放：1280×720 永远居中铺满能放下的地方 */
  function fit() {
    var s = Math.min(window.innerWidth / 1280, window.innerHeight / 720);
    stage.style.transform = 'scale(' + s + ')';
  }
  window.addEventListener('resize', fit);
  fit();

  /* ── 进度条：一格一页 */
  total.textContent = (slides.length < 10 ? '0' : '') + slides.length;
  slides.forEach(function () { dots.appendChild(document.createElement('i')); });
  var bars = [].slice.call(dots.children);

  function pad(n) { return (n < 10 ? '0' : '') + n; }

  /* ── 翻页 */
  /* 写进地址栏，顺手也能直接链到某一页 */
  function go(n, quiet) {
    n = (n + slides.length) % slides.length;
    if (n === i) return;
    slides[i].classList.remove('on');
    i = n;
    show();
    if (!quiet) splash();
    history.replaceState(null, '', '#' + (i + 1));
  }

  function show() {
    slides[i].classList.add('on');
    now.textContent = pad(i + 1);
    title.textContent = slides[i].dataset.title || '';
    bars.forEach(function (b, k) { b.classList.toggle('on', k <= i); });
    /* 进场动效要重放：先摘掉 .on 再加回去不生效，用 reflow 顶一下 */
    var live = slides[i].querySelectorAll('.rise');
    for (var k = 0; k < live.length; k++) {
      live[k].style.animation = 'none';
    }
    void slides[i].offsetWidth;
    for (var j = 0; j < live.length; j++) {
      live[j].style.animation = '';
    }
  }

  /* ── 翻页时从画面下沿冒一串泡：水面被搅动了 */
  function splash() {
    if (!window.Reef) return;
    var w = 1280, h = 720;
    for (var k = 0; k < 14; k++) {
      var x = 60 + Math.random() * (w - 120);
      Reef.burst(x, h - 24 - Math.random() * 40, 1 + (k % 2), { sp: 10 + Math.random() * 10, r: 3 + (k % 3) });
    }
  }

  document.addEventListener('keydown', function (e) {
    if (e.key === 'ArrowRight' || e.key === 'PageDown' || e.key === ' ') { e.preventDefault(); go(i + 1); }
    else if (e.key === 'ArrowLeft' || e.key === 'PageUp') { e.preventDefault(); go(i - 1); }
    else if (e.key === 'Home') { go(0); }
    else if (e.key === 'End') { go(slides.length - 1); }
  });

  stage.addEventListener('click', function (e) {
    if (e.target.closest('a')) return;
    go(i + 1);
  });

  /* 触屏左右滑 */
  var x0 = null;
  stage.addEventListener('pointerdown', function (e) { x0 = e.clientX; });
  stage.addEventListener('pointerup', function (e) {
    if (x0 === null) return;
    var dx = e.clientX - x0;
    if (Math.abs(dx) > 60) go(i + (dx < 0 ? 1 : -1));
    x0 = null;
  });

  show();

  /* 直接开 #4 就是第四页 */
  var h = parseInt((location.hash || '').replace('#', ''), 10);
  if (h > 1) go(h - 1, true);
  history.replaceState(null, '', '#' + (i + 1));
  setTimeout(splash, 400);
})();
