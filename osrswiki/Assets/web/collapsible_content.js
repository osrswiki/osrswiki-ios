/*
 * OSRS Wiki collapsible-content transformer.
 *
 * This is the canonical Android/iOS implementation. Decisions are based on
 * authored DOM semantics and geometry, never page titles.
 */
(function() {
    'use strict';

    const mapIdentityByElement = new WeakMap();
    const claimedMapIdentities = new Set();
    const observedMaps = new WeakSet();
    let disclosureSequence = 0;
    let mapRemeasureScheduled = false;

    function logTimeline(message) {
        if (window.RenderTimeline && typeof window.RenderTimeline.log === 'function') {
            window.RenderTimeline.log(message);
        }
    }

    function normalizeText(text) {
        return (text || '').replace(/\s+/g, ' ').trim();
    }

    function bridgeCall(method) {
        const bridge = window.OsrsWikiBridge;
        if (!bridge || typeof bridge[method] !== 'function') return;
        const args = Array.prototype.slice.call(arguments, 1);
        bridge[method].apply(bridge, args);
    }

    function restoreDeferredImages(root) {
        if (!root || !root.querySelectorAll) return 0;
        const deferredImages = root.querySelectorAll('img[data-osrs-deferred-src]');
        deferredImages.forEach(function(image) {
            [
                ['data-osrs-deferred-src', 'src'],
                ['data-osrs-deferred-srcset', 'srcset'],
                ['data-osrs-deferred-sizes', 'sizes']
            ].forEach(function(attributes) {
                const value = image.getAttribute(attributes[0]);
                if (!value) return;
                image.setAttribute(attributes[1], value);
                image.removeAttribute(attributes[0]);
            });
            image.classList.remove('osrs-deferred-table-image');
        });
        return deferredImages.length;
    }

    function ensureMapIdentity(mapPlaceholder, index) {
        const assignedIdentity = mapIdentityByElement.get(mapPlaceholder);
        if (assignedIdentity) return assignedIdentity;

        const preferredIdentity = mapPlaceholder.dataset.osrsNativeMapId ||
            mapPlaceholder.id || ('map-placeholder-' + index);
        let mapId = preferredIdentity;
        let suffix = Math.max(0, index);
        while (claimedMapIdentities.has(mapId)) {
            mapId = preferredIdentity + '-' + suffix;
            suffix += 1;
        }

        claimedMapIdentities.add(mapId);
        mapIdentityByElement.set(mapPlaceholder, mapId);
        mapPlaceholder.id = mapId;
        mapPlaceholder.dataset.osrsNativeMapId = mapId;
        const accessibleSurface = mapPlaceholder.querySelector('a, img') || mapPlaceholder;
        accessibleSurface.setAttribute('aria-label', 'Interactive OSRS article map');
        return mapId;
    }

    function authoredMapId(mapPlaceholder) {
        const raw = mapPlaceholder.dataset.mapid ||
            mapPlaceholder.getAttribute('data-mapid');
        if (raw === undefined || raw === null || raw === '') {
            return null;
        }
        const parsed = parseInt(raw, 10);
        return Number.isFinite(parsed) ? parsed : null;
    }

    function assignMapIdentities() {
        document.querySelectorAll('.mw-kartographer-map').forEach(ensureMapIdentity);
    }

    function isNearViewport(rect) {
        return rect.bottom >= -256 && rect.top <= window.innerHeight + 256;
    }

    function observeMapVisibility(mapPlaceholder, mapId) {
        if (observedMaps.has(mapPlaceholder) || typeof IntersectionObserver === 'undefined') return;
        const observer = new IntersectionObserver(function(entries) {
            entries.forEach(function(entry) {
                const container = mapPlaceholder.closest('.collapsible-container');
                bridgeCall(
                    'onMapViewportVisibilityChanged',
                    mapId,
                    entry.isIntersecting && !(container && container.classList.contains('collapsed'))
                );
            });
        }, { rootMargin: '256px 0px' });
        observer.observe(mapPlaceholder);
        observedMaps.add(mapPlaceholder);
    }

    function applyAuthoredMapAspect(mapPlaceholder) {
        const authoredWidth = parseFloat(mapPlaceholder.getAttribute('data-width') || mapPlaceholder.dataset.width || '300');
        const authoredHeight = parseFloat(mapPlaceholder.getAttribute('data-height') || mapPlaceholder.dataset.height || '300');
        if (!(authoredWidth > 0 && authoredHeight > 0)) return;
        const ratio = authoredHeight / authoredWidth;
        mapPlaceholder.style.setProperty('--osrs-map-width', authoredWidth + 'px');
        mapPlaceholder.style.setProperty('--osrs-map-aspect', authoredWidth + ' / ' + authoredHeight);
        mapPlaceholder.style.setProperty('display', 'block', 'important');
        mapPlaceholder.style.setProperty('width', '100%', 'important');
        mapPlaceholder.style.setProperty('max-width', '100%', 'important');
        mapPlaceholder.style.setProperty('box-sizing', 'border-box', 'important');
        const parentWidth = (mapPlaceholder.parentElement && mapPlaceholder.parentElement.clientWidth) || 0;
        const boxWidth = mapPlaceholder.getBoundingClientRect().width || parentWidth || authoredWidth;
        const height = Math.max(160, Math.round(boxWidth * ratio));
        mapPlaceholder.style.setProperty('height', height + 'px', 'important');
        mapPlaceholder.style.setProperty('min-height', height + 'px', 'important');
        const cell = mapPlaceholder.closest('td, th');
        if (cell) {
            cell.style.setProperty('height', height + 'px', 'important');
            cell.style.setProperty('min-height', height + 'px', 'important');
        }
    }

    function sendMapMeasurement(mapPlaceholder, index) {
        applyAuthoredMapAspect(mapPlaceholder);
        const mapId = ensureMapIdentity(mapPlaceholder, index);
        const rect = mapPlaceholder.getBoundingClientRect();
        if (rect.width <= 0 || rect.height <= 0) {
            scheduleMapRemeasure();
            return;
        }
        if (rect.height + 1 < rect.width * 0.85) {
            scheduleMapRemeasure();
        }

        const rectJson = JSON.stringify({
            y: rect.top + window.scrollY,
            x: rect.left,
            width: rect.width,
            height: rect.height
        });
        const mapDataJson = JSON.stringify({
            lat: mapPlaceholder.dataset.lat,
            lon: mapPlaceholder.dataset.lon,
            zoom: mapPlaceholder.dataset.zoom,
            plane: mapPlaceholder.dataset.plane,
            mapId: authoredMapId(mapPlaceholder),
            initiallyVisible: isNearViewport(rect)
        });
        bridgeCall('onMapPlaceholderMeasured', mapId, rectJson, mapDataJson);
        observeMapVisibility(mapPlaceholder, mapId);
    }

    function measureAndPreloadMaps() {
        if (!window.OsrsWikiBridge) return;
        document.querySelectorAll('.mw-kartographer-map').forEach(function(mapPlaceholder, index) {
            ensureMapIdentity(mapPlaceholder, index);
            const container = mapPlaceholder.closest('.collapsible-container');
            if (container && container.classList.contains('collapsed')) return;
            sendMapMeasurement(mapPlaceholder, index);
        });
    }
    window.measureAndPreloadMaps = measureAndPreloadMaps;

    function scheduleMapRemeasure() {
        if (mapRemeasureScheduled) return;
        mapRemeasureScheduled = true;
        window.setTimeout(function() {
            mapRemeasureScheduled = false;
            measureAndPreloadMaps();
        }, 80);
    }
    window.scheduleMapRemeasure = scheduleMapRemeasure;

    function updateHeaderText(container, titleWrapper, captionText) {
        const isCollapsed = container.classList.contains('collapsed');
        titleWrapper.replaceChildren();

        const label = document.createElement('span');
        label.className = 'collapsible-label';
        label.textContent = captionText;
        titleWrapper.appendChild(label);

        container.setAttribute('aria-expanded', String(!isCollapsed));
        const header = container.querySelector(':scope > .collapsible-header');
        if (header) header.setAttribute('aria-expanded', String(!isCollapsed));
    }

    function syncDisclosureAccessibility(container, content) {
        const isCollapsed = container.classList.contains('collapsed');
        const header = container.querySelector(':scope > .collapsible-header');

        if (isCollapsed) {
            if (content.contains(document.activeElement) && header) {
                try {
                    header.focus({ preventScroll: true });
                } catch (_) {
                    header.focus();
                }
            }
            content.setAttribute('aria-hidden', 'true');
            content.setAttribute('inert', '');
            content.inert = true;
        } else {
            content.removeAttribute('aria-hidden');
            content.removeAttribute('inert');
            content.inert = false;
        }
    }

    function toggleCollapsible(container, titleWrapper, captionText, scrollToTop) {
        const content = container.querySelector(':scope > .collapsible-content');
        if (!content) return;

        const isOpening = container.classList.contains('collapsed');
        const mapPlaceholders = Array.from(content.querySelectorAll('.mw-kartographer-map'));
        mapPlaceholders.forEach(function(mapPlaceholder) {
            ensureMapIdentity(
                mapPlaceholder,
                Array.prototype.indexOf.call(document.querySelectorAll('.mw-kartographer-map'), mapPlaceholder)
            );
        });

        if (isOpening) {
            const restoredCount = restoreDeferredImages(content);
            if (restoredCount > 0) {
                logTimeline('Event: DeferredImagesRestored count=' + restoredCount);
            }
            container.classList.remove('collapsed');
            content.style.height = 'auto';
        } else {
            container.classList.add('collapsed');
            content.style.height = '0px';
            if (scrollToTop) {
                window.setTimeout(function() {
                    container.scrollIntoView({ behavior: 'smooth', block: 'start' });
                }, 100);
            }
        }

        updateHeaderText(container, titleWrapper, captionText);
        syncDisclosureAccessibility(container, content);
        mapPlaceholders.forEach(function(mapPlaceholder) {
            bridgeCall('onCollapsibleToggled', mapPlaceholder.dataset.osrsNativeMapId, isOpening);
        });
        if (typeof window.refreshHorizontalScrollAffordances === 'function') {
            requestAnimationFrame(window.refreshHorizontalScrollAffordances);
        }
        scheduleMapRemeasure();
    }

    function ensureDisclosureIds(header, content) {
        disclosureSequence += 1;
        const base = 'osrs-disclosure-' + disclosureSequence;
        header.id = header.id || base + '-header';
        content.id = content.id || base + '-content';
        header.setAttribute('aria-controls', content.id);
        content.setAttribute('aria-labelledby', header.id);
    }

    function setupCollapsible(header, container, titleWrapper, captionText) {
        const content = container.querySelector(':scope > .collapsible-content');
        if (!content || container.dataset.osrsDisclosureBound === 'true') return;
        container.dataset.osrsDisclosureBound = 'true';
        if (!container.classList.contains('collapsed')) restoreDeferredImages(content);

        header.setAttribute('role', 'button');
        header.setAttribute('tabindex', '0');
        ensureDisclosureIds(header, content);

        const closeFooter = document.createElement('div');
        closeFooter.className = 'collapsible-close-footer';
        const closeButton = document.createElement('div');
        closeButton.className = 'collapsible-close-button';
        closeButton.setAttribute('role', 'button');
        closeButton.setAttribute('tabindex', '0');
        closeButton.setAttribute('aria-label', 'Collapse ' + captionText);

        const footerTitleWrapper = document.createElement('div');
        footerTitleWrapper.className = 'title-wrapper';
        footerTitleWrapper.textContent = 'Close';
        const icon = document.createElement('span');
        icon.className = 'icon';
        closeButton.appendChild(footerTitleWrapper);
        closeButton.appendChild(icon);
        closeFooter.appendChild(closeButton);
        content.appendChild(closeFooter);
        absorbDisclosureChildren(content);

        function activateHeader(event) {
            if (event && event.type === 'keydown' && event.key !== 'Enter' && event.key !== ' ') return;
            if (event && event.type === 'keydown') event.preventDefault();
            toggleCollapsible(container, titleWrapper, captionText, false);
        }
        header.addEventListener('click', activateHeader);
        header.addEventListener('keydown', activateHeader);

        function activateClose(event) {
            if (event && event.type === 'keydown' && event.key !== 'Enter' && event.key !== ' ') return;
            if (event) {
                event.preventDefault();
                event.stopPropagation();
            }
            if (!container.classList.contains('collapsed')) {
                toggleCollapsible(container, titleWrapper, captionText, true);
            }
        }
        closeButton.addEventListener('click', activateClose);
        closeButton.addEventListener('keydown', activateClose);
        syncDisclosureAccessibility(container, content);
    }

    function shouldIgnoreCaptionTextElement(element) {
        if (!element || !element.matches) return false;
        if (element.hidden || element.getAttribute('aria-hidden') === 'true') return true;
        if (element.matches(
            '.infobox-buttons, .infobox-buttons *, ' +
            '.switch-infobox-triggers, .switch-infobox-triggers *, ' +
            '.loading-button, .loading-button *, ' +
            '.infobox-switch-resources, .infobox-switch-resources *, ' +
            '[class*="infobox-resources-"], [class*="infobox-resources-"] *, ' +
            '.rsw-synced-switch, .rsw-synced-switch *, ' +
            '.rsw-synced-switch-item:not(.showing), .rsw-synced-switch-item:not(.showing) *, ' +
            '.item:not(.showing), .item:not(.showing) *, ' +
            '.gender-render-hidden, .gender-render-hidden *'
        )) return true;

        const style = (element.getAttribute('style') || '').toLowerCase();
        return /display\s*:\s*none/.test(style) || /visibility\s*:\s*hidden/.test(style);
    }

    function visibleCaptionText(element) {
        if (!element || shouldIgnoreCaptionTextElement(element)) return '';
        const parts = [];
        const walker = document.createTreeWalker(element, NodeFilter.SHOW_TEXT, {
            acceptNode: function(node) {
                if (!normalizeText(node.nodeValue)) return NodeFilter.FILTER_REJECT;
                let cursor = node.parentElement;
                while (cursor && cursor !== element) {
                    if (shouldIgnoreCaptionTextElement(cursor)) return NodeFilter.FILTER_REJECT;
                    cursor = cursor.parentElement;
                }
                return NodeFilter.FILTER_ACCEPT;
            }
        });
        let node;
        while ((node = walker.nextNode())) parts.push(node.nodeValue);
        return normalizeText(parts.join(' '));
    }

    function firstText(root, selector) {
        const element = root ? root.querySelector(selector) : null;
        return visibleCaptionText(element);
    }

    function directCaption(table) {
        if (!table) return null;
        try {
            return table.querySelector(':scope > caption');
        } catch (_) {
            return table.firstElementChild && table.firstElementChild.tagName === 'CAPTION'
                ? table.firstElementChild
                : null;
        }
    }

    function firstHeaderCells(table) {
        return Array.from(table.querySelectorAll('tr:first-child th'))
            .map(function(cell) { return visibleCaptionText(cell); })
            .filter(Boolean)
            .slice(0, 3)
            .join(' / ');
    }

    function findContextHeading(element) {
        let cursor = element;
        while (cursor && cursor !== document.body) {
            let previous = cursor.previousElementSibling;
            while (previous) {
                const heading = previous.matches && previous.matches('h1, h2, h3, h4, h5, h6')
                    ? previous
                    : previous.querySelector && previous.querySelector(
                        '.mw-heading h1, .mw-heading h2, .mw-heading h3, .mw-heading h4, ' +
                        '.mw-heading h5, .mw-heading h6, h1, h2, h3, h4, h5, h6'
                    );
                const headingText = heading ? visibleCaptionText(heading) : '';
                if (headingText) return headingText;
                previous = previous.previousElementSibling;
            }
            cursor = cursor.parentElement;
        }
        return '';
    }

    function isSwitchInfoboxElement(element) {
        return !!(element && element.matches && element.querySelector && (
            element.matches('table.infobox-switch, .infobox-switch, .switch-infobox, .multi-infobox') ||
            element.querySelector('table.infobox-switch, .infobox-switch, .switch-infobox')
        ));
    }

    function switchInfoboxSemanticTitle(element) {
        if (!isSwitchInfoboxElement(element)) return '';
        return firstText(element, '.infobox-header[data-attr-param="name"]') ||
            firstText(element, '.infobox-header') ||
            firstText(element, 'tr:first-child th');
    }

    function nearestSwitchInfoboxElement(element) {
        return element && element.closest
            ? element.closest('table.infobox-switch, .infobox-switch, .switch-infobox, .multi-infobox')
            : null;
    }

    function deriveCaptionText(kind, defaultTitle, elementToWrap, table) {
        if (table && table.querySelector('.mw-kartographer-map')) {
            return findContextHeading(elementToWrap) ||
                visibleCaptionText(directCaption(table)) ||
                firstHeaderCells(table) ||
                'Map table';
        }
        if (kind === 'infobox') {
            if (table.classList.contains('infobox-bonuses')) {
                return findContextHeading(elementToWrap) ||
                    firstText(table, '.infobox-subheader') ||
                    'Equipment bonuses';
            }
            return switchInfoboxSemanticTitle(table) ||
                switchInfoboxSemanticTitle(elementToWrap) ||
                switchInfoboxSemanticTitle(nearestSwitchInfoboxElement(table)) ||
                visibleCaptionText(directCaption(table)) ||
                firstText(table, '.infobox-header') ||
                firstText(table, 'th') ||
                findContextHeading(elementToWrap) ||
                defaultTitle;
        }
        if (kind === 'navbox') {
            return firstText(table, '.navbox-title-name') ||
                firstText(table, '.navbox-title') ||
                'Navigation';
        }
        if (kind === 'questdetails') {
            return findContextHeading(elementToWrap) ||
                visibleCaptionText(directCaption(table)) ||
                'Quest details';
        }
        return switchInfoboxSemanticTitle(table) ||
            switchInfoboxSemanticTitle(elementToWrap) ||
            switchInfoboxSemanticTitle(nearestSwitchInfoboxElement(table)) ||
            visibleCaptionText(directCaption(table)) ||
            firstHeaderCells(table) ||
            findContextHeading(elementToWrap) ||
            firstText(table, 'th') ||
            defaultTitle;
    }

    function recipeRoleForTable(table) {
        const semanticText = normalizeText([
            visibleCaptionText(directCaption(table)),
            firstHeaderCells(table)
        ].join(' ')).toLowerCase();
        if (/\b(materials?|ingredients?|items?\s+required)\b/.test(semanticText)) {
            return 'recipe-materials';
        }
        if (/\b(requirements?|prerequisites?)\b/.test(semanticText) ||
            /\b(skills?|quests?)\b.{0,32}\b(level|required)\b/.test(semanticText)) {
            return 'recipe-requirements';
        }
        return 'recipe-other';
    }

    function recipeDescriptor(table, index, labelCounts) {
        const role = recipeRoleForTable(table);
        const caption = visibleCaptionText(directCaption(table));
        const headers = firstHeaderCells(table);
        let baseLabel = role === 'recipe-requirements'
            ? 'Requirements'
            : (role === 'recipe-materials' ? 'Materials' : (caption || headers || 'Recipe details ' + (index + 1)));
        const normalizedLabel = baseLabel.toLowerCase();
        const occurrence = (labelCounts.get(normalizedLabel) || 0) + 1;
        labelCounts.set(normalizedLabel, occurrence);
        if (occurrence > 1) baseLabel += ' (' + occurrence + ')';
        return { role: role, label: baseLabel, caption: caption };
    }

    function hasExplicitFullWidth(table) {
        const style = (table.getAttribute('style') || '').toLowerCase();
        return /(?:^|;)\s*(?:min-)?width\s*:\s*100%/.test(style) || table.style.width === '100%';
    }

    function isIntrinsicWidthTable(table) {
        if (!table.classList.contains('wikitable') ||
            table.classList.contains('sortable') ||
            table.classList.contains('filterable') ||
            table.matches('.infobox, .navbox') ||
            table.querySelector('.mw-kartographer-map, input, select, button, textarea') ||
            hasExplicitFullWidth(table)) return false;

        const style = (table.getAttribute('style') || '').toLowerCase();
        const floats = /float\s*:\s*(?:left|right)/.test(style);
        const rows = table.querySelectorAll('tr').length;
        const maxCells = Array.from(table.querySelectorAll('tr')).reduce(function(max, row) {
            return Math.max(max, Array.from(row.children).reduce(function(total, cell) {
                return total + Math.max(1, Number(cell.colSpan) || 1);
            }, 0));
        }, 0);
        return floats || (rows <= 8 && maxCells <= 4);
    }

    function hideRepresentedCaption(table, representedCaption) {
        const caption = directCaption(table);
        if (!caption || !representedCaption) return;
        if (normalizeText(visibleCaptionText(caption)).toLowerCase() !== normalizeText(representedCaption).toLowerCase()) return;
        caption.hidden = true;
        caption.setAttribute('aria-hidden', 'true');
        caption.dataset.osrsCaptionHiddenByDisclosure = 'true';
    }

    function shouldStartCollapsed(isPrimary) {
        const globalPreference = typeof window.OSRS_TABLE_COLLAPSED !== 'undefined'
            ? window.OSRS_TABLE_COLLAPSED
            : true;
        return !!globalPreference && !isPrimary;
    }

    function appendDisclosureBody(content) {
        const body = document.createElement('div');
        body.className = 'osrs-disclosure-body osrs-disclosure-inset-target';
        body.dataset.osrsDisclosureBody = '1';
        content.appendChild(body);
        return body;
    }

    function absorbDisclosureChildren(content) {
        if (!content) return;
        const body = content.querySelector(':scope > .osrs-disclosure-body');
        if (!body) return;
        Array.from(content.children).forEach(function(child) {
            if (child === body || child.classList.contains('collapsible-close-footer')) return;
            body.appendChild(child);
        });
    }

    function applyDisclosureInnerInset(content) {
        /* CSS owns the inset via .osrs-disclosure-body margins. Keep this
           hook so later layout passes can re-assert the inner wrapper. */
        if (!content) return;
        const body = content.querySelector(':scope > .osrs-disclosure-body');
        if (body) body.classList.add('osrs-disclosure-inset-target');
    }

    function scheduleDisclosureInnerInsets() {
        const run = function() {
            document.querySelectorAll('.collapsible-content').forEach(applyDisclosureInnerInset);
        };
        run();
        if (typeof requestAnimationFrame === 'function') {
            requestAnimationFrame(run);
        }
        [0, 50, 250, 800, 1600].forEach(function(ms) {
            setTimeout(run, ms);
        });
    }

    function transformElement(options) {
        const kind = options.kind;
        const table = options.table;
        const elementToWrap = options.elementToWrap || table;
        if (!table || !elementToWrap || !elementToWrap.parentNode || elementToWrap.closest('.collapsible-container')) {
            return null;
        }

        const isPrimary = !!options.isPrimary;
        if (isPrimary) {
            table.classList.add('main-infobox');
            table.style.marginTop = '0px';
        }
        const captionText = options.captionText ||
            deriveCaptionText(kind, options.defaultTitle || 'Table', elementToWrap, table);
        const startCollapsed = shouldStartCollapsed(isPrimary);
        const container = document.createElement('div');
        const classes = ['collapsible-container'];
        if (startCollapsed) classes.push('collapsed');
        else classes.push('primary-collapsible');

        if (kind === 'recipe') {
            classes.push('collapsible-wikitable', 'collapsible-intrinsic-table', 'collapsible-recipe-table');
            table.classList.add('osrs-intrinsic-recipe-table');
        } else if (kind === 'wikitable') {
            classes.push('collapsible-wikitable');
            if (table.querySelector('.mw-kartographer-map')) {
                classes.push('collapsible-map-table');
                table.classList.add('osrs-map-table');
            } else if (isIntrinsicWidthTable(table)) {
                classes.push('collapsible-intrinsic-table');
            }
        } else if (kind === 'questdetails') {
            classes.push('collapsible-questdetails');
        } else if (kind === 'explicit') {
            classes.push('collapsible-explicit-mw-collapsible');
        } else if (kind === 'navbox') {
            classes.push('collapsible-navbox');
        } else if (kind === 'infobox') {
            classes.push('collapsible-infobox');
            if (isPrimary) classes.push('collapsible-primary-infobox');
            if (table.classList.contains('infobox-bonuses')) classes.push('collapsible-bonuses-infobox');
        }

        // Recipe units are stacked full-width cards. Wiki float classes must not shrink
        // their headers, padding, or close footers to the table's intrinsic width.
        if (kind !== 'recipe') {
            if (elementToWrap.matches('[class*="floatright"], [class*="-right"]') ||
                elementToWrap.classList.contains('archivelist') ||
                elementToWrap.classList.contains('shortcut') ||
                elementToWrap.classList.contains('mw-halign-right') ||
                elementToWrap.classList.contains('multi-infobox')) {
                classes.push('collapsible-float-right');
            } else if (elementToWrap.matches('[class*="floatleft"], [class*="-left"]') ||
                elementToWrap.classList.contains('mw-halign-left')) {
                classes.push('collapsible-float-left');
            }
        }

        container.className = classes.join(' ');
        container.dataset.osrsDisclosureKind = kind;
        container.dataset.collapseLabelKind = normalizeText(captionText) === (options.defaultTitle || 'Table')
            ? 'generic'
            : 'semantic';
        if (options.tableRole) {
            container.dataset.osrsTableRole = options.tableRole;
            table.dataset.osrsTableRole = options.tableRole;
        }

        const header = document.createElement('div');
        header.className = 'collapsible-header';
        const titleWrapper = document.createElement('div');
        titleWrapper.className = 'title-wrapper';
        const icon = document.createElement('span');
        icon.className = 'icon';
        icon.setAttribute('aria-hidden', 'true');
        header.appendChild(titleWrapper);
        header.appendChild(icon);

        hideRepresentedCaption(table, options.representedCaption || visibleCaptionText(directCaption(table)));
        elementToWrap.parentNode.insertBefore(container, elementToWrap);
        container.appendChild(header);
        const content = document.createElement('div');
        content.className = 'collapsible-content';
        appendDisclosureBody(content).appendChild(elementToWrap);
        container.appendChild(content);
        updateHeaderText(container, titleWrapper, captionText);
        setupCollapsible(header, container, titleWrapper, captionText);
        return container;
    }

    function directRecipeTables(wrapper) {
        return Array.from(wrapper.children).filter(function(child) {
            return child.matches && child.matches('table:not([role="presentation"]):not(.navbox)');
        });
    }

    function transformRecipeTables() {
        document.querySelectorAll('.recipe-table').forEach(function(wrapper) {
            wrapper.classList.add('osrs-recipe-unit', 'osrs-intrinsic-table');
            const labelCounts = new Map();
            wrapper.querySelectorAll(':scope > .collapsible-recipe-table .collapsible-label').forEach(function(label) {
                const normalized = normalizeText(label.textContent).replace(/\s+\(\d+\)$/, '').toLowerCase();
                labelCounts.set(normalized, (labelCounts.get(normalized) || 0) + 1);
            });
            directRecipeTables(wrapper).forEach(function(table, index) {
                const descriptor = recipeDescriptor(table, index, labelCounts);
                table.classList.add('wikitable');
                table.dataset.osrsRecipeIndex = String(index);
                transformElement({
                    kind: 'recipe',
                    defaultTitle: 'Recipe details',
                    table: table,
                    elementToWrap: table,
                    captionText: descriptor.label,
                    representedCaption: descriptor.caption,
                    tableRole: descriptor.role
                });
            });
            wrapper.dataset.osrsRecipeTransformed = 'true';
        });
    }

    function topLevelPrimaryInfobox() {
        return Array.from(document.querySelectorAll('table.infobox')).find(function(table) {
            return !table.closest('.recipe-table') &&
                !table.classList.contains('infobox-bonuses') &&
                !(table.parentElement && table.parentElement.closest('table'));
        }) || null;
    }

    function shouldTransformExplicitCollapsibleTable(table) {
        if (!table || !table.matches('table.mw-collapsible') || table.closest('.collapsible-container')) return false;
        return !table.matches(
            'table.infobox, table.wikitable, table.navbox, table.messagebox, table.ambox, ' +
            'table.mbox, table.notebox, table.gallery, table[role="presentation"]'
        );
    }

    function shouldTransformQuestDetailsTable(table) {
        return !!(table && table.matches('table.questdetails') &&
            !table.closest('.collapsible-container') &&
            !(table.parentElement && table.parentElement.closest('table')));
    }

    function transformSections() {
        document.querySelectorAll('div.mw-collapsible').forEach(function(collapsibleDiv) {
            if (collapsibleDiv.closest('.collapsible-container')) return;
            const trigger = collapsibleDiv.querySelector('.collapsed-sec');
            const originalContent = collapsibleDiv.querySelector('.mw-collapsible-content');
            if (!trigger || !originalContent) return;

            const globalPreference = typeof window.OSRS_TABLE_COLLAPSED !== 'undefined'
                ? window.OSRS_TABLE_COLLAPSED
                : null;
            const startCollapsed = globalPreference !== null
                ? globalPreference
                : collapsibleDiv.classList.contains('mw-collapsed');
            const container = document.createElement('div');
            container.className = startCollapsed ? 'collapsible-container collapsed' : 'collapsible-container';
            container.dataset.collapseLabelKind = 'semantic';
            container.dataset.osrsDisclosureKind = 'section';
            const header = document.createElement('div');
            header.className = 'collapsible-header';
            const titleWrapper = document.createElement('div');
            titleWrapper.className = 'title-wrapper';
            const icon = document.createElement('span');
            icon.className = 'icon';
            icon.setAttribute('aria-hidden', 'true');
            header.appendChild(titleWrapper);
            header.appendChild(icon);

            const previous = collapsibleDiv.previousElementSibling;
            const captionText = previous && /^H[1-6]$/.test(previous.tagName)
                ? normalizeText(previous.textContent)
                : 'Section';
            const content = document.createElement('div');
            content.className = 'collapsible-content';
            const body = appendDisclosureBody(content);
            while (originalContent.firstChild) body.appendChild(originalContent.firstChild);
            container.appendChild(header);
            container.appendChild(content);
            collapsibleDiv.parentNode.insertBefore(container, collapsibleDiv);
            collapsibleDiv.remove();
            updateHeaderText(container, titleWrapper, captionText);
            setupCollapsible(header, container, titleWrapper, captionText);
        });
    }

    function collectCollapseMetrics() {
        const controls = Array.from(document.querySelectorAll('.collapsible-container')).map(function(container) {
            return {
                label: firstText(container, '.collapsible-label'),
                labelKind: container.dataset.collapseLabelKind || '',
                disclosureKind: container.dataset.osrsDisclosureKind || '',
                tableRole: container.dataset.osrsTableRole || '',
                collapsed: container.classList.contains('collapsed')
            };
        });
        return {
            collapseControls: controls.length,
            collapsedControls: controls.filter(function(control) { return control.collapsed; }).length,
            genericCollapseLabels: controls.filter(function(control) { return control.labelKind === 'generic'; }).length,
            recipeControls: controls.filter(function(control) { return control.disclosureKind === 'recipe'; }).length,
            controls: controls
        };
    }

    function bindMapLifecycle() {
        if (window.__osrsMapLifecycleBound) return;
        window.__osrsMapLifecycleBound = true;
        window.addEventListener('resize', scheduleMapRemeasure, { passive: true });
        window.addEventListener('orientationchange', scheduleMapRemeasure, { passive: true });
        window.addEventListener('pageshow', scheduleMapRemeasure, { passive: true });
        document.addEventListener('scroll', scheduleMapRemeasure, { capture: true, passive: true });
        if (document.fonts && document.fonts.ready) {
            document.fonts.ready.then(scheduleMapRemeasure).catch(function() {});
        }
        if (window.ResizeObserver && document.body) {
            const resizeObserver = new ResizeObserver(scheduleMapRemeasure);
            resizeObserver.observe(document.body);
            document.querySelectorAll('.mw-kartographer-map').forEach(function(element) {
                resizeObserver.observe(element);
            });
            window.osrsMapResizeObserver = resizeObserver;
        }
    }

    function initialize() {
        if (!document.body) return;
        const startedAt = window.performance && performance.now ? performance.now() : Date.now();

        transformRecipeTables();
        const primaryInfobox = topLevelPrimaryInfobox();
        document.querySelectorAll('table.infobox').forEach(function(table) {
            if (table.closest('.recipe-table, .collapsible-container')) return;
            const switcherContainer = table.closest('.infobox-switch');
            transformElement({
                kind: 'infobox',
                defaultTitle: 'Infobox',
                table: table,
                elementToWrap: switcherContainer || table,
                isPrimary: table === primaryInfobox
            });
        });
        document.querySelectorAll('table.navbox').forEach(function(table) {
            transformElement({ kind: 'navbox', defaultTitle: 'Navigation', table: table });
        });
        document.querySelectorAll('table.questdetails').forEach(function(table) {
            if (shouldTransformQuestDetailsTable(table)) {
                transformElement({ kind: 'questdetails', defaultTitle: 'Quest details', table: table });
            }
        });
        document.querySelectorAll('table.mw-collapsible').forEach(function(table) {
            if (shouldTransformExplicitCollapsibleTable(table)) {
                transformElement({ kind: 'explicit', defaultTitle: 'Table', table: table });
            }
        });
        document.querySelectorAll('table.wikitable').forEach(function(table) {
            if (!table.closest('.recipe-table, .collapsible-container') &&
                !table.matches('.navbox, .questdetails')) {
                transformElement({ kind: 'wikitable', defaultTitle: 'Table', table: table });
            }
        });
        transformSections();

        if (typeof initializeInfoboxSwitcher === 'function') initializeInfoboxSwitcher();
        document.querySelectorAll('.collapsible-content').forEach(absorbDisclosureChildren);
        scheduleDisclosureInnerInsets();
        if (typeof window.OSRSApplyArticlePolish === 'function') {
            window.OSRSApplyArticlePolish();
        }
        document.body.classList.add('js-transforms-complete');

        const finishedAt = window.performance && performance.now ? performance.now() : Date.now();
        logTimeline(
            'Event: CollapsibleTransformsComplete durationMs=' + Math.round(finishedAt - startedAt) +
            ' containers=' + document.querySelectorAll('.collapsible-container').length +
            ' recipeControls=' + document.querySelectorAll('.collapsible-recipe-table').length
        );
        window.OSRSCollapseMetrics = collectCollapseMetrics();
        const generation = window.__osrsArticleLoadGeneration;
        logTimeline(typeof generation === 'number'
            ? 'Event: StylingScriptsComplete:' + generation
            : 'Event: StylingScriptsComplete');

        assignMapIdentities();
        measureAndPreloadMaps();
        scheduleMapRemeasure();
        setTimeout(measureAndPreloadMaps, 150);
        setTimeout(measureAndPreloadMaps, 450);
        bindMapLifecycle();
    }

    window.OSRSInitializeCollapsibleContent = initialize;
    if (document.body) {
        initialize();
    } else if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', initialize, { once: true });
    } else {
        initialize();
    }
})();
