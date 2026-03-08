// MIDI2Kit ランディングページ - 最小限のインタラクション

(function () {
  'use strict';

  // タブ切替
  var tabs = document.querySelectorAll('.tab');
  var contents = document.querySelectorAll('.tab-content');

  tabs.forEach(function (tab) {
    tab.addEventListener('click', function () {
      var target = tab.getAttribute('data-tab');

      tabs.forEach(function (t) { t.classList.remove('active'); });
      contents.forEach(function (c) { c.classList.remove('active'); });

      tab.classList.add('active');
      var el = document.getElementById('tab-' + target);
      if (el) el.classList.add('active');
    });
  });

  // モバイルナビゲーション トグル
  var toggle = document.getElementById('nav-toggle');
  var navLinks = document.getElementById('nav-links');

  if (toggle && navLinks) {
    toggle.addEventListener('click', function () {
      navLinks.classList.toggle('open');
    });

    // ナビリンクをクリックしたらメニューを閉じる
    navLinks.querySelectorAll('a').forEach(function (link) {
      link.addEventListener('click', function () {
        navLinks.classList.remove('open');
      });
    });
  }

  // ヘッダーのスクロール時背景強化
  var header = document.getElementById('header');
  if (header) {
    window.addEventListener('scroll', function () {
      if (window.scrollY > 10) {
        header.style.borderBottomColor = 'rgba(42, 42, 58, 0.8)';
      } else {
        header.style.borderBottomColor = '';
      }
    }, { passive: true });
  }
})();
