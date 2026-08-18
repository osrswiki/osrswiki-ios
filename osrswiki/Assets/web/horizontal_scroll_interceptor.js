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
    const standaloneScrollSurfaceSelector = [
        '.mw-parser-output > table.wikitable',
        '.mw-parser-output > .wikitable',
        '.mw-parser-output > table.sortable',
        '.mw-parser-output > table.filterable',
        '.mw-parser-output > table.item-drops',
        '.mw-parser-output > table.navbox',
        '.mwe-math-element',
        'math.mwe-math-element'
    ].join(',');
    
    // Helper function to log to Android
    function log(message) {
        if (window.OsrsWikiBridge && typeof window.OsrsWikiBridge.log === 'function') {
            window.OsrsWikiBridge.log('[HorizontalScroll] ' + message);
        }
    }

    function getScrollSurfaceForTable(table) {
        if (!table || !table.closest) {
            return null;
        }
        if (table.matches('.main-infobox, .osrs-map-table') ||
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
            !surface.closest('.collapsible-primary-infobox, .osrs-recipe-unit')) {
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

    function isInProtectedNonlocalTableRole(target) {
        return !!(target && target.closest && target.closest(
            '.collapsible-primary-infobox, .collapsible-map-table, .osrs-recipe-unit'
        ));
    }

    function scrollOwnerForTarget(target) {
        if (isInProtectedNonlocalTableRole(target)) return null;
        let current = target;
        while (current && current !== document.body) {
            if (current.classList && current.classList.contains('osrs-local-scroll-surface') &&
                current.scrollWidth > current.clientWidth + 2) {
                return current;
            }
            current = current.parentElement;
        }
        // The disclosure is one interaction region. A horizontal drag that begins on its
        // header/padding must not become article navigation when the disclosed content owns a
        // real local horizontal viewport (for example Combat stats). Do not apply this to
        // primary infoboxes, recipes, or map tables because those are deliberately nonlocal.
        const disclosure = target?.closest?.('.collapsible-container');
        const disclosureSurface = disclosure?.querySelector?.('.osrs-local-scroll-surface');
        if (disclosureSurface &&
            disclosureSurface.scrollWidth > disclosureSurface.clientWidth + 2) {
            return disclosureSurface;
        }
        return null;
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
            const isLocalOwner = !!(owner || mapPlaceholder || chart);
            return {
                isLocalOwner: isLocalOwner,
                ownerId: chart
                    ? 'price-chart'
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

    document.addEventListener('touchstart', function(event) {
        // Additional fingers belong to the current primary touch even when that touch started on
        // ordinary article content. Never let a pinch advance the immutable sequence snapshot.
        if (activeTouchSequence !== null) return;
        const target = event.target;
        latestTouchSequence += 1;
        activeTouchSequence = latestTouchSequence;
        latestTouchOwnedByLocalHorizontalContent = false;
        // Force-disable app back swipe for GE chart interactions
        if (isInGEChart(target)) {
            geChartTouchActive = true;
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
        log('Touch on: ' + target.tagName + ' ' + (target.className || '') + 
            ' at (' + Math.round(event.touches[0].clientX) + ', ' + Math.round(event.touches[0].clientY) + ')');
        
        // Check if the touch target is inside a scrollable container.
        const owner = scrollOwnerForTarget(target);
        isHorizontallyScrollable = !!owner;
        latestTouchOwnedByLocalHorizontalContent = isHorizontallyScrollable;
        rememberTouchOwnership(activeTouchSequence, isHorizontallyScrollable);
        notifyTouchSequence(activeTouchSequence);
        log('Scrollable: ' + isHorizontallyScrollable);
        
        if (isHorizontallyScrollable) {
            gestureSequence += 1;
            activeGestureId = 'article-local-' + gestureSequence;
            activeGestureOwner = owner?.getAttribute('aria-label') || owner?.id || 'local-scroll-surface';
            notifyGesturePhase('begin', activeGestureId, activeGestureOwner, true);
            log('Claimed native gesture ' + activeGestureId + ' for ' + activeGestureOwner);
        }
    }, { passive: true });

    /**
     * Resets the scroll state when the touch gesture ends.
     */
    function resetScrollState() {
        activeTouchSequence = null;
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
