// Minimal GE charts initializer for OSRS Wiki pages in the app
// Finds elements with .GEChartBox and renders a Highcharts stock chart
// using the OSRS Wiki price API.

(function () {
  const LOG_TAG = 'GEChartInit';

  function log(level, msg, obj) {
    try {
      const text = `[${LOG_TAG}] ${msg}`;
      if (level === 'e') console.error(text, obj || '');
      else if (level === 'w') console.warn(text, obj || '');
      else console.log(text, obj || '');
    } catch (e) {}
  }

  function toMidPrice(point) {
    const hi = point.avgHighPrice;
    const lo = point.avgLowPrice;
    if (typeof hi === 'number' && typeof lo === 'number') return Math.round((hi + lo) / 2);
    if (typeof hi === 'number') return hi;
    if (typeof lo === 'number') return lo;
    return null;
  }

  async function fetchSeries(itemId) {
    const url = `https://prices.runescape.wiki/api/v1/osrs/timeseries?timestep=24h&id=${encodeURIComponent(itemId)}`;
    const resp = await fetch(url, { credentials: 'omit', mode: 'cors', cache: 'force-cache' });
    if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
    const json = await resp.json();
    const data = Array.isArray(json?.data) ? json.data : [];
    const series = [];
    for (const p of data) {
      const mid = toMidPrice(p);
      if (typeof mid === 'number' && typeof p.timestamp === 'number') {
        // API timestamp in seconds
        series.push([p.timestamp * 1000, mid]);
      }
    }
    return series;
  }

  function ensureStylesInjected() {
    if (document.getElementById('ge-charts-style')) return;
    const css = `
      .GEdatachart.smallChart { width: 100% !important; max-width: 100% !important; overflow: visible !important; height: auto !important; }
      .GEChartBox { width: 100%; margin: 0 !important; padding: 0 !important; }
      /* Let Highcharts manage its own overflow; keep labels visible */
      .GEdatachart.smallChart svg { overflow: visible !important; }
      /* Ensure container doesn't clip labels */
      .GEdatachart.smallChart .highcharts-container { overflow: visible !important; }
    `;
    const style = document.createElement('style');
    style.id = 'ge-charts-style';
    style.textContent = css;
    document.head.appendChild(style);
  }

  function formatCompact(n) {
    const abs = Math.abs(n);
    if (abs >= 1_000_000) return (n/1_000_000).toFixed(n % 1_000_000 === 0 ? 0 : 1) + 'm';
    if (abs >= 1_000) return (n/1_000).toFixed(n % 1_000 === 0 ? 0 : 1) + 'k';
    return String(n);
  }

  function renderChart(container, series) {
    if (!window.Highcharts || !window.Highcharts.stockChart) {
      log('e', 'Highcharts.stockChart not available');
      return;
    }
    ensureStylesInjected();

    const id = container.id || undefined;
    const bodyColor = getComputedStyle(document.body).color || '#333';
    const cs = getComputedStyle(container);
    const styleH = parseFloat(cs.height) || 0;
    const inlineH = parseFloat((container.style && container.style.height) || '') || 0;
    const height = Math.max(styleH, inlineH, container.clientHeight || 0, 160);
    const opts = {
      chart: {
        height,
        backgroundColor: 'white',
        reflow: true,
        marginLeft: 48,
        marginRight: 16,
        spacingBottom: 10,
        spacing: [4, 4, 4, 4],
        animation: false
      },
      title: { text: null },
      subtitle: { text: null },
      credits: { enabled: false },
      rangeSelector: { enabled: false },
      legend: { enabled: false },
      navigator: { enabled: false },
      scrollbar: { enabled: false },
      xAxis: {
        ordinal: false,
        lineWidth: 1,
        tickWidth: 0,
        labels: { style: { color: bodyColor, fontSize: '11px' } }
      },
      yAxis: {
        opposite: false,
        title: { text: null },
        gridLineWidth: 1,
        tickAmount: 3,
        startOnTick: true,
        endOnTick: true,
        lineWidth: 1,
        lineColor: '#E0E0E0',
        showLastLabel: true,
        showFirstLabel: true,
        labels: {
          style: { color: bodyColor, fontSize: '11px' },
          align: 'right',
          x: -6,
          reserveSpace: true,
          formatter: function () { return formatCompact(this.value); }
        }
      },
      series: [{
        type: 'line',
        name: 'Price',
        data: series,
        color: '#4572A7',
        lineWidth: 2,
        tooltip: { valueDecimals: 0, pointFormat: '<b>{point.y}</b> gp' }
      }]
    };
    try {
      if (id) {
        window.Highcharts.stockChart(id, opts);
      } else {
        window.Highcharts.stockChart(container, opts);
      }
    } catch (e) {
      log('e', 'Failed to render chart', e);
    }
  }

  function initOne(box) {
    try {
      const dataEl = box.querySelector('.GEdataprices');
      const chartEl = box.querySelector('.GEdatachart');
      if (!dataEl || !chartEl) return;
      const itemId = dataEl.getAttribute('data-itemid');
      if (!itemId) return;
      // Prevent duplicate renders
      if (chartEl.dataset.rendered === '1') return;
      chartEl.dataset.rendered = '1';
      // Install swipe-back guard so horizontal drags inside the chart
      // don't trigger the app's back gesture.
      installSwipeBackGuard(chartEl);

      fetchSeries(itemId)
        .then(series => {
          if (series.length) renderChart(chartEl, series);
          else log('w', 'No series data for item', itemId);
        })
        .catch(err => log('e', `fetchSeries failed for ${itemId}`, err));
    } catch (e) {
      log('e', 'initOne error', e);
    }
  }

  function initAll() {
    if (!document || !document.body) return;
    const boxes = document.querySelectorAll('.GEChartBox');
    if (!boxes || boxes.length === 0) return;
    if (!window.Highcharts) {
      log('w', 'Highcharts not yet loaded; delaying init');
      setTimeout(initAll, 100);
      return;
    }
    boxes.forEach(initOne);
  }

  function ready(fn) {
    if (document.readyState === 'complete' || document.readyState === 'interactive') {
      setTimeout(fn, 0);
    } else {
      document.addEventListener('DOMContentLoaded', fn);
    }
  }

  // Kickoff
  ready(initAll);
  // Also observe late-added content
  const mo = new MutationObserver(() => initAll());
  ready(() => mo.observe(document.body, { childList: true, subtree: true }));

  // --- Swipe-back guard helpers ---
  function installSwipeBackGuard(el) {
    if (!el || el.dataset.swipeGuard === '1') return;
    el.dataset.swipeGuard = '1';
    let down = false, startX = 0, startY = 0, sent = false, resetTimer = null;

    const send = (flag) => {
      if (!window.OsrsWikiBridge || typeof window.OsrsWikiBridge.setHorizontalScroll !== 'function') return;
      try { window.OsrsWikiBridge.setHorizontalScroll(!!flag); } catch (_) {}
    };
    const resetSoon = () => {
      if (resetTimer) clearTimeout(resetTimer);
      resetTimer = setTimeout(() => { sent = false; send(false); }, 400);
    };

    const onDown = (x, y) => { down = true; startX = x; startY = y; sent = true; send(true); };
    const onMove = (x, y) => {
      if (!down) return;
      const dx = Math.abs(x - startX);
      const dy = Math.abs(y - startY);
      if (!sent && dx > 6 && dx > dy) { sent = true; send(true); }
      if (sent) resetSoon();
    };
    const onUp = () => { down = false; if (sent) { // keep guard for a short delay to beat fling race
        if (resetTimer) clearTimeout(resetTimer);
        resetTimer = setTimeout(() => { sent = false; send(false); }, 250);
      } };

    // Pointer events preferred
    if (window.PointerEvent) {
      el.addEventListener('pointerdown', (e) => onDown(e.clientX, e.clientY), { passive: true });
      el.addEventListener('pointermove', (e) => onMove(e.clientX, e.clientY), { passive: true });
      el.addEventListener('pointerup', onUp, { passive: true });
      el.addEventListener('pointercancel', onUp, { passive: true });
      el.addEventListener('pointerleave', onUp, { passive: true });
    } else {
      // Touch/mouse fallback
      el.addEventListener('touchstart', (e) => { const t = e.touches[0]; if (t) onDown(t.clientX, t.clientY); }, { passive: true });
      el.addEventListener('touchmove', (e) => { const t = e.touches[0]; if (t) onMove(t.clientX, t.clientY); }, { passive: true });
      el.addEventListener('touchend', onUp, { passive: true });
      el.addEventListener('mousedown', (e) => onDown(e.clientX, e.clientY), { passive: true });
      el.addEventListener('mousemove', (e) => onMove(e.clientX, e.clientY), { passive: true });
      el.addEventListener('mouseup', onUp, { passive: true });
      el.addEventListener('mouseleave', onUp, { passive: true });
    }
  }

  // Global, capture-phase guard to reliably catch events within inner Highcharts layers
  // Keep the local guard for pointer events inside Highcharts, but the
  // primary enforcement now happens in horizontal_scroll_interceptor.js
  (function installGlobalChartGestureGuard() {
    const isInChart = (t) => !!(t && (t.closest && (t.closest('.GEdatachart') || t.closest('.GEChartBox'))));
    const send = (flag) => {
      if (!window.OsrsWikiBridge || typeof window.OsrsWikiBridge.setHorizontalScroll !== 'function') return;
      try { window.OsrsWikiBridge.setHorizontalScroll(!!flag); } catch (_) {}
    };
    const onDown = (ev) => { const t = ev.target; if (isInChart(t)) send(true); };
    const onUp = () => send(false);
    if (window.PointerEvent) {
      document.addEventListener('pointerdown', onDown, { passive: true, capture: true });
      document.addEventListener('pointerup', onUp, { passive: true, capture: true });
      document.addEventListener('pointercancel', onUp, { passive: true, capture: true });
      document.addEventListener('pointerleave', onUp, { passive: true, capture: true });
    } else {
      document.addEventListener('touchstart', onDown, { passive: true, capture: true });
      document.addEventListener('touchend', onUp, { passive: true, capture: true });
      document.addEventListener('touchcancel', onUp, { passive: true, capture: true });
      document.addEventListener('mousedown', onDown, { passive: true, capture: true });
      document.addEventListener('mouseup', onUp, { passive: true, capture: true });
      document.addEventListener('mouseleave', onUp, { passive: true, capture: true });
    }
  })();
})();
