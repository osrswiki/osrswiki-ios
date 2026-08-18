// Lightweight Tabber for offline/app articles. MediaWiki's ext.Tabber is not
// shipped, so every .tabbertab would otherwise render stacked. Phone widths
// cannot show a real stacked tab strip, so the control is a labeled select
// whose panel contains every table the selection switches.
(function () {
  'use strict';

  function tabTitle(tab, index) {
    return (
      tab.getAttribute('data-title') ||
      tab.getAttribute('title') ||
      tab.getAttribute('data-tab-name') ||
      ('Tab ' + (index + 1))
    );
  }

  function activate(tabber, tabs, select, index) {
    tabs.forEach(function (tab, i) {
      const on = i === index;
      tab.hidden = !on;
      tab.style.display = on ? '' : 'none';
      tab.classList.toggle('tabbertab-active', on);
    });
    if (select && select.selectedIndex !== index) {
      select.selectedIndex = index;
    }
    tabber.setAttribute('data-osrs-tabber-index', String(index));
    tabber.dispatchEvent(new CustomEvent('osrs-tabber-change', { bubbles: true }));
    if (typeof window.refreshHorizontalScrollAffordances === 'function') {
      window.refreshHorizontalScrollAffordances();
    }
  }

  function enhance(tabber) {
    if (!tabber || tabber.classList.contains('tabberlive')) return;
    const tabs = Array.from(tabber.children).filter(function (node) {
      return node.classList && node.classList.contains('tabbertab');
    });
    if (tabs.length < 2) return;

    const toolbar = document.createElement('div');
    toolbar.className = 'osrs-tabber-toolbar';
    const label = document.createElement('label');
    label.className = 'osrs-tabber-toolbar-label';
    label.textContent = 'Showing';
    const select = document.createElement('select');
    select.className = 'osrs-tabber-select';
    select.setAttribute('aria-label', 'Choose which variant to show');
    const selectId = 'osrs-tabber-select-' + Math.random().toString(36).slice(2, 9);
    select.id = selectId;
    label.setAttribute('for', selectId);

    const panel = document.createElement('div');
    panel.className = 'osrs-tabber-panel';

    tabs.forEach(function (tab, index) {
      const option = document.createElement('option');
      option.value = String(index);
      option.textContent = tabTitle(tab, index);
      select.appendChild(option);
      tab.setAttribute('role', 'tabpanel');
      tab.setAttribute('data-osrs-tab-index', String(index));
      panel.appendChild(tab);
    });

    select.addEventListener('change', function () {
      activate(tabber, tabs, select, Number(select.value) || 0);
    });

    toolbar.appendChild(label);
    toolbar.appendChild(select);
    tabber.appendChild(toolbar);
    tabber.appendChild(panel);
    tabber.classList.add('tabberlive', 'osrs-tabber');
    activate(tabber, tabs, select, 0);
  }

  function init(root) {
    const scope = root && root.querySelectorAll ? root : document;
    scope.querySelectorAll('.tabber').forEach(enhance);
  }

  function ready(fn) {
    if (document.readyState === 'complete' || document.readyState === 'interactive') {
      setTimeout(fn, 0);
    } else {
      document.addEventListener('DOMContentLoaded', fn);
    }
  }

  ready(init);
  ready(function () {
    let queued = false;
    const observer = new MutationObserver(function () {
      if (queued) return;
      queued = true;
      setTimeout(function () {
        queued = false;
        init();
      }, 50);
    });
    if (document.body) observer.observe(document.body, { childList: true, subtree: true });
  });

  window.__osrsInitTabbers = init;
})();
