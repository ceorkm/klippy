/* Klippy. Built to design/landing/DESIGN.md.
   Hash routing, the theme, the FAQ, and the changelog. No dependencies. */

(function () {
  'use strict';

  var root = document.documentElement;

  // --- theme ---------------------------------------------------------------
  // The boot script in the head already set this before paint. All that is
  // left is the switch and remembering the choice.

  var sw = document.querySelector('.switch');

  function paintSwitch() {
    var light = root.dataset.theme === 'light';
    sw.setAttribute('aria-checked', String(light));
    sw.setAttribute('aria-label', light ? 'Dark mode': 'Light mode');
  }

  sw.addEventListener('click', function () {
    root.dataset.theme = root.dataset.theme === 'light' ? 'dark': 'light';
    try { localStorage.setItem('klippy.theme', root.dataset.theme); } catch (e) {}
    paintSwitch();
  });

  paintSwitch();

  // --- the menu on a phone -------------------------------------------------

  var nav = document.querySelector('.nav');
  var burger = nav.querySelector('.burger');
  var drop = nav.querySelector('.nav__drop');

  burger.addEventListener('click', function () {
    var open = nav.dataset.open !== 'true';
    nav.dataset.open = open ? 'true': 'false';
    burger.setAttribute('aria-expanded', String(open));
    drop.hidden = !open;
  });

  drop.addEventListener('click', function () {
    nav.dataset.open = 'false';
    burger.setAttribute('aria-expanded', 'false');
    drop.hidden = true;
  });

  // --- routing -------------------------------------------------------------
  // Hash routing is enough for a landing site. A bare "#section" is an anchor
  // on the home page; "#/name" is a page of its own.

  var pages = {};
  [].forEach.call(document.querySelectorAll('[data-page]'), function (el) {
    pages[el.dataset.page] = el;
  });

  function route() {
    var hash = location.hash || '';
    var name = hash.indexOf('#/') === 0 ? hash.slice(2): '';
    var page = pages[name] || pages.home;

    Object.keys(pages).forEach(function (key) {
      pages[key].hidden = pages[key] !== page;
    });

    if (hash.indexOf('#/') === 0) {
      window.scrollTo(0, 0);
    } else if (hash.length > 1) {
      var target = document.getElementById(hash.slice(1));
      if (target) target.scrollIntoView();
    }

    reveal();
    if (name === 'changelog') loadReleases();
  }

  addEventListener('hashchange', route);

  // --- the faq -------------------------------------------------------------
  // Height animates from zero to the measured height and back, which is the
  // only way to animate `auto`.

  var items = [].slice.call(document.querySelectorAll('.qa'));

  function setOpen(item, open) {
    var panel = item.querySelector('.qa__wrap');
    item.dataset.open = open ? 'true': 'false';
    item.querySelector('.qa__ask').setAttribute('aria-expanded', String(open));
    panel.style.height = open ? panel.scrollHeight + 'px': '0px';
  }

  items.forEach(function (item) {
    item.querySelector('.qa__ask').addEventListener('click', function () {
      var open = item.dataset.open !== 'true';
      items.forEach(function (other) { setOpen(other, false); });
      setOpen(item, open);
    });
    setOpen(item, item.dataset.open === 'true');
  });

  addEventListener('resize', function () {
    items.forEach(function (i) { if (i.dataset.open === 'true') setOpen(i, true); });
  });

  // --- sections rise once ----------------------------------------------------
  // A plain scroll check rather than IntersectionObserver. The observer is the
  // tidier tool but its callback does not fire in every environment the page
  // gets rendered in, and a section that never reveals is a blank page. This
  // always runs.

  var rising = [];

  function reveal() {
    rising = [].slice.call(document.querySelectorAll('[data-rise]:not(.seen)'));
    check();
  }

  function check() {
    var limit = innerHeight * 0.92;
    rising = rising.filter(function (el) {
      if (el.getBoundingClientRect().top < limit) {
        el.classList.add('seen');
        return false;
      }
      return true;
    });
  }

  // Called straight from the scroll event rather than through
  // requestAnimationFrame. The frame callback is the tidier tool and it does
  // not run in every environment this page is rendered in, and a section that
  // never reveals is a blank page. The work is a bounding box per unrevealed
  // element and the list empties as it goes.
  function onScroll() {
    if (rising.length) check();
  }

  addEventListener('scroll', onScroll, { passive: true });
  addEventListener('resize', onScroll);

  // --- the lead cell cycles --------------------------------------------------
  // Real examples only: the thing on the left is something you would copy, and
  // the chip on the right is the category Klippy's classifier actually files it
  // under. Four seconds each, per the motion rules, and off entirely for anyone
  // who has asked for less movement.

  var rows = [].slice.call(document.querySelectorAll('.pair'));

  if (rows.length && !matchMedia('(prefers-reduced-motion: reduce)').matches) {
    var at = 0;
    setInterval(function () {
      rows[at].removeAttribute('data-on');
      at = (at + 1) % rows.length;
      rows[at].setAttribute('data-on', 'true');
    }, 4000);
  }

  // --- changelog -----------------------------------------------------------
  // Sourced from the repository's releases, with a seeded fallback so the page
  // is never empty when the API is rate limited or the network is gone.

  var SEED = [
    {
      name: 'Bug fixes and an app filter',
      date: '2026-09-15',
      body: [
        'App filter: show only the clips you copied from one app, with its icon beside the name.',
        'History size: 200, 1,000, 5,000 or every clip you have. The list used to stop at a thousand with no way to change it.',
        'Instant tooltips: hovering an icon shows its label straight away rather than after a wait.',
        'Your own picture as the panel background, with the wash over it measured from the picture.'
      ]
    },
    {
      name: 'A rebuilt panel, and the sandbox',
      date: '2026-09-14',
      body: [
        'New panel: rebuilt as a borderless window it owns, so it always opens somewhere visible.',
        'Sandboxed: Klippy now runs inside Apple’s sandbox with three entitlements.',
        'Faster search: a keystroke used to cost nearly three seconds on a large history. It is instant now.'
      ]
    }
  ];

  var loaded = false;

  function renderReleases(list) {
    var rail = document.querySelector('.rail');
    var body = document.querySelector('.releases');
    rail.innerHTML = '';
    body.innerHTML = '';

    var latest = document.querySelector('.latest');
    if (latest && list.length) {
      latest.textContent = 'Latest release ' + list[0].name + ' \u00b7 ' + fmt(list[0].date);
    }

    list.forEach(function (rel, i) {
      var b = document.createElement('button');
      b.type = 'button';
      b.innerHTML = rel.name + '<span>' + fmt(rel.date) + '</span>';
      b.addEventListener('click', function () {
        document.getElementById('rel-' + i).scrollIntoView({ block: 'center' });
      });
      rail.appendChild(b);

      var art = document.createElement('article');
      art.className = 'release';
      art.id = 'rel-' + i;
      art.innerHTML =
        '<p class="release__date">' + fmt(rel.date) + '</p>' +
        '<h2 class="release__name">' + esc(rel.name) + '</h2>' +
        '<ul>' + rel.body.map(bullet).join('') + '</ul>';
      body.appendChild(art);
    });
  }

  // A release note bullet becomes a bold lead and an explanation. Three shapes
  // turn up in the wild and all three land the same way:
  //
  //   **Lead** the rest        the shape GitHub release notes actually use
  //   Lead — the rest          an em dash separator
  //   Lead: the rest           a colon separator
  //
  // Escaping happens first, so nothing in a release note can inject markup.
  function bullet(line) {
    var text = esc(line.replace(/^\s*[-*]\s*/, '').trim());
    var lead = '';

    var bold = text.match(/^\*\*(.+?)\*\*(.*)$/);
    if (bold) {
      lead = bold[1];
      // Whatever separator sat between the lead and the explanation goes; the
      // bold already does that job.
      text = bold[2].replace(/^\s*(?:\u2014|\u2013|-|:)?\s*/, '');
    } else {
      var split = text.match(/^(.+?)\s*(?:\u2014|:)\s+(.+)$/);
      if (split) {
        lead = split[1];
        text = split[2];
      }
    }

    return '<li>' + (lead ? '<b>' + inline(lead) + '</b> ' : '') + inline(text) + '</li>';
  }

  // The small amount of Markdown that survives inside a bullet.
  function inline(t) {
    return t
      .replace(/\*\*(.+?)\*\*/g, '<b>$1</b>')
      .replace(/`([^`]+)`/g, '<code>$1</code>');
  }

  function esc(s) {
    return String(s).replace(/[&<>]/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c];
    });
  }

  function fmt(iso) {
    var d = new Date(iso);
    return isNaN(d) ? iso: d.toLocaleDateString('en-GB',
      { day: 'numeric', month: 'short', year: 'numeric' });
  }

  function loadReleases() {
    if (loaded) return;
    loaded = true;
    renderReleases(SEED);

    fetch('https://api.github.com/repos/ceorkm/klippy/releases')
      .then(function (r) { return r.ok ? r.json(): null; })
      .then(function (json) {
        if (!json || !json.length) return;
        renderReleases(json.slice(0, 12).map(function (r) {
          return {
            name: r.name || r.tag_name,
            date: (r.published_at || '').slice(0, 10),
            body: (r.body || '').split('\n')
                   .map(function (l) { return l.trim(); })
                   .filter(function (l) { return /^[-*]\s+/.test(l); })
          };
        }).filter(function (r) { return r.body.length; }));
      })
      .catch(function () { /* the seed is already on screen */ });
  }

  route();
})();
