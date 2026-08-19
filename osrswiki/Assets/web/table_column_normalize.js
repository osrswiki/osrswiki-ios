// Equalize sibling stat cells so leftover table width cannot dump onto the
// last column (the "wide ranged cell" failure). Applies to every bonuses /
// nested-stat row, not a specific article.
(function () {
  function tableCellsWrapEnabled() {
    return document.documentElement.classList.contains('osrs-table-cells-wrap') ||
      (document.body && document.body.classList.contains('osrs-table-cells-wrap'));
  }

  function median(values) {
    if (!values.length) return 0;
    const sorted = values.slice().sort((a, b) => a - b);
    const mid = Math.floor(sorted.length / 2);
    return sorted.length % 2 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
  }

  function normalizeRow(row) {
    const cells = Array.from(row.children).filter((cell) => {
      if (!(cell instanceof HTMLElement)) return false;
      return cell.classList.contains('infobox-nested');
    });
    if (cells.length < 3) return;
    const table = row.closest('table');
    if (table) {
      table.style.setProperty('table-layout', 'fixed', 'important');
    }
    const widths = cells.map((cell) => cell.getBoundingClientRect().width);
    const mid = median(widths);
    if (mid < 8) return;
    const widest = Math.max.apply(null, widths);
    const total = widths.reduce((sum, width) => sum + width, 0);
    if (widest <= mid * 1.15) return;
    const target = Math.max(1, Math.floor(total / cells.length));
    cells.forEach((cell) => {
      cell.style.setProperty('width', target + 'px', 'important');
      cell.style.setProperty('max-width', target + 'px', 'important');
      cell.style.setProperty('min-width', '0', 'important');
    });
  }

  function isIOSWebKit() {
    return typeof navigator !== 'undefined' && /iPhone|iPad|iPod/.test(navigator.userAgent);
  }

  function applySmallTableIconSize(img) {
    if (!(img instanceof HTMLElement)) return;
    img.removeAttribute('width');
    img.removeAttribute('height');
    img.style.setProperty('display', 'inline-block', 'important');
    img.style.setProperty('max-width', '2em', 'important');
    img.style.setProperty('max-height', '2em', 'important');
    img.style.setProperty('width', 'auto', 'important');
    img.style.setProperty('object-fit', 'contain', 'important');
    img.style.setProperty('vertical-align', 'middle', 'important');
    // Wiki/Minerva wrappers can still pin table glyphs to 1em on WebKit.
    // Android is already height:auto + max 2em; iOS needs an explicit 2em
    // height so those wrappers cannot shrink the bitmap.
    if (isIOSWebKit()) {
      img.style.setProperty('height', '2em', 'important');
      img.style.setProperty('min-height', '2em', 'important');
    } else {
      img.style.setProperty('height', 'auto', 'important');
    }
  }

  function tightenBonusesCells(table) {
    table.querySelectorAll(':is(th, td).infobox-padding').forEach((cell) => {
      const row = cell.parentElement;
      if (row && row.children.length === 1) {
        row.style.setProperty('display', 'none', 'important');
      }
      cell.style.setProperty('display', 'none', 'important');
      cell.style.setProperty('height', '0', 'important');
      cell.style.setProperty('padding', '0', 'important');
    });
    table.querySelectorAll('.infobox-subheader').forEach((cell) => {
      if (!tableCellsWrapEnabled()) {
        cell.style.setProperty('white-space', 'nowrap', 'important');
      } else {
        cell.style.removeProperty('white-space');
      }
      cell.style.setProperty('overflow-wrap', 'normal', 'important');
      cell.style.setProperty('word-break', 'keep-all', 'important');
      cell.style.setProperty('vertical-align', 'middle', 'important');
      cell.style.setProperty('padding-block', '1px', 'important');
      cell.style.setProperty('line-height', '1.1', 'important');
      cell.style.removeProperty('max-width');
      cell.querySelectorAll('a').forEach((link) => {
        if (!(link instanceof HTMLElement)) return;
        link.style.setProperty('min-height', '0', 'important');
        link.style.setProperty('min-width', '0', 'important');
        link.style.setProperty('line-height', '1.2', 'important');
      });
    });
    table.querySelectorAll(':is(th, td).infobox-nested').forEach((cell) => {
      cell.style.setProperty('padding', '1px 0.08em', 'important');
      cell.style.setProperty('line-height', '1.05', 'important');
      cell.style.setProperty('min-height', '0', 'important');
      cell.style.setProperty('height', 'auto', 'important');
      cell.style.setProperty('overflow', 'visible', 'important');
      cell.style.setProperty('text-align', 'center', 'important');
      cell.style.setProperty('vertical-align', 'middle', 'important');
      cell.style.setProperty('white-space', 'nowrap', 'important');
      const param = cell.getAttribute('data-attr-param') || '';
      const isSlotLink = /slot_link/i.test(param);
      cell.querySelectorAll('a, span, .mw-default-size').forEach((wrap) => {
        if (!(wrap instanceof HTMLElement)) return;
        if (isSlotLink && wrap.matches('a') && !wrap.querySelector('img')) {
          wrap.style.setProperty('display', 'inline', 'important');
          wrap.style.setProperty('width', 'auto', 'important');
          wrap.style.setProperty('max-width', 'none', 'important');
          wrap.style.setProperty('height', 'auto', 'important');
          wrap.style.setProperty('min-height', '0', 'important');
          wrap.style.setProperty('line-height', '1.2', 'important');
          wrap.style.setProperty('margin', '0', 'important');
          wrap.style.setProperty('padding', '0', 'important');
          wrap.style.setProperty('text-align', 'center', 'important');
          wrap.style.setProperty('vertical-align', 'middle', 'important');
          return;
        }
        wrap.style.setProperty('display', 'inline-block', 'important');
        wrap.style.setProperty('width', 'auto', 'important');
        wrap.style.setProperty('max-width', '100%', 'important');
        wrap.style.setProperty('height', 'auto', 'important');
        wrap.style.setProperty('min-height', '0', 'important');
        wrap.style.setProperty('margin', '0', 'important');
        wrap.style.setProperty('padding', '0', 'important');
        wrap.style.setProperty('vertical-align', 'middle', 'important');
      });
      if (isSlotLink) {
        cell.style.setProperty('display', 'table-cell', 'important');
        cell.style.setProperty('text-align', 'center', 'important');
        cell.style.setProperty('vertical-align', 'middle', 'important');
      }
      const img = cell.querySelector('img');
      if (img) {
        img.removeAttribute('width');
        img.removeAttribute('height');
        img.style.setProperty('display', 'inline-block', 'important');
        img.style.setProperty('margin', '0 auto', 'important');
        img.style.setProperty('max-width', '2em', 'important');
        img.style.setProperty('max-height', '2em', 'important');
        img.style.setProperty('width', 'auto', 'important');
        img.style.setProperty('height', 'auto', 'important');
        img.style.setProperty('object-fit', 'contain', 'important');
        img.style.setProperty('vertical-align', 'middle', 'important');
      }
    });
  }

  function tightenTableIcons(root) {
    root.querySelectorAll('table :is(td, th) .scp').forEach((scp) => {
      if (!(scp instanceof HTMLElement)) return;
      scp.style.setProperty('display', 'inline-flex', 'important');
      scp.style.setProperty('align-items', 'center', 'important');
      scp.style.setProperty('height', 'auto', 'important');
      scp.style.setProperty('min-height', '0', 'important');
      scp.style.setProperty('vertical-align', 'middle', 'important');
    });
    root.querySelectorAll(
      'table :is(td, th):not(.infobox-bonuses-image) :is(.scp, .inventory-image, .mw-default-size) img'
    ).forEach((img) => {
      if (!(img instanceof HTMLElement)) return;
      if (img.closest('.infobox-bonuses-image, .infobox-image, figure, .infobox-nested, .infobox-subheader')) return;
      const width = Number(img.getAttribute('width') || 0);
      const height = Number(img.getAttribute('height') || 0);
      if ((width && width > 64) || (height && height > 64)) return;
      applySmallTableIconSize(img);
    });
  }

  function normalize(root) {
    const scope = root && root.querySelectorAll ? root : document;
    scope.querySelectorAll('table.infobox-bonuses').forEach((table) => {
      tightenBonusesCells(table);
      table.querySelectorAll('tr').forEach(normalizeRow);
    });
    tightenTableIcons(scope);
  }

  function ready(fn) {
    if (document.readyState === 'complete' || document.readyState === 'interactive') {
      setTimeout(fn, 0);
    } else {
      document.addEventListener('DOMContentLoaded', fn);
    }
  }

  ready(normalize);
  ready(() => {
    let queued = false;
    const observer = new MutationObserver(() => {
      if (queued) return;
      queued = true;
      setTimeout(() => {
        queued = false;
        normalize();
      }, 50);
    });
    if (document.body) observer.observe(document.body, { childList: true, subtree: true });
  });

  window.__osrsNormalizeArticleTables = normalize;
  window.osrsApplyTableCellWrapPreference = function (enabled) {
    const wrap = !!enabled;
    [document.documentElement, document.body].forEach((element) => {
      if (element) element.classList.toggle('osrs-table-cells-wrap', wrap);
    });
    document.querySelectorAll('th, td').forEach((cell) => {
      if (!(cell instanceof HTMLElement)) return;
      if (cell.closest('.collapsible-header, .collapsible-close-button, .collapsible-close-footer')) return;
      if (cell.matches('.infobox-nested')) return;
      if (wrap && cell.style.getPropertyValue('white-space') === 'nowrap') {
        cell.style.removeProperty('white-space');
      }
    });
    if (!wrap) {
      normalize();
    }
  };
  window.__osrsDumpArticleTableMetrics = function () {
    function box(el) {
      if (!el) return null;
      const r = el.getBoundingClientRect();
      return {
        w: Math.round(r.width * 10) / 10,
        h: Math.round(r.height * 10) / 10,
        x: Math.round(r.left * 10) / 10,
        y: Math.round(r.top * 10) / 10
      };
    }
    const bonuses = [];
    document.querySelectorAll('table.infobox-bonuses tr').forEach((row, index) => {
      const cells = Array.from(row.querySelectorAll(':scope > :is(th, td)')).map((cell) => {
        const style = window.getComputedStyle(cell);
        const img = cell.querySelector('img');
        const imgBox = box(img);
        const cellBox = box(cell);
        const text = (cell.textContent || '').replace(/\s+/g, ' ').trim();
        return {
          tag: cell.tagName,
          cls: cell.className,
          param: cell.getAttribute('data-attr-param'),
          w: cellBox.w,
          h: cellBox.h,
          whiteSpace: style.whiteSpace,
          textAlign: style.textAlign,
          verticalAlign: style.verticalAlign,
          display: style.display,
          wrap: text.includes(' ') ? text : text,
          lines: Math.max(1, Math.round((cellBox.h || 0) / Math.max(parseFloat(style.lineHeight) || 16, 8))),
          img: imgBox,
          imgCenterDeltaX: imgBox && cellBox
            ? Math.round((imgBox.x + imgBox.w / 2 - (cellBox.x + cellBox.w / 2)) * 10) / 10
            : 0,
          imgCenterDeltaY: imgBox && cellBox
            ? Math.round((imgBox.y + imgBox.h / 2 - (cellBox.y + cellBox.h / 2)) * 10) / 10
            : 0,
          text: text.slice(0, 48)
        };
      });
      if (cells.length) bonuses.push({ index, cells });
    });
    const tableIcons = Array.from(
      document.querySelectorAll('table :is(td, th):not(.infobox-bonuses-image) img.mw-file-element')
    ).slice(0, 24).map((img) => {
      const cell = img.closest('th, td');
      const text = cell ? cell.querySelector('a:not(:has(img)), span:not(:has(img))') : null;
      const imgBox = box(img);
      const textBox = box(text);
      const cellBox = box(cell);
      return {
        alt: img.getAttribute('alt') || '',
        img: imgBox,
        text: textBox,
        cellH: cellBox ? cellBox.h : null,
        alignDeltaY: imgBox && textBox
          ? Math.round((imgBox.y + imgBox.h / 2 - (textBox.y + textBox.h / 2)) * 10) / 10
          : null,
        parent: img.closest('.scp, .inventory-image, .mw-default-size')
          ? (img.closest('.scp') ? 'scp' : img.closest('.inventory-image') ? 'inventory' : 'file')
          : 'other'
      };
    });
    const tabbers = Array.from(document.querySelectorAll('.tabber')).map((tabber) => {
      const select = tabber.querySelector('select.osrs-tabber-select');
      const panel = tabber.querySelector('.osrs-tabber-panel');
      return {
        live: tabber.classList.contains('tabberlive'),
        selectOptions: select ? Array.from(select.options).map((o) => o.textContent) : [],
        selected: select ? select.options[select.selectedIndex] && select.options[select.selectedIndex].textContent : null,
        panelTables: panel ? panel.querySelectorAll('table').length : 0,
        visibleTabs: Array.from(tabber.querySelectorAll('.tabbertab')).filter((t) => t.style.display !== 'none' && !t.hidden).length
      };
    });
    const paddingRows = document.querySelectorAll('table.infobox-bonuses .infobox-padding').length;
    const visiblePaddingRows = Array.from(document.querySelectorAll('table.infobox-bonuses .infobox-padding')).filter((el) => {
      const style = window.getComputedStyle(el);
      return style.display !== 'none' && el.getBoundingClientRect().height > 1;
    }).length;
    return { bonuses, tableIcons, tabbers, paddingRows, visiblePaddingRows };
  };
})();

