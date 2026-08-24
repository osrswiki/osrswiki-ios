// Minimal GE charts initializer for OSRS Wiki pages in the app
// Finds elements with .GEChartBox and renders a Chart.js line chart
// using the OSRS Wiki price API. Chart.js version: see CHART_JS_VERSION (4.4.9).

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

  function resolveChart() {
    if (typeof window.Chart === 'function') return window.Chart;
    // MediaWiki's AMD `define` can capture Chart.js' UMD build.
    try {
      if (typeof require === 'function') {
        const mod = require('chart.js') || require('Chart');
        if (typeof mod === 'function') {
          window.Chart = mod;
          return mod;
        }
        if (mod && typeof mod.Chart === 'function') {
          window.Chart = mod.Chart;
          return mod.Chart;
        }
      }
    } catch (e) {}
    return null;
  }

  function seriesFromPayload(json) {
    const data = Array.isArray(json?.data) ? json.data : [];
    const series = [];
    for (const p of data) {
      const mid = toMidPrice(p);
      if (typeof mid === 'number' && typeof p.timestamp === 'number') {
        series.push({ x: p.timestamp * 1000, y: mid });
      }
    }
    return series;
  }

  function withTimeout(promise, ms) {
    let timer = null;
    return Promise.race([
      Promise.resolve(promise),
      new Promise((_, reject) => {
        timer = setTimeout(() => reject(new Error('timeout')), ms);
      })
    ]).finally(() => {
      if (timer) clearTimeout(timer);
    });
  }

  async function readBridgeText(url) {
    const bridge = window.OsrsWikiBridge;
    if (!bridge || typeof bridge.fetchText !== 'function') return '';
    try {
      const raw = bridge.fetchText(url);
      if (raw && typeof raw.then === 'function') {
        const text = await withTimeout(raw, 4000);
        return text ? String(text) : '';
      }
      return raw ? String(raw) : '';
    } catch (e) {
      log('w', 'fetchText failed', e);
      return '';
    }
  }

  async function fetchSeries(itemId) {
    const url = `https://prices.runescape.wiki/api/v1/osrs/timeseries?timestep=24h&id=${encodeURIComponent(itemId)}`;
    const bridged = await readBridgeText(url);
    if (bridged) return seriesFromPayload(JSON.parse(bridged));
    const controller = typeof AbortController === 'function' ? new AbortController() : null;
    const timer = controller ? setTimeout(() => controller.abort(), 4000) : null;
    try {
      const resp = await fetch(url, {
        credentials: 'omit',
        mode: 'cors',
        cache: 'no-cache',
        signal: controller ? controller.signal : undefined,
        headers: { 'Accept': 'application/json' }
      });
      if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
      return seriesFromPayload(await resp.json());
    } finally {
      if (timer) clearTimeout(timer);
    }
  }

  function ensureStylesInjected() {
    if (document.getElementById('ge-charts-style')) return;
    const css = `
      .GEdatachart.smallChart { box-sizing:border-box; width:100% !important; max-width:100% !important; min-width:0 !important; overflow:hidden !important; height:220px !important; touch-action:pan-y; }
      .GEChartBox { box-sizing:border-box; width:100%; max-width:100%; min-width:0; overflow:hidden; margin:0 !important; padding:0 !important; }
      .GEdatachart.smallChart canvas { display:block; width:100% !important; max-width:100% !important; height:100% !important; }
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

  function formatTickDate(epochMs) {
    try {
      const d = new Date(epochMs);
      if (Number.isNaN(d.getTime())) return '';
      const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      return months[d.getMonth()] + ' ' + d.getDate();
    } catch (e) {
      return '';
    }
  }

  function renderChart(container, series) {
    const ChartCtor = resolveChart();
    if (!ChartCtor) {
      log('e', 'Chart.js not available');
      return false;
    }
    ensureStylesInjected();

    const bodyColor = getComputedStyle(document.body).color || '#333';
    const cs = getComputedStyle(container);
    const styleH = parseFloat(cs.height) || 0;
    const inlineH = parseFloat((container.style && container.style.height) || '') || 0;
    const height = Math.max(styleH, inlineH, container.clientHeight || 0, 220);

    // Clear wiki "Loading" placeholder / prior canvas
    container.textContent = '';
    container.style.height = height + 'px';
    const canvas = document.createElement('canvas');
    canvas.setAttribute('aria-label', 'Grand Exchange price chart');
    container.appendChild(canvas);

    try {
      if (container.__osrsChart && typeof container.__osrsChart.destroy === 'function') {
        container.__osrsChart.destroy();
      }
      const chart = new ChartCtor(canvas, {
        type: 'line',
        data: {
          datasets: [{
            label: 'Price',
            data: series,
            borderColor: '#4572A7',
            backgroundColor: 'transparent',
            borderWidth: 2,
            pointRadius: 0,
            pointHoverRadius: 3,
            tension: 0.1,
            spanGaps: false
          }]
        },
        options: {
          responsive: true,
          maintainAspectRatio: false,
          animation: false,
          interaction: {
            mode: 'index',
            intersect: false
          },
          plugins: {
            legend: { display: false },
            tooltip: {
              enabled: true,
              callbacks: {
                title: function (items) {
                  if (!items || !items.length) return '';
                  const x = items[0].parsed && items[0].parsed.x;
                  if (typeof x !== 'number') return '';
                  try {
                    return new Date(x).toLocaleString();
                  } catch (e) {
                    return formatTickDate(x);
                  }
                },
                label: function (item) {
                  const y = item.parsed && item.parsed.y;
                  if (typeof y !== 'number') return '';
                  return y.toLocaleString() + ' gp';
                }
              }
            }
          },
          scales: {
            x: {
              type: 'linear',
              title: { display: false },
              grid: { display: false },
              ticks: {
                color: bodyColor,
                font: { size: 11 },
                maxRotation: 0,
                autoSkip: true,
                maxTicksLimit: 5,
                callback: function (value) {
                  return formatTickDate(value);
                }
              }
            },
            y: {
              title: { display: false },
              grid: { color: 'rgba(128,128,128,0.25)' },
              ticks: {
                color: bodyColor,
                font: { size: 11 },
                maxTicksLimit: 4,
                callback: function (value) {
                  return formatCompact(value);
                }
              }
            }
          }
        }
      });

      container.setAttribute('role', 'application');
      container.setAttribute('aria-label', 'Interactive Grand Exchange price chart. Drag or pinch horizontally to inspect prices.');
      container.tabIndex = 0;
      if (window.ResizeObserver) {
        if (container.__osrsChartResizeObserver) {
          try { container.__osrsChartResizeObserver.disconnect(); } catch (e) {}
        }
        const observer = new ResizeObserver(() => {
          try { chart.resize(); } catch (e) {}
        });
        observer.observe(container);
        container.__osrsChartResizeObserver = observer;
      }
      container.__osrsChart = chart;
      return true;
    } catch (e) {
      log('e', 'Failed to render chart', e);
      return false;
    }
  }

  function initOne(box) {
    try {
      const dataEl = box.querySelector('.GEdataprices');
      const chartEl = box.querySelector('.GEdatachart');
      if (!dataEl || !chartEl) return;
      const itemId = dataEl.getAttribute('data-itemid');
      if (!itemId) return;
      // Only skip work that already produced a chart. A failed or empty
      // fetch must remain retryable — marking rendered first left the
      // wiki "Loading" placeholder stuck forever.
      if (chartEl.dataset.rendered === '1' && chartEl.__osrsChart) return;
      const pendingAt = Number(chartEl.dataset.osrsChartPendingAt || '0');
      if (chartEl.dataset.osrsChartPending === '1' && pendingAt && (Date.now() - pendingAt) < 5000) return;
      chartEl.dataset.osrsChartPending = '1';
      chartEl.dataset.osrsChartPendingAt = String(Date.now());
      // Install swipe-back guard so horizontal drags inside the chart
      // don't trigger the app's back gesture.
      installSwipeBackGuard(chartEl);

      const clearPending = () => {
        delete chartEl.dataset.osrsChartPending;
        delete chartEl.dataset.osrsChartPendingAt;
      };
      const markUnavailable = () => {
        clearPending();
        if (!chartEl.__osrsChart) {
          chartEl.textContent = 'Price history unavailable';
          chartEl.dataset.rendered = '0';
        }
      };
      if (!chartEl.__osrsChartWatchdog) {
        chartEl.__osrsChartWatchdog = setTimeout(() => {
          chartEl.__osrsChartWatchdog = null;
          if (chartEl.__osrsChart || chartEl.querySelector('canvas')) return;
          log('e', 'GE chart watchdog expired still showing placeholder', itemId);
          markUnavailable();
        }, 7000);
      }

      const attempt = (remaining) => {
        fetchSeries(itemId)
          .then(series => {
            if (series.length) {
              if (renderChart(chartEl, series)) {
                chartEl.dataset.rendered = '1';
                clearPending();
                if (chartEl.__osrsChartWatchdog) {
                  clearTimeout(chartEl.__osrsChartWatchdog);
                  chartEl.__osrsChartWatchdog = null;
                }
                return;
              }
              log('w', 'renderChart did not produce a canvas', itemId);
            } else {
              log('w', 'No series data for item', itemId);
            }
            if (remaining > 0) {
              setTimeout(() => attempt(remaining - 1), 400);
            } else {
              markUnavailable();
            }
          })
          .catch(err => {
            log('e', `fetchSeries failed for ${itemId}`, err);
            if (remaining > 0) {
              setTimeout(() => attempt(remaining - 1), 400);
            } else {
              markUnavailable();
            }
          });
      };
      attempt(1);
    } catch (e) {
      log('e', 'initOne error', e);
    }
  }

  function markUnavailable(boxes) {
    boxes.forEach((box) => {
      const chartEl = box.querySelector('.GEdatachart');
      if (chartEl && !chartEl.__osrsChart && chartEl.dataset.rendered !== '1') {
        chartEl.textContent = 'Price history unavailable';
        chartEl.dataset.rendered = '0';
      }
    });
  }

  let chartjsDeadline = 0;
  let chartjsWaitQueued = false;
  let initStartedAt = 0;

  function initAll() {
    if (!document || !document.body) return;
    const boxes = document.querySelectorAll('.GEChartBox');
    if (!boxes || boxes.length === 0) return;
    if (!initStartedAt) initStartedAt = Date.now();
    if (Date.now() - initStartedAt > 6000) {
      log('e', 'GE chart init exceeded 6s budget');
      markUnavailable(boxes);
      return;
    }
    if (!resolveChart()) {
      const now = Date.now();
      if (!chartjsDeadline) chartjsDeadline = now + 4000;
      if (now >= chartjsDeadline) {
        log('e', 'Chart.js never became available');
        markUnavailable(boxes);
        return;
      }
      if (!chartjsWaitQueued) {
        chartjsWaitQueued = true;
        log('w', 'Chart.js not yet loaded; delaying init');
        setTimeout(() => {
          chartjsWaitQueued = false;
          initAll();
        }, 100);
      }
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

  function kick(resetBudget) {
    if (resetBudget) {
      initStartedAt = 0;
      chartjsDeadline = 0;
    }
    initAll();
  }

  // Kickoff. First-open of an adopted/pre-rendered WKWebView can miss
  // DOMContentLoaded and leave fetch pending; pageshow/visibility retry.
  ready(initAll);
  window.addEventListener('pageshow', () => kick(true));
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible') kick(true);
  });
  // Also observe late-added content
  const mo = new MutationObserver(() => initAll());
  ready(() => {
    if (document.body) mo.observe(document.body, { childList: true, subtree: true });
  });

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
    const onUp = () => { down = false; if (sent) {
        if (resetTimer) clearTimeout(resetTimer);
        resetTimer = setTimeout(() => { sent = false; send(false); }, 250);
      } };

    if (window.PointerEvent) {
      el.addEventListener('pointerdown', (e) => onDown(e.clientX, e.clientY), { passive: true });
      el.addEventListener('pointermove', (e) => onMove(e.clientX, e.clientY), { passive: true });
      el.addEventListener('pointerup', onUp, { passive: true });
      el.addEventListener('pointercancel', onUp, { passive: true });
      el.addEventListener('pointerleave', onUp, { passive: true });
    } else {
      el.addEventListener('touchstart', (e) => { const t = e.touches[0]; if (t) onDown(t.clientX, t.clientY); }, { passive: true });
      el.addEventListener('touchmove', (e) => { const t = e.touches[0]; if (t) onMove(t.clientX, t.clientY); }, { passive: true });
      el.addEventListener('touchend', onUp, { passive: true });
      el.addEventListener('mousedown', (e) => onDown(e.clientX, e.clientY), { passive: true });
      el.addEventListener('mousemove', (e) => onMove(e.clientX, e.clientY), { passive: true });
      el.addEventListener('mouseup', onUp, { passive: true });
      el.addEventListener('mouseleave', onUp, { passive: true });
    }
  }

  // Global, capture-phase guard for chart gesture layers.
  // Primary enforcement also happens in horizontal_scroll_interceptor.js
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
