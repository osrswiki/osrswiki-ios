(function() {
    'use strict';

    // This script helps prevent the native Android swipe gestures (like back navigation)
    // from firing when the user is trying to scroll a horizontally-scrollable
    // element within the WebView, such as a wide table.

    let isHorizontallyScrollable = false;
    let geChartTouchActive = false;
    let scrollAffordanceRefreshScheduled = false;
    let gestureSequence = 0;
    let activeGestureId = null;
    let activeGestureOwner = null;
    let activeTouchSequence = null;
    // Native navigation asks for the terminal classification after WebKit has delivered
    // touchend. Keep the last completed sequence's answer until the next primary touch begins;
    // the transient bridge flag is intentionally cleared at touchend and cannot answer that race.
    let latestTouchOwnedByLocalHorizontalContent = false;
    let latestTouchSequence = 0;
    let activeTouchStartX = 0;
    let activeScrollOwner = null;
    let sequenceAxisLock = null;
    let startCanScrollPositive = false;
    let startCanScrollNegative = false;
    const touchOwnershipSnapshots = new Map();
    const maxTouchOwnershipSnapshots = 16;
    const scrollSurfaceMarker = 'osrsScrollAffordanceBound';
    const scrollAffordanceClass = 'osrs-scroll-affordance';
    const scrollCanLeftClass = 'osrs-scroll-can-left';
    const scrollCanRightClass = 'osrs-scroll-can-right';
    const generatedScrollSurfaceClass = 'osrs-scroll-generated-surface';
    const tableSelector = [
        'table.wikitable',
        'table.sortable',
        'table.filterable',
        'table.item-drops',
        'table.infobox-bonuses',
        'table.navbox',
        'table.questdetails',
        'table.calculator',
        'table[class*="combat"]',
        'table[class*="skill"]',
        'table[class*="training"]',
        'table[class*="league"]',
        'table[class*="task"]'
    ].join(',');
    const standaloneScrollSurfaceSelectorParts = [
        '.mw-parser-output > table.wikitable',
        '.mw-parser-output > .wikitable',
        '.mw-parser-output > table.sortable',
        '.mw-parser-output > table.filterable',
        '.mw-parser-output > table.item-drops',
        '.mw-parser-output > table.navbox',
        '.mwe-math-fallback-image-display',
        'math.mwe-math-element[display="block"]',
        '.mwe-math-element:has(.mwe-math-fallback-image-display)'
    ];
    var __osrsSupportsHas = false;
    try {
        __osrsSupportsHas = !!(window.CSS && CSS.supports && CSS.supports('selector(:has(*))'));
    } catch (e) { __osrsSupportsHas = false; }
    const standaloneScrollSurfaceSelector = (__osrsSupportsHas
        ? standaloneScrollSurfaceSelectorParts
        : standaloneScrollSurfaceSelectorParts.filter(function (p) { return p.indexOf(':has(') < 0; })
    ).join(',');
    
    // Helper function to log to Android
    function log(message) {
        if (window.OsrsWikiBridge && typeof window.OsrsWikiBridge.log === 'function') {
            window.OsrsWikiBridge.log('[HorizontalScroll] ' + message);
        }
    }

    function isQuoteBoxTable(table) {
        return !!(table && table.querySelector &&
            table.querySelector('td.quotation-mark, th.quotation-mark'));
    }

    function isProseBannerTable(table) {
        if (isQuoteBoxTable(table)) return true;
        return !!(table && table.matches && table.matches(
            'table.messagebox, table.ambox, table.mbox, table.notebox, ' +
            'table.tmbox, table.cmbox, table.ombox, table.imbox, table.fmbox'
        ));
    }

    function isCalculatorHostTable(table) {
        return !!(table && table.matches && (
            table.matches('table.calculator, .osrs-calculator-panel') ||
            table.closest('.osrs-calculator-layout, .osrs-calculator-panel') ||
            table.querySelector('[id$="Form"], .jcTable, .jsCalc-field, .oo-ui-fieldsetLayout')
        ));
    }

    function getScrollSurfaceForTable(table) {
        if (!table || !table.closest) {
            return null;
        }
        if (isProseBannerTable(table) ||
            isCalculatorHostTable(table) ||
            table.matches('.main-infobox, .osrs-map-table') ||
            table.closest('.collapsible-primary-infobox, .collapsible-map-table, .osrs-recipe-unit')) {
            return null;
        }
        return table.closest('.osrs-local-scroll-surface, .osrs-article-scroll-region') ||
            table.closest('.mw-parser-output > table.wikitable, .mw-parser-output > .wikitable') ||
            table;
    }

    function normalizeScrollSurface(surface) {
        if (!surface || String(surface.tagName || '').toLowerCase() !== 'table') {
            constrainScrollSurface(surface);
            return surface;
        }

        const existingWrapper = surface.parentElement &&
            surface.parentElement.classList &&
            surface.parentElement.classList.contains('osrs-article-scroll-region')
            ? surface.parentElement
            : null;
        if (existingWrapper) {
            constrainScrollSurface(existingWrapper);
            return existingWrapper;
        }

        if (surface.matches && surface.matches('table.wikitable') &&
            !surface.matches('.infobox, .infobox-bonuses, .navbox, .main-infobox') &&
            !surface.closest('.collapsible-primary-infobox, .osrs-recipe-unit') &&
            !(document.documentElement.classList.contains('osrs-table-cells-wrap') ||
                (document.body && document.body.classList.contains('osrs-table-cells-wrap')))) {
            surface.querySelectorAll(':scope > * > tr > :is(th, td), :scope > tr > :is(th, td)').forEach(function(cell) {
                cell.style.setProperty('white-space', 'nowrap');
            });
        }
        const parentWidth = surface.parentElement && surface.parentElement.clientWidth > 0
            ? surface.parentElement.clientWidth
            : window.innerWidth;
        const tableWidth = Math.max(surface.scrollWidth, surface.getBoundingClientRect().width);
        if (tableWidth <= parentWidth + 2) {
            return surface;
        }

        const wrapper = document.createElement('div');
        wrapper.className = 'osrs-article-scroll-region osrs-local-scroll-surface ' + generatedScrollSurfaceClass;
        surface.parentNode.insertBefore(wrapper, surface);
        wrapper.appendChild(surface);
        constrainScrollSurface(wrapper);
        return wrapper;
    }

    function constrainScrollSurface(surface) {
        if (!surface || !surface.classList || !surface.classList.contains('osrs-article-scroll-region')) {
            return;
        }
        const root = surface.closest('.mw-parser-output') || document.documentElement;
        const rootRect = root.getBoundingClientRect();
        const surfaceRect = surface.getBoundingClientRect();
        const viewportRight = Math.min(
            document.documentElement.clientWidth || window.innerWidth || rootRect.right,
            rootRect.right
        );
        const visibleWidth = Math.floor(Math.max(0, viewportRight - Math.max(0, surfaceRect.left)));
        if (visibleWidth > 0) {
            surface.style.setProperty('--osrs-local-scrollport-width', visibleWidth + 'px');
        }
    }

    function collectScrollSurfaces() {
        const surfaces = new Set();
        document.querySelectorAll(tableSelector).forEach(function(table) {
            const surface = getScrollSurfaceForTable(table);
            if (surface) {
                surfaces.add(surface);
            }
        });
        document.querySelectorAll(standaloneScrollSurfaceSelector).forEach(function(surface) {
            surfaces.add(surface);
        });
        return Array.from(new Set(Array.from(surfaces).map(normalizeScrollSurface))).filter(function(surface) {
            return surface &&
                typeof surface.scrollWidth !== 'undefined' &&
                typeof surface.clientWidth !== 'undefined' &&
                !isMainContentContainer(surface) &&
                !isMediaElement(surface);
        });
    }

    function updateScrollSurfaceState(surface) {
        const overflowX = Math.max(0, surface.scrollWidth - surface.clientWidth);
        const rect = surface.getBoundingClientRect();
        const isScrollable = surface.clientWidth > 0 && rect.height > 0 && overflowX > 2;
        surface.classList.toggle(scrollAffordanceClass, isScrollable);
        surface.classList.toggle(scrollCanLeftClass, isScrollable && surface.scrollLeft > 2);
        surface.classList.toggle(scrollCanRightClass, isScrollable && surface.scrollLeft < overflowX - 2);

        if (isScrollable) {
            surface.dataset.osrsLocalOverflowX = String(Math.round(overflowX));
            if (surface.dataset[scrollSurfaceMarker] !== 'true') {
                surface.addEventListener('scroll', function() {
                    updateScrollSurfaceState(surface);
                }, { passive: true });
                surface.dataset[scrollSurfaceMarker] = 'true';
            }
        } else {
            delete surface.dataset.osrsLocalOverflowX;
        }
    }

    function refreshHorizontalScrollAffordances() {
        scrollAffordanceRefreshScheduled = false;
        collectScrollSurfaces().forEach(updateScrollSurfaceState);
    }

    function scheduleScrollAffordanceRefresh() {
        if (scrollAffordanceRefreshScheduled) {
            return;
        }
        scrollAffordanceRefreshScheduled = true;
        const schedule = window.requestAnimationFrame || window.setTimeout;
        schedule(refreshHorizontalScrollAffordances, 16);
    }

    function describeTable(table) {
        const rect = table.getBoundingClientRect();
        const surface = getScrollSurfaceForTable(table) || table;
        const surfaceRect = surface.getBoundingClientRect();
        const isVisibleSurface = surface.clientWidth > 0 && surfaceRect.height > 0;
        return {
            className: String(table.className || '').slice(0, 160),
            caption: (table.querySelector('caption') ? table.querySelector('caption').textContent : '').trim().replace(/\s+/g, ' ').slice(0, 120),
            width: Math.round(rect.width),
            localOverflowX: isVisibleSurface ? Math.round(Math.max(0, surface.scrollWidth - surface.clientWidth)) : 0,
            hasAffordance: !!(surface.classList && surface.classList.contains(scrollAffordanceClass))
        };
    }

    function collectArticleMetrics() {
        refreshHorizontalScrollAffordances();
        const viewportWidth = window.innerWidth;
        const root = document.scrollingElement || document.documentElement;
        const rootOverflowX = Math.max(0, root.scrollWidth - viewportWidth);
        const tables = Array.from(document.querySelectorAll(tableSelector));
        const localTableOverflows = tables
            .map(describeTable)
            .filter(function(item) {
                return item.localOverflowX > 2;
            });
        return {
            rootOverflowX: Math.round(rootOverflowX),
            localTableOverflowCount: localTableOverflows.length,
            maxLocalTableOverflowX: Math.max(0, ...localTableOverflows.map(function(item) { return item.localOverflowX; })),
            tableAffordanceCount: document.querySelectorAll('.' + scrollAffordanceClass).length,
            tableAffordanceCanRightCount: document.querySelectorAll('.' + scrollAffordanceClass + '.' + scrollCanRightClass).length,
            tableAffordanceCanLeftCount: document.querySelectorAll('.' + scrollAffordanceClass + '.' + scrollCanLeftClass).length,
            localTableOverflows: localTableOverflows.slice(0, 20)
        };
    }

    window.refreshHorizontalScrollAffordances = refreshHorizontalScrollAffordances;
    window.OSRSArticleMetrics = {
        collect: collectArticleMetrics,
        refreshHorizontalScrollAffordances: refreshHorizontalScrollAffordances
    };
    window.OSRSHorizontalGestureOwnership = {
        latestTouchIsOwned: function() {
            return latestTouchOwnedByLocalHorizontalContent;
        },
        latestTouchSequence: function() {
            return latestTouchSequence;
        },
        snapshotForSequence: function(sequence) {
            const snapshot = touchOwnershipSnapshots.get(Number(sequence));
            return snapshot ? { sequence: snapshot.sequence, owned: snapshot.owned } : null;
        }
    };

    /**
     * Checks if an element is a main content container that shouldn't block gestures.
     * These are typically layout containers that are slightly wider than viewport.
     * @param {HTMLElement} element The element to check.
     * @returns {boolean} True if element is a main content container.
     */
    function isMainContentContainer(element) {
        const className = (element.className || '').toString().toLowerCase();
        const id = (element.id || '').toLowerCase();
        const tagName = element.tagName ? element.tagName.toLowerCase() : '';
        
        // Skip the body element - it shouldn't block navigation gestures
        if (tagName === 'body') {
            log('Found body element - skipping to allow navigation');
            return true;
        }
        
        // Check for MediaWiki main content containers
        if (className.includes('mw-content-ltr') && className.includes('mw-parser-output')) {
            log('Found main parser output container');
            return true;
        }
        
        // Check for section containers that are wide due to embedded content
        if (tagName === 'section' && (className.includes('collapsible-block') || className.includes('mf-section'))) {
            log('Found section container - likely wide due to embedded content');
            return true;
        }
        
        // Check for other common main content containers
        if (className.includes('main-content') || 
            className.includes('content-wrapper') ||
            className.includes('page-content') ||
            id.includes('content') ||
            id.includes('main')) {
            log('Found main content container by class/id');
            return true;
        }
        
        return false;
    }

    /**
     * Checks if an element is within a media container that should not block gestures.
     * @param {HTMLElement} element The element to check.
     * @returns {boolean} True if element is within excluded media.
     */
    function isMediaElement(element) {
        let current = element;
        let depth = 0;
        
        while (current && current !== document.body && depth < 10) {
            depth++;
            
            // Enhanced YouTube detection
            if (current.tagName === 'IFRAME') {
                const src = current.src || '';
                if (src.includes('youtube') || src.includes('youtu.be')) {
                    log('Found YouTube iframe: ' + src);
                    return true;
                }
            }
            
            // Check if we're inside a YouTube iframe's document
            if (window.location.href.includes('youtube')) {
                log('Inside YouTube iframe document');
                return true;
            }
            
            // Check for video elements
            if (current.tagName === 'VIDEO') {
                log('Found video element');
                return true;
            }
            
            // Check IDs and classes
            const id = (current.id || '').toLowerCase();
            const className = (current.className || '').toString().toLowerCase();
            
            if (id.includes('youtube') || id.includes('player') || id.includes('video')) {
                log('Found media by ID: ' + id);
                return true;
            }
            
            if (className.includes('youtube') || 
                className.includes('video') || 
                className.includes('player') || 
                className.includes('embed') ||
                className.includes('media')) {
                log('Found media by class: ' + className);
                return true;
            }
            
            current = current.parentElement;
        }
        return false;
    }

    /**
     * Touch start event listener.
     * Checks if the touch is on a scrollable element and notifies the native app.
     */
    function isInGEChart(target) {
        return !!(target && target.closest && (target.closest('.GEdatachart') || target.closest('.GEChartBox')));
    }

    // The in-article audio seek slider owns its whole pointer sequence: a drag
    // on the thumb must scrub, never open article back or the contents drawer.
    function isInArticleAudioSeek(target) {
        return !!(target && target.closest && target.closest('.osrs-article-audio-seek'));
    }

    function isInProtectedNonlocalTableRole(target) {
        return !!(target && target.closest && target.closest(
            '.collapsible-primary-infobox, .collapsible-map-table, .osrs-recipe-unit'
        ));
    }

    function isLayoutRoot(element) {
        if (!element || !element.tagName) return true;
        const tag = element.tagName.toLowerCase();
        if (tag === 'html' || tag === 'body') return true;
        const className = (element.className || '').toString();
        return className.includes('mw-parser-output') || className.includes('mw-body-content');
    }

    function isOverflowingHorizontalScroller(element) {
        if (!element || isLayoutRoot(element)) return false;
        let overflowX = '';
        try {
            overflowX = window.getComputedStyle(element).overflowX;
        } catch (_) {
            return false;
        }
        if (overflowX !== 'auto' && overflowX !== 'scroll') return false;
        return element.scrollWidth > element.clientWidth + 2;
    }

    function overflowingHorizontalOwner(root) {
        if (!root) return null;
        if (((root.classList && root.classList.contains('osrs-local-scroll-surface')) ||
                isOverflowingHorizontalScroller(root)) &&
            root.scrollWidth > root.clientWidth + 2) {
            return root;
        }
        if (!root.querySelectorAll) return null;
        const nested = root.querySelectorAll('.osrs-local-scroll-surface, .osrs-disclosure-body');
        for (let i = 0; i < nested.length; i++) {
            const candidate = nested[i];
            if (candidate.scrollWidth > candidate.clientWidth + 2) return candidate;
        }
        return null;
    }

    function canConsumeHorizontalDelta(owner, deltaX) {
        if (!owner) return false;
        const capacity = horizontalEdgeCapacity(owner);
        if (!capacity.hasOverflow) return false;
        if (Math.abs(deltaX) < 10) return true;
        if (deltaX > 0) return capacity.canPositive;
        return capacity.canNegative;
    }

    // Snapshot of whether this pointer could pan the local scroller when it
    // began. Live scrollLeft is not used to hand off the same finger sequence
    // to article swipe after the table hits an edge. Subpixel leftovers on the
    // trailing edge must still count as terminal so a new swipe can open
    // contents the way a zero scrollLeft opens back.
    function horizontalEdgeCapacity(owner) {
        if (!owner) {
            return { hasOverflow: false, canPositive: false, canNegative: false };
        }
        const maxScroll = owner.scrollWidth - owner.clientWidth;
        if (maxScroll <= 2) {
            return { hasOverflow: false, canPositive: false, canNegative: false };
        }
        const scrollLeft = owner.scrollLeft;
        const edgeSlop = 8;
        return {
            hasOverflow: true,
            canPositive: scrollLeft > edgeSlop,
            canNegative: scrollLeft < maxScroll - edgeSlop
        };
    }

    function scrollOwnerForTarget(target) {
        let current = target;
        while (current && current !== document.body) {
            const markedOwner = current.classList && current.classList.contains('osrs-local-scroll-surface');
            if ((markedOwner || isOverflowingHorizontalScroller(current)) &&
                current.scrollWidth > current.clientWidth + 2) {
                return current;
            }
            current = current.parentElement;
        }
        // Infoboxes, recipes, and map tables are not treated as one giant scroller, but a
        // real overflow:auto/scroll descendant still owns this pointer sequence.
        if (isInProtectedNonlocalTableRole(target)) return null;
        // The disclosure is one interaction region. A horizontal drag that begins on its
        // header/padding must not become article navigation when the disclosed content owns a
        // real local horizontal viewport (for example Combat stats).
        const disclosure = target?.closest?.('.collapsible-container');
        return overflowingHorizontalOwner(disclosure);
    }

    function scrollOwnerForPoint(clientX, clientY) {
        if (!Number.isFinite(clientX) || !Number.isFinite(clientY)) return null;
        const pointTarget = document.elementFromPoint(clientX, clientY);
        return scrollOwnerForTarget(pointTarget);
    }

    window.OSRSArticleGestureOwnership = {
        classifyPoint: function(clientX, clientY) {
            const target = document.elementFromPoint(clientX, clientY);
            const owner = scrollOwnerForTarget(target);
            const mapPlaceholder = target && target.closest ? target.closest('.mw-kartographer-map') : null;
            const chart = isInGEChart(target);
            const audioSeek = isInArticleAudioSeek(target);
            const isLocalOwner = !!(owner || mapPlaceholder || chart || audioSeek);
            return {
                isLocalOwner: isLocalOwner,
                ownerId: chart
                    ? 'price-chart'
                    : audioSeek
                    ? 'article-audio-seek'
                    : (mapPlaceholder?.id || owner?.getAttribute('aria-label') || owner?.id || (isLocalOwner ? 'local-scroll-surface' : 'article-navigation')),
                targetTag: String(target?.tagName || ''),
                targetClass: String(target?.className || '').slice(0, 160)
            };
        }
    };

    function notifyGesturePhase(phase, gestureId, ownerId, blocked) {
        const bridge = window.OsrsWikiBridge;
        if (!bridge) return;
        if (typeof bridge.setHorizontalScrollGesture === 'function') {
            bridge.setHorizontalScrollGesture(phase, gestureId, ownerId);
        } else if (typeof bridge.setHorizontalScroll === 'function') {
            bridge.setHorizontalScroll(blocked);
        }
    }

    function rememberTouchOwnership(sequence, owned) {
        touchOwnershipSnapshots.set(sequence, { sequence: sequence, owned: !!owned });
        while (touchOwnershipSnapshots.size > maxTouchOwnershipSnapshots) {
            touchOwnershipSnapshots.delete(touchOwnershipSnapshots.keys().next().value);
        }
    }

    function notifyTouchSequence(sequence) {
        const bridge = window.OsrsWikiBridge;
        if (bridge && typeof bridge.setArticleTouchSequence === 'function') {
            bridge.setArticleTouchSequence(sequence);
        }
    }

    function claimLocalSequence(owner) {
        sequenceAxisLock = 'local';
        isHorizontallyScrollable = true;
        latestTouchOwnedByLocalHorizontalContent = true;
        rememberTouchOwnership(activeTouchSequence, true);
        gestureSequence += 1;
        activeGestureId = 'article-local-' + gestureSequence;
        activeGestureOwner = owner
            ? (owner.getAttribute('aria-label') || owner.id || 'local-scroll-surface')
            : 'local-scroll-surface';
        notifyGesturePhase('begin', activeGestureId, activeGestureOwner, true);
        log('Claimed native gesture ' + activeGestureId + ' for ' + activeGestureOwner);
    }

    function beginNavigationSequence() {
        sequenceAxisLock = 'navigation';
        isHorizontallyScrollable = false;
        latestTouchOwnedByLocalHorizontalContent = false;
        rememberTouchOwnership(activeTouchSequence, false);
        gestureSequence += 1;
        activeGestureId = 'article-touch-' + gestureSequence;
        activeGestureOwner = 'article-navigation';
        notifyGesturePhase('begin', activeGestureId, activeGestureOwner, false);
    }

    document.addEventListener('touchstart', function(event) {
        // Additional fingers belong to the current primary touch even when that touch started on
        // ordinary article content. Never let a pinch advance the immutable sequence snapshot.
        if (activeTouchSequence !== null) return;
        const target = event.target;
        latestTouchSequence += 1;
        activeTouchSequence = latestTouchSequence;
        latestTouchOwnedByLocalHorizontalContent = false;
        activeTouchStartX = event.touches && event.touches[0] ? event.touches[0].clientX : 0;
        activeScrollOwner = null;
        sequenceAxisLock = null;
        startCanScrollPositive = false;
        startCanScrollNegative = false;
        // Force-disable app back swipe for GE chart interactions
        if (isInGEChart(target)) {
            geChartTouchActive = true;
            sequenceAxisLock = 'local';
            gestureSequence += 1;
            activeGestureId = 'article-local-' + gestureSequence;
            activeGestureOwner = 'price-chart';
            latestTouchOwnedByLocalHorizontalContent = true;
            rememberTouchOwnership(activeTouchSequence, true);
            notifyTouchSequence(activeTouchSequence);
            notifyGesturePhase('begin', activeGestureId, activeGestureOwner, true);
            log('GE chart touchstart: claimed gesture ' + activeGestureId);
            return; // don't run generic check to avoid flipping state
        }
        // Audio seek slider: claim unconditionally at touchstart, like GE charts.
        // The generic path would decline it (a range input has no scroll overflow),
        // letting a scrub drag read as an article back/contents swipe.
        if (isInArticleAudioSeek(target)) {
            notifyTouchSequence(activeTouchSequence);
            claimLocalSequence(target.closest('.osrs-article-audio-seek'));
            return;
        }
        log('Touch on: ' + target.tagName + ' ' + (target.className || '') + 
            ' at (' + Math.round(event.touches[0].clientX) + ', ' + Math.round(event.touches[0].clientY) + ')');
        
        const owner = scrollOwnerForTarget(target);
        activeScrollOwner = owner;
        const capacity = horizontalEdgeCapacity(owner);
        startCanScrollPositive = capacity.canPositive;
        startCanScrollNegative = capacity.canNegative;
        notifyTouchSequence(activeTouchSequence);
        if (owner && capacity.hasOverflow) {
            // A horizontally scrollable surface owns the whole pointer sequence,
            // including terminal edges. Back/contents swipes must start outside it.
            claimLocalSequence(owner);
        } else {
            beginNavigationSequence();
        }
    }, { passive: true });

    /**
     * Resets the scroll state when the touch gesture ends.
     */
    document.addEventListener('touchmove', function(event) {
        if (activeTouchSequence === null || geChartTouchActive) return;
        if (sequenceAxisLock !== null) return;
        const owner = activeScrollOwner;
        if (!owner || !event.touches || !event.touches.length) return;
        const deltaX = event.touches[0].clientX - activeTouchStartX;
        if (Math.abs(deltaX) < 10) return;
        claimLocalSequence(owner);
    }, { passive: true });

    function resetScrollState() {
        activeTouchSequence = null;
        activeScrollOwner = null;
        sequenceAxisLock = null;
        startCanScrollPositive = false;
        startCanScrollNegative = false;
        if (geChartTouchActive) {
            geChartTouchActive = false;
            log('GE chart touchend: ending ' + activeGestureId);
            notifyGesturePhase('end', activeGestureId, activeGestureOwner, false);
            isHorizontallyScrollable = false;
            activeGestureId = null;
            activeGestureOwner = null;
            return;
        }
        // Only send a reset call if the state was previously true, to avoid unnecessary calls.
        if (isHorizontallyScrollable) {
            log('Resetting scroll state to false');
            notifyGesturePhase('end', activeGestureId, activeGestureOwner, false);
            isHorizontallyScrollable = false;
            activeGestureId = null;
            activeGestureOwner = null;
        }
    }

    // Add listeners to reset the state when the touch gesture ends for any reason.
    document.addEventListener('touchend', function(event) {
        if (event.touches && event.touches.length > 0) return;
        resetScrollState();
    }, { passive: true });
    document.addEventListener('touchcancel', resetScrollState, { passive: true });
    document.addEventListener('click', function() {
        window.setTimeout(scheduleScrollAffordanceRefresh, 0);
    }, { capture: true, passive: true });
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', scheduleScrollAffordanceRefresh, { once: true });
    } else {
        scheduleScrollAffordanceRefresh();
    }
    new MutationObserver(scheduleScrollAffordanceRefresh).observe(document.documentElement, {
        childList: true,
        subtree: true
    });
    window.addEventListener('load', scheduleScrollAffordanceRefresh, { once: true });
    window.addEventListener('resize', scheduleScrollAffordanceRefresh, { passive: true });
    window.addEventListener('orientationchange', scheduleScrollAffordanceRefresh, { passive: true });

})();
