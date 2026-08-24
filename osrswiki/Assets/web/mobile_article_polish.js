
/* Overnight: Android System WebView may lack :has() — guard querySelectorAll. */
(function(){
  if (window.__osrsSafeQsa) return;
  window.__osrsSafeQsa = function(root, sel) {
    try { return root.querySelectorAll(sel); } catch (e) { return []; }
  };
})();

(function () {
  'use strict';

  const diagnostics = {
    inlineIcons: 0,
    portraitImages: 0,
    vignettes: 0,
    scrollRegions: 0,
    primaryInfoboxes: 0,
    intrinsicRecipes: 0,
    mapTables: 0
  };
  window.__osrsArticlePolishDiagnostics = diagnostics;

  function numericAttribute(image, name) {
    const value = Number(image.getAttribute(name) || image.dataset['file' + name[0].toUpperCase() + name.slice(1)] || 0);
    return Number.isFinite(value) ? value : 0;
  }

  function osrsAuthoredPhrasingText(element) {
    if (!element || !element.cloneNode) return '';
    const clone = element.cloneNode(true);
    clone.querySelectorAll('img').forEach((image) => image.remove());
    return normalizeText(clone.textContent);
  }

  function osrsWrapperIsIconChrome(element) {
    if (!element) return false;
    if (osrsAuthoredPhrasingText(element)) return false;
    return Array.from(element.querySelectorAll('*')).every((child) =>
      child.matches('a, span, img')
    );
  }

  function hasOnlyInlineIconContent(element) {
    if (!osrsWrapperIsIconChrome(element)) return false;
    return element.querySelectorAll('img.osrs-inline-icon').length === 1;
  }

  function normalizeText(text) {
    return (text || '').replace(/\s+/g, ' ').trim();
  }

  function markInlineImages(root) {
    root.querySelectorAll('img.mw-file-element:not(.osrs-inline-icon)').forEach((image) => {
      const width = numericAttribute(image, 'width');
      const height = numericAttribute(image, 'height');
      const phrasing = image.closest('p, li, td, th, figcaption');
      const excluded = image.closest('figure, .gallery, .infobox-image, .infobox-bonuses-image, .infobox-nested, .infobox-bonuses, .navbox');
      if (!phrasing || excluded || width <= 0 || height <= 0 || width > 48 || height > 48) return;

      image.classList.add('osrs-inline-icon');
      image.removeAttribute('width');
      image.removeAttribute('height');
      let wrapper = image.parentElement;
      while (wrapper && wrapper !== phrasing && /^(A|SPAN)$/i.test(wrapper.tagName)) {
        /* Only chrome around the bitmap. Grouping spans that also hold the
           following sentence must stay in normal paragraph line boxes. */
        if (osrsWrapperIsIconChrome(wrapper)) {
          wrapper.classList.add('osrs-inline-icon-wrapper');
        }
        wrapper = wrapper.parentElement;
      }
      diagnostics.inlineIcons += 1;

      // Some templates place a prose icon in its own otherwise-empty paragraph. Treat that
      // paragraph as phrasing content so the icon does not manufacture a blank article row.
      if (phrasing.tagName === 'P' && !osrsAuthoredPhrasingText(phrasing)) {
        phrasing.classList.add('osrs-inline-icon-only-paragraph');
      }
    });

    window.__osrsSafeQsa(root, 'p > span:has(img.osrs-inline-icon)').forEach((wrapper) => {
      if (hasOnlyInlineIconContent(wrapper)) {
        wrapper.classList.add('osrs-inline-lore-note');
      }
    });

    /* Templates such as LoreSources wrap the icon and the sourced sentence in
       one span. That span is not icon chrome: keep its authored font-size and
       let wrapping lines size to a normal line-height. */
    window.__osrsSafeQsa(root, '.osrs-inline-icon-wrapper, p span:has(img.osrs-inline-icon), li span:has(img.osrs-inline-icon)').forEach((wrapper) => {
      if (!wrapper.querySelector('img')) return;
      if (osrsWrapperIsIconChrome(wrapper)) return;
      if (!osrsAuthoredPhrasingText(wrapper)) return;
      wrapper.classList.remove('osrs-inline-icon-wrapper');
      wrapper.classList.add('osrs-inline-icon-prose');
    });

    // Keep structurally isolated inline icons and following prose in one line box without
    // depending on a template name, page title, or presentation-style substring.
    window.__osrsSafeQsa(root, 'p:has(> .osrs-inline-lore-note), p:has(> .osrs-inline-icon-prose)').forEach((paragraph) => {
      paragraph.classList.add('osrs-inline-lore-paragraph');
    });
  }

  function markBalancedImages(root) {
    root.querySelectorAll('.infobox-image img.mw-file-element, .infobox-full-width-content img.mw-file-element, .infobox-bonuses-image img.mw-file-element').forEach((image) => {
      if (image.closest('.inventory-image, .GEChartBox')) return;
      const width = numericAttribute(image, 'width');
      const height = numericAttribute(image, 'height');
      if (width >= 80 && height / Math.max(width, 1) >= 1.45) {
        image.classList.add('osrs-balanced-portrait');
        diagnostics.portraitImages += 1;
      }
    });

    root.querySelectorAll('figure.mw-halign-left, figure.mw-halign-right, .thumb.tleft, .thumb.tright, .floatleft, .floatright').forEach((figure) => {
      if (figure.classList.contains('osrs-balanced-vignette') ||
          figure.closest('.infobox, .gallery, .navbox, .mw-kartographer-map, .GEChartBox')) return;
      const images = figure.querySelectorAll('img.mw-file-element');
      if (images.length !== 1) return;
      const image = images[0];
      const width = numericAttribute(image, 'width') || image.naturalWidth;
      const height = numericAttribute(image, 'height') || image.naturalHeight;
      if (width < 72 || height < 96 || height / Math.max(width, 1) < 1.25) return;
      figure.classList.add('osrs-balanced-vignette');
      figure.dataset.osrsAspect = String(height / width);
      diagnostics.vignettes += 1;
    });
  }

  function markSemanticTableRoles(root) {
    root.querySelectorAll('.collapsible-primary-infobox, table.main-infobox').forEach((element) => {
      demoteGenericScrollSurfacesWithin(element);
      if (!element.dataset.osrsPrimaryMeasured) {
        element.dataset.osrsPrimaryMeasured = 'true';
        diagnostics.primaryInfoboxes += 1;
      }
    });

    root.querySelectorAll('.recipe-table').forEach((wrapper) => {
      wrapper.classList.add('osrs-intrinsic-table', 'osrs-recipe-unit');
      demoteGenericScrollSurfacesWithin(wrapper);
      wrapper.querySelectorAll('table.wikitable').forEach((table) => {
        table.classList.add('osrs-intrinsic-recipe-table');
      });
      if (!wrapper.dataset.osrsRecipeMeasured) {
        wrapper.dataset.osrsRecipeMeasured = 'true';
        diagnostics.intrinsicRecipes += 1;
      }
    });

    window.__osrsSafeQsa(root, 'table:has(.mw-kartographer-map)').forEach((table) => {
      table.classList.add('osrs-map-table');
      const container = table.closest('.collapsible-container');
      if (container) container.classList.add('collapsible-map-table');
      const content = table.closest('.collapsible-content');
      demoteGenericScrollSurfacesWithin(container || content || table);
      if (!table.dataset.osrsMapTableMeasured) {
        table.dataset.osrsMapTableMeasured = 'true';
        diagnostics.mapTables += 1;
      }
    });
  }

  function isProtectedTableRole(table) {
    return !!(table && (
      table.matches('.main-infobox, .osrs-map-table') ||
      table.closest('.collapsible-primary-infobox, .collapsible-map-table, .osrs-recipe-unit')
    ));
  }

  function isProseBannerTable(table) {
    return !!(table && table.matches && table.matches(
      'table.messagebox, table.ambox, table.mbox, table.notebox, ' +
      'table.tmbox, table.cmbox, table.ombox, table.imbox, table.fmbox, ' +
      'table.archivelist'
    ));
  }

  function markTocLayoutTables(root) {
    const scope = root && root.querySelectorAll ? root : document;
    scope.querySelectorAll('table').forEach((table) => {
      if (table.classList.contains('wikitable') ||
          table.classList.contains('infobox') ||
          table.classList.contains('navbox') ||
          table.classList.contains('archivelist') ||
          isProseBannerTable(table)) {
        return;
      }
      const toc = table.querySelector('#toc, .toc');
      if (!toc) return;
      const tocCell = toc.closest('td, th');
      if (!tocCell || !table.contains(tocCell)) return;
      const hasSiblingContent = Array.from(table.querySelectorAll('td, th')).some((cell) => {
        return cell !== tocCell &&
          !tocCell.contains(cell) &&
          !cell.contains(toc) &&
          String(cell.textContent || '').trim().length > 0;
      });
      if (hasSiblingContent) {
        table.classList.add('osrs-toc-layout-table');
      }
    });
    scope.querySelectorAll('#toc, .toc').forEach((toc) => {
      const host = toc.closest('#toctemplate, [style*="float"]') || toc.parentElement;
      if (!host || host === document.body || host === document.documentElement) return;
      if (host.classList.contains('osrs-toc-layout-table')) return;
      const style = host.getAttribute('style') || '';
      const computed = window.getComputedStyle(host);
      const floated = /float\s*:\s*(right|left)/i.test(style) ||
        computed.float === 'right' ||
        computed.float === 'left';
      if (floated || host.id === 'toctemplate') {
        host.classList.add('osrs-toc-layout-host');
        host.style.setProperty('float', 'none', 'important');
        host.style.setProperty('width', 'fit-content', 'important');
        host.style.setProperty('max-width', '100%', 'important');
        host.style.setProperty('margin-inline', '0', 'important');
      }
    });
  }

  function expandProseBanners(root) {
    const scope = root && root.querySelectorAll ? root : document;
    scope.querySelectorAll(
      'table.messagebox, table.ambox, table.mbox, table.notebox, ' +
      'table.tmbox, table.cmbox, table.ombox, table.imbox, table.fmbox, ' +
      'table.archivelist, .osrs-calculator-templates'
    ).forEach((table) => {
      table.style.setProperty('float', 'none', 'important');
      table.style.setProperty('width', '100%', 'important');
      table.style.setProperty('max-width', '100%', 'important');
      table.style.setProperty('text-align', 'start', 'important');
    });
  }

  function unwrapGeneratedScrollSurface(table) {
    const surface = table && table.parentElement;
    if (!surface || !surface.classList ||
        !surface.classList.contains('osrs-scroll-generated-surface')) {
      return;
    }
    const parent = surface.parentElement;
    if (!parent) return;
    parent.insertBefore(table, surface);
    demoteGenericScrollSurface(surface);
    surface.remove();
  }

  function initializeLogicalScrollStart(surface) {
    if (!surface || surface.dataset.osrsScrollStartInitialized === 'true') return;
    // CSSOM uses zero for the inline-start edge in LTR and the start edge of RTL scrollports.
    // Set it once only; later polish passes must never reset a reader's position.
    surface.scrollLeft = 0;
    surface.dataset.osrsScrollStartInitialized = 'true';
  }

  function makeLocalScrollSurface(surface, label) {
    if (!surface || surface.closest('.collapsible-primary-infobox, .collapsible-map-table, .osrs-recipe-unit')) return;
    surface.classList.add('osrs-article-scroll-region', 'osrs-local-scroll-surface');
    surface.tabIndex = 0;
    surface.setAttribute('role', 'region');
    surface.setAttribute('aria-label', label || 'Scrollable table');
    initializeLogicalScrollStart(surface);
  }

  function demoteGenericScrollSurface(surface) {
    if (!surface?.classList) return;
    surface.classList.remove(
      'osrs-article-scroll-region',
      'osrs-local-scroll-surface',
      'osrs-scroll-affordance',
      'osrs-scroll-can-left',
      'osrs-scroll-can-right'
    );
    if (surface.getAttribute('role') === 'region') surface.removeAttribute('role');
    if (/^Scrollable\b/i.test(surface.getAttribute('aria-label') || '')) {
      surface.removeAttribute('aria-label');
    }
    if (surface.getAttribute('tabindex') === '0') surface.removeAttribute('tabindex');
    surface.style.removeProperty('--osrs-local-scrollport-width');
    delete surface.dataset.osrsScrollStartInitialized;
    delete surface.dataset.osrsLocalOverflowX;
    delete surface.dataset.osrsScrollAffordanceBound;
  }

  function demoteGenericScrollSurfacesWithin(root) {
    if (!root) return;
    if (root.matches?.('.osrs-local-scroll-surface, .osrs-article-scroll-region')) {
      demoteGenericScrollSurface(root);
    }
    root.querySelectorAll?.('.osrs-local-scroll-surface, .osrs-article-scroll-region')
      .forEach(demoteGenericScrollSurface);
  }

  function demoteRedundantOuterSurface(surface) {
    if (!surface) return;
    demoteGenericScrollSurface(surface);
    surface.classList.add('osrs-demoted-scroll-surface');
  }

  function localScrollSurfaceLabel(table) {
    const disclosure = table.closest('.collapsible-container')
      ?.querySelector('.collapsible-header .collapsible-label')
      ?.textContent?.trim();
    const caption = table.querySelector('caption')?.textContent?.trim();
    const semanticName = disclosure || caption || 'table';
    if (semanticName.toLowerCase().startsWith('scrollable ')) return semanticName;
    return semanticName.toLowerCase().endsWith(' table')
      ? `Scrollable ${semanticName}`
      : `Scrollable ${semanticName} table`;
  }

  function hasRealHorizontalOverflow(surface) {
    return !!(surface && surface.clientWidth > 0 && surface.scrollWidth > surface.clientWidth + 2);
  }

  // Tables with width:100% / table-layout:fixed report scrollWidth == the parent,
  // so they never get a local viewport. Measure the intrinsic max-content width
  // without leaving those squeeze rules in place.
  function restoreInlineStyle(style, name, previousValue, previousPriority) {
    if (previousValue) style.setProperty(name, previousValue, previousPriority || '');
    else style.removeProperty(name);
  }

  function tableIntrinsicScrollWidth(table) {
    if (!table) return 0;
    const style = table.style;
    const previous = {
      width: style.getPropertyValue('width'),
      widthPriority: style.getPropertyPriority('width'),
      maxWidth: style.getPropertyValue('max-width'),
      maxWidthPriority: style.getPropertyPriority('max-width'),
      tableLayout: style.getPropertyValue('table-layout'),
      tableLayoutPriority: style.getPropertyPriority('table-layout')
    };
    // Authored min-width (Combat stats 720px fixtures, wiki inline mins) must stay.
    // Stylesheet width:100% !important beats a non-important inline max-content,
    // so measurement has to use the important flag too.
    style.setProperty('width', 'max-content', 'important');
    style.setProperty('max-width', 'none', 'important');
    style.setProperty('table-layout', 'auto', 'important');
    const width = Math.max(table.scrollWidth, table.offsetWidth);
    restoreInlineStyle(style, 'width', previous.width, previous.widthPriority);
    restoreInlineStyle(style, 'max-width', previous.maxWidth, previous.maxWidthPriority);
    restoreInlineStyle(style, 'table-layout', previous.tableLayout, previous.tableLayoutPriority);
    return width;
  }

  function overflowingLocalSurface(root) {
    if (!root) return null;
    if (hasRealHorizontalOverflow(root)) return root;
    if (!root.querySelectorAll) return null;
    const nested = root.querySelectorAll('.osrs-local-scroll-surface, .osrs-disclosure-body');
    for (let i = 0; i < nested.length; i++) {
      if (hasRealHorizontalOverflow(nested[i])) return nested[i];
    }
    return null;
  }

  function localScrollOwnerForTarget(target) {
    if (!target || !target.closest) return null;
    if (target.closest('.collapsible-primary-infobox, .collapsible-map-table, .osrs-recipe-unit')) return null;
    const directSurface = overflowingLocalSurface(target.closest('.osrs-local-scroll-surface'));
    if (directSurface) return directSurface;
    const disclosure = target.closest('.collapsible-container');
    return overflowingLocalSurface(disclosure);
  }

  function markScrollableTables(root) {
    root.querySelectorAll('table').forEach((table) => {
      if (isProseBannerTable(table)) {
        unwrapGeneratedScrollSurface(table);
        return;
      }
      if (isProtectedTableRole(table) ||
          table.closest('.navbox, .scrollable-table-wrapper')) return;
      const existingLocalSurface = table.closest('.osrs-local-scroll-surface');
      const collapsibleContent = table.closest('.collapsible-content');
      if (collapsibleContent) {
        const viewportWidth = document.documentElement.clientWidth || window.innerWidth || 0;
        const parentWidth = collapsibleContent.clientWidth || viewportWidth;
        const availableWidth = Math.min(parentWidth || viewportWidth, viewportWidth);
        const isIrreduciblyWide = table.matches('.infobox-bonuses') ||
          tableIntrinsicScrollWidth(table) > Math.ceil(availableWidth + 2);
        if (isIrreduciblyWide) {
          // A generic interceptor may have wrapped this table before the disclosure transformer
          // ran. In that ordering the old scroll surface sits *outside* collapsibleContent, while
          // a right-floated intrinsic table can overflow toward negative X and contribute no
          // scrollWidth to that ancestor. Make the disclosure content itself the local viewport;
          // the canonical direct-child CSS then clears the float and anchors inline-start.
          const nestedExistingSurface = existingLocalSurface &&
            collapsibleContent.contains(existingLocalSurface)
            ? existingLocalSurface
            : null;
          const outerExistingSurface = existingLocalSurface && !nestedExistingSurface
            ? existingLocalSurface
            : null;
          if (outerExistingSurface) {
            // A disclosure must have exactly one physical and semantic viewport. Retire any
            // older outer owner—even one added by an earlier polish pass—and promote the
            // content that directly owns the intrinsic table geometry.
            demoteRedundantOuterSurface(outerExistingSurface);
          }
          // The wide table lives in .osrs-disclosure-body, which is the physical
          // overflow:auto scroller. Marking only .collapsible-content leaves a
          // non-overflowing ancestor; header/padding pans then become chrome swipes.
          const disclosureBody = collapsibleContent.querySelector(':scope > .osrs-disclosure-body');
          makeLocalScrollSurface(
            nestedExistingSurface || disclosureBody || collapsibleContent,
            localScrollSurfaceLabel(table)
          );
        }
        return;
      }
      if (existingLocalSurface) {
        makeLocalScrollSurface(existingLocalSurface, localScrollSurfaceLabel(table));
        return;
      }
      const parent = table.parentElement;
      if (!parent) return;
      const isWideInfobox = table.matches('.infobox-bonuses');
      if (!isWideInfobox &&
          tableIntrinsicScrollWidth(table) <= Math.ceil(document.documentElement.clientWidth - 24)) return;

      // Ordinary compact infoboxes keep their native layout. Wide switch/bonuses infoboxes
      // are the exception: their many columns and portrait states otherwise push the article
      // itself off-screen, so give only that component a local horizontal viewport.
      if (table.matches('.infobox') && !isWideInfobox) return;
      const wrapper = document.createElement('div');
      wrapper.className = 'osrs-article-scroll-region osrs-local-scroll-surface osrs-scroll-generated-surface';
      makeLocalScrollSurface(
        wrapper,
        localScrollSurfaceLabel(table)
      );
      parent.insertBefore(wrapper, table);
      wrapper.appendChild(table);
      diagnostics.scrollRegions += 1;
    });
  }

  function articleChromeOffsetPx() {
    const cs = getComputedStyle(document.documentElement);
    const parsePx = function(value) {
      const n = parseFloat(value);
      return Number.isFinite(n) ? n : 0;
    };
    return Math.max(parsePx(cs.scrollPaddingTop), parsePx(cs.paddingTop), 0);
  }

  function scrollArticleTargetBelowChrome(element, headerOffset) {
    if (!element) return;
    const offset = Number.isFinite(headerOffset) ? headerOffset : articleChromeOffsetPx();
    if (offset > 0) {
      element.style.scrollMarginTop = offset + 'px';
    }
    const rectTop = element.getBoundingClientRect().top;
    const scrollTop = window.pageYOffset || document.documentElement.scrollTop || 0;
    window.scrollTo(0, Math.max(0, scrollTop + rectTop - offset));
  }

  let scheduled = false;
  function applyPolish() {
    scheduled = false;
    markInlineImages(document);
    markBalancedImages(document);
    markSemanticTableRoles(document);
    markTocLayoutTables(document);
    expandProseBanners(document);
    markScrollableTables(document);
    document.documentElement.dataset.osrsArticlePolished = 'true';
  }
  window.OSRSApplyArticlePolish = applyPolish;
  window.OSRSArticlePolish = {
    apply: applyPolish,
    localScrollOwnerForTarget: localScrollOwnerForTarget,
    classifyTouchOwner: function(target) {
      const owner = localScrollOwnerForTarget(target);
      return {
        isLocalOwner: !!owner,
        owner: owner,
        ownerId: owner
          ? (owner.getAttribute('aria-label') || owner.id || 'local-scroll-surface')
          : 'article-navigation'
      };
    }
  };
  function schedule() {
    if (scheduled) return;
    scheduled = true;
    const run = function() {
      applyPolish();
    };
    if (typeof queueMicrotask === 'function') queueMicrotask(run);
    else Promise.resolve().then(run);
  }

  if (document.body) applyPolish();
  else if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', applyPolish, { once: true });
  else applyPolish();
  new MutationObserver(schedule).observe(document.documentElement, { childList: true, subtree: true });

  document.addEventListener('click', function (event) {
    const target = event.target;
    if (!(target instanceof Element)) return;
    const help = target.closest('.floornumber-help, .floor-convention, a[href*="Special:Preferences"]');
    if (help) {
      event.preventDefault();
      event.stopPropagation();
      if (window.OsrsWikiBridge && typeof window.OsrsWikiBridge.openFloorNumberingSettings === 'function') {
        window.OsrsWikiBridge.openFloorNumberingSettings();
      }
      return;
    }
    const link = target.closest('a[href^="#"]');
    if (!link) return;
    const chromeOffset = articleChromeOffsetPx();
    if (chromeOffset <= 0) return;
    const href = link.getAttribute('href') || '';
    if (href.length < 2) return;
    let id = href.slice(1);
    try { id = decodeURIComponent(id); } catch (e) {}
    if (!id) return;
    const destination = document.getElementById(id) ||
      (window.CSS && CSS.escape && document.querySelector('#' + CSS.escape(id)));
    if (!destination) return;
    event.preventDefault();
    scrollArticleTargetBelowChrome(destination, chromeOffset);
  }, true);
})();
