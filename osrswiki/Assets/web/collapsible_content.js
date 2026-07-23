/*
 * OSRSWiki Collapsible Content Transformer
 */
(function() {
    'use strict';

    const tryInitializeSwitcher = () => {
        if (typeof initializeInfoboxSwitcher === 'function') {
            initializeInfoboxSwitcher();
        }
    };

    let mapRemeasureScheduled = false;

    function sendMapMeasurement(mapPlaceholder, index) {
        const mapId = mapPlaceholder.id || mapPlaceholder.dataset.osrsNativeMapId || ('map-placeholder-' + index);
        mapPlaceholder.id = mapId;
        mapPlaceholder.dataset.osrsNativeMapId = mapId;

        const rect = mapPlaceholder.getBoundingClientRect();
        if (rect.width <= 0 || rect.height <= 0) return;

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
            plane: mapPlaceholder.dataset.plane
        });
        window.OsrsWikiBridge.onMapPlaceholderMeasured(mapId, rectJson, mapDataJson);
    }

    function measureAndPreloadMaps() {
        if (!window.OsrsWikiBridge) return;
        const mapPlaceholders = document.querySelectorAll('.mw-kartographer-map');
        mapPlaceholders.forEach((mapPlaceholder, index) => {
            const container = mapPlaceholder.closest('.collapsible-container');
            const content = container ? container.querySelector('.collapsible-content') : null;
            if (container && content && container.classList.contains('collapsed')) {
                const originalHeight = content.style.height;
                const originalVisibility = content.style.visibility;
                content.style.height = 'auto';
                content.style.visibility = 'hidden';
                requestAnimationFrame(() => {
                    sendMapMeasurement(mapPlaceholder, index);
                    content.style.height = originalHeight;
                    content.style.visibility = originalVisibility;
                });
            } else {
                sendMapMeasurement(mapPlaceholder, index);
            }
        });
    }
    window.measureAndPreloadMaps = measureAndPreloadMaps;

    function scheduleMapRemeasure() {
        if (mapRemeasureScheduled) return;
        mapRemeasureScheduled = true;
        requestAnimationFrame(() => {
            setTimeout(() => {
                mapRemeasureScheduled = false;
                measureAndPreloadMaps();
            }, 80);
        });
    }
    window.scheduleMapRemeasure = scheduleMapRemeasure;

    function updateHeaderText(container, titleWrapper, captionText) {
        var isCollapsed = container.classList.contains('collapsed');
        var stateText = isCollapsed ? ': Tap to expand' : ': Tap to collapse';
        titleWrapper.innerHTML = captionText + '<span style="font-weight: normal;">' + stateText + '</span>';
    }

    function toggleCollapsible(container, titleWrapper, captionText, scrollToTop) {
        var content = container.querySelector('.collapsible-content');
        if (!content) return;
        
        var isCurrentlyCollapsed = container.classList.contains('collapsed');
        var mapPlaceholder = content.querySelector('.mw-kartographer-map');
        var mapId = mapPlaceholder ? mapPlaceholder.id : null;
        
        if (isCurrentlyCollapsed) {
            container.classList.remove('collapsed');
            content.style.height = 'auto';
        } else {
            container.classList.add('collapsed');
            content.style.height = '0px';
            
            // Scroll to top of collapsed container if requested (from footer)
            if (scrollToTop) {
                setTimeout(function() {
                    container.scrollIntoView({ 
                        behavior: 'smooth', 
                        block: 'start' 
                    });
                }, 100); // Small delay to let collapse animation start
            }
        }
        
        updateHeaderText(container, titleWrapper, captionText);

        if (window.OsrsWikiBridge && mapId) {
            window.OsrsWikiBridge.onCollapsibleToggled(mapId, isCurrentlyCollapsed);
        }
        scheduleMapRemeasure();
    }

    function normalizeText(text) {
        return (text || '').replace(/\s+/g, ' ').trim();
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
        )) {
            return true;
        }

        var style = (element.getAttribute('style') || '').toLowerCase();
        return /display\s*:\s*none/.test(style) || /visibility\s*:\s*hidden/.test(style);
    }

    function visibleCaptionText(element) {
        if (!element || shouldIgnoreCaptionTextElement(element)) return '';

        var parts = [];
        var walker = document.createTreeWalker(element, NodeFilter.SHOW_TEXT, {
            acceptNode: function(node) {
                if (!normalizeText(node.nodeValue)) {
                    return NodeFilter.FILTER_REJECT;
                }

                var cursor = node.parentElement;
                while (cursor && cursor !== element) {
                    if (shouldIgnoreCaptionTextElement(cursor)) {
                        return NodeFilter.FILTER_REJECT;
                    }
                    cursor = cursor.parentElement;
                }

                return NodeFilter.FILTER_ACCEPT;
            }
        });

        var node;
        while ((node = walker.nextNode())) {
            parts.push(node.nodeValue);
        }

        return normalizeText(parts.join(' '));
    }

    function firstText(root, selector) {
        var element = root ? root.querySelector(selector) : null;
        return visibleCaptionText(element);
    }

    function findContextHeading(element) {
        var cursor = element;
        while (cursor && cursor !== document.body) {
            var previous = cursor.previousElementSibling;
            while (previous) {
                var heading = previous.matches && previous.matches('h1, h2, h3, h4, h5, h6')
                    ? previous
                    : previous.querySelector && previous.querySelector('.mw-heading h1, .mw-heading h2, .mw-heading h3, .mw-heading h4, .mw-heading h5, .mw-heading h6, h1, h2, h3, h4, h5, h6');
                var headingText = heading ? visibleCaptionText(heading) : '';
                if (headingText) return headingText;
                previous = previous.previousElementSibling;
            }
            cursor = cursor.parentElement;
        }
        return '';
    }

    function firstHeaderCells(table) {
        return Array.from(table.querySelectorAll('tr:first-child th'))
            .map(function(cell) { return visibleCaptionText(cell); })
            .filter(Boolean)
            .slice(0, 3)
            .join(' / ');
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
            firstText(element, 'tr:first-child th') ||
            '';
    }

    function nearestSwitchInfoboxElement(element) {
        if (!element || !element.closest) return null;
        return element.closest('table.infobox-switch, .infobox-switch, .switch-infobox, .multi-infobox');
    }

    function normalizedPageTitle() {
        var heading = document.querySelector('#firstHeading, h1.firstHeading, .mw-page-title, h1');
        var title = heading ? heading.textContent : (document.title || '');
        return normalizeText(title).replace(/_/g, ' ').toLowerCase();
    }

    function isStandaloneLevelUpTablePage() {
        return normalizedPageTitle().indexOf('/level up table') !== -1;
    }

    function isSkillLandingPage() {
        if (isStandaloneLevelUpTablePage()) {
            return false;
        }

        var skills = [
            'attack', 'strength', 'defence', 'ranged', 'prayer', 'magic',
            'runecraft', 'construction', 'hitpoints', 'agility', 'herblore',
            'thieving', 'crafting', 'fletching', 'slayer', 'hunter',
            'mining', 'smithing', 'fishing', 'cooking', 'firemaking',
            'woodcutting', 'farming'
        ];
        return skills.indexOf(normalizedPageTitle()) !== -1;
    }

    function deriveCaptionText(selector, defaultTitle, elementToWrap, elementForTitle) {
        if (selector === 'table.infobox') {
            if (elementForTitle.classList.contains('infobox-bonuses')) {
                return findContextHeading(elementToWrap) ||
                    firstText(elementForTitle, '.infobox-subheader') ||
                    'Equipment bonuses';
            }
            return switchInfoboxSemanticTitle(elementForTitle) ||
                switchInfoboxSemanticTitle(elementToWrap) ||
                switchInfoboxSemanticTitle(nearestSwitchInfoboxElement(elementForTitle)) ||
                switchInfoboxSemanticTitle(nearestSwitchInfoboxElement(elementToWrap)) ||
                firstText(elementForTitle, 'caption') ||
                firstText(elementForTitle, '.infobox-header') ||
                firstText(elementForTitle, 'th') ||
                findContextHeading(elementToWrap) ||
                defaultTitle;
        }

        if (selector === 'table.navbox') {
            return firstText(elementForTitle, '.navbox-title-name') ||
                firstText(elementForTitle, '.navbox-title') ||
                'Navigation';
        }

        if (selector === 'table.questdetails') {
            return findContextHeading(elementToWrap) ||
                firstText(elementForTitle, 'caption') ||
                'Quest details';
        }

        if (selector === 'table.mw-collapsible') {
            return switchInfoboxSemanticTitle(elementForTitle) ||
                switchInfoboxSemanticTitle(elementToWrap) ||
                switchInfoboxSemanticTitle(nearestSwitchInfoboxElement(elementForTitle)) ||
                switchInfoboxSemanticTitle(nearestSwitchInfoboxElement(elementToWrap)) ||
                firstText(elementForTitle, 'caption') ||
                firstHeaderCells(elementForTitle) ||
                findContextHeading(elementToWrap) ||
                firstText(elementForTitle, 'th') ||
                defaultTitle;
        }

        return switchInfoboxSemanticTitle(elementForTitle) ||
            switchInfoboxSemanticTitle(elementToWrap) ||
            switchInfoboxSemanticTitle(nearestSwitchInfoboxElement(elementForTitle)) ||
            switchInfoboxSemanticTitle(nearestSwitchInfoboxElement(elementToWrap)) ||
            firstText(elementForTitle, 'caption') ||
            firstHeaderCells(elementForTitle) ||
            findContextHeading(elementToWrap) ||
            firstText(elementForTitle, 'th') ||
            defaultTitle;
    }

    function shouldTreatAsPrimaryTable(table, index) {
        if (table.classList.contains('mmg-table')) {
            return true;
        }

        if (index !== 0) {
            return false;
        }

        if (table.closest('.navbox') || table.classList.contains('navbox')) {
            return false;
        }

        if (isSkillLandingPage()) {
            return false;
        }

        return true;
    }

    function isAlwaysExpandedContent(selector, index, elementForTitle) {
        return (selector === 'table.infobox' && index === 0) ||
            (selector === 'table.wikitable' && shouldTreatAsPrimaryTable(elementForTitle, index));
    }

    function hasExplicitFullWidth(table) {
        var inlineStyle = (table.getAttribute('style') || '').toLowerCase();
        return inlineStyle.indexOf('width:100%') !== -1 ||
            inlineStyle.indexOf('width: 100%') !== -1 ||
            inlineStyle.indexOf('min-width') !== -1 ||
            table.style.width === '100%';
    }

    function isIntrinsicWidthTable(table) {
        if (!table.classList.contains('wikitable')) return false;
        if (table.classList.contains('sortable') ||
            table.classList.contains('mmg-table') ||
            table.classList.contains('infobox') ||
            table.classList.contains('navbox') ||
            table.classList.contains('tbrl-tasks') ||
            hasExplicitFullWidth(table)) {
            return false;
        }

        var style = (table.getAttribute('style') || '').toLowerCase();
        var floats = style.indexOf('float:right') !== -1 ||
            style.indexOf('float: right') !== -1 ||
            style.indexOf('float:left') !== -1 ||
            style.indexOf('float: left') !== -1;
        var rows = table.querySelectorAll('tr').length;
        var maxCells = Array.from(table.querySelectorAll('tr')).reduce(function(max, row) {
            return Math.max(max, row.children.length);
        }, 0);

        return floats || (rows <= 8 && maxCells <= 4);
    }

    function shouldCollapseInitially(selector, index, elementForTitle) {
        const globalPreference = (typeof window.OSRS_TABLE_COLLAPSED !== 'undefined') ?
            window.OSRS_TABLE_COLLAPSED : true;

        if (isAlwaysExpandedContent(selector, index, elementForTitle)) {
            return false;
        }

        return globalPreference;
    }

    function setupCollapsible(header, container, titleWrapper, captionText) {
        var content = container.querySelector('.collapsible-content');
        if (!content) return;
        
        // Create close footer that mirrors the header design
        var closeFooter = document.createElement('div');
        closeFooter.className = 'collapsible-close-footer';
        var closeButton = document.createElement('div');
        closeButton.className = 'collapsible-close-button';
        closeButton.setAttribute('role', 'button');
        closeButton.setAttribute('tabindex', '0');
        closeButton.setAttribute('aria-label', 'Collapse ' + captionText);
        
        var footerTitleWrapper = document.createElement('div');
        footerTitleWrapper.className = 'title-wrapper';
        footerTitleWrapper.textContent = 'Close';
        
        var icon = document.createElement('span');
        icon.className = 'icon';
        
        closeButton.appendChild(footerTitleWrapper);
        closeButton.appendChild(icon);
        closeFooter.appendChild(closeButton);
        content.appendChild(closeFooter);
        
        // Header click handler (no scroll)
        header.addEventListener('click', function() {
            toggleCollapsible(container, titleWrapper, captionText, false);
        });
        
        // Close footer click handler (scroll to top)
        closeButton.addEventListener('click', function(e) {
            e.stopPropagation(); // Prevent bubbling to container
            // Only collapse if currently expanded
            if (!container.classList.contains('collapsed')) {
                toggleCollapsible(container, titleWrapper, captionText, true);
            }
        });
        
        // Keyboard support for close footer (scroll to top)
        closeButton.addEventListener('keydown', function(e) {
            if (e.key === 'Enter' || e.key === ' ') {
                e.preventDefault();
                e.stopPropagation();
                if (!container.classList.contains('collapsed')) {
                    toggleCollapsible(container, titleWrapper, captionText, true);
                }
            }
        });
    }

    function transformElement(selector, defaultTitle, index, elementToWrap, elementForTitle) {
        if (elementToWrap.closest('.collapsible-container')) {
            return;
        }



        if (selector === 'table.infobox' && index === 0) {
            elementForTitle.classList.add('main-infobox');
            elementForTitle.style.marginTop = '0px';
        }

        const shouldStartCollapsed = shouldCollapseInitially(selector, index, elementForTitle);
        var container = document.createElement('div');
        var containerClasses = ['collapsible-container'];
        if (shouldStartCollapsed) {
            containerClasses.push('collapsed');
        }
        if (!shouldStartCollapsed) {
            containerClasses.push('primary-collapsible');
        }
        if (selector === 'table.wikitable') {
            containerClasses.push('collapsible-wikitable');
            if (isIntrinsicWidthTable(elementForTitle)) {
                containerClasses.push('collapsible-intrinsic-table');
            }
        } else if (selector === 'table.questdetails') {
            containerClasses.push('collapsible-questdetails');
        } else if (selector === 'table.mw-collapsible') {
            containerClasses.push('collapsible-explicit-mw-collapsible');
        } else if (selector === 'table.navbox') {
            containerClasses.push('collapsible-navbox');
        } else if (selector === 'table.infobox') {
            containerClasses.push('collapsible-infobox');
            if (index === 0) {
                containerClasses.push('collapsible-primary-infobox');
            }
            if (elementForTitle.classList.contains('infobox-bonuses')) {
                containerClasses.push('collapsible-bonuses-infobox');
            }
        }
        if (elementToWrap.matches('[class*="floatright"], [class*="-right"]') ||
            elementToWrap.classList.contains('archivelist') ||
            elementToWrap.classList.contains('shortcut') ||
            elementToWrap.classList.contains('mw-halign-right') ||
            elementToWrap.classList.contains('multi-infobox')) {
            containerClasses.push('collapsible-float-right');
        } else if (elementToWrap.matches('[class*="floatleft"], [class*="-left"]') ||
            elementToWrap.classList.contains('mw-halign-left')) {
            containerClasses.push('collapsible-float-left');
        }
        container.className = containerClasses.join(' ');

        var header = document.createElement('div');
        header.className = 'collapsible-header';
        var titleWrapper = document.createElement('div');
        titleWrapper.className = 'title-wrapper';
        var captionText = deriveCaptionText(selector, defaultTitle, elementToWrap, elementForTitle);
        // Hide original captions if they exist
        if (selector !== 'table.infobox') {
            const caption = elementForTitle.querySelector('caption');
            if (caption) {
                caption.style.display = 'none';
            }
        }

        var icon = document.createElement('span');
        icon.className = 'icon';
        header.appendChild(titleWrapper);
        header.appendChild(icon);
        elementToWrap.parentNode.insertBefore(container, elementToWrap);
        container.appendChild(header);
        var content = document.createElement('div');
        content.className = 'collapsible-content';
        content.appendChild(elementToWrap);
        container.appendChild(content);
        updateHeaderText(container, titleWrapper, captionText);
        setupCollapsible(header, container, titleWrapper, captionText);
    }

    function transformSections() {
        document.querySelectorAll('div.mw-collapsible').forEach(function(collapsibleDiv, index) {
            // Skip if already transformed
            if (collapsibleDiv.closest('.collapsible-container')) {
                return;
            }

            const triggerSpan = collapsibleDiv.querySelector('.collapsed-sec');
            if (!triggerSpan) {
                return;
            }

            // Find the content div
            const originalContent = collapsibleDiv.querySelector('.mw-collapsible-content');
            if (!originalContent) {
                return;
            }

            // Determine initial state - check global preference first, then fallback to mw-collapsed class
            const globalPreference = (typeof window.OSRS_TABLE_COLLAPSED !== 'undefined') ? window.OSRS_TABLE_COLLAPSED : null;
            const shouldStartCollapsed = (globalPreference !== null) ? 
                globalPreference : 
                collapsibleDiv.classList.contains('mw-collapsed');

            // Create container structure
            var container = document.createElement('div');
            container.className = shouldStartCollapsed ? 'collapsible-container collapsed' : 'collapsible-container';
            var header = document.createElement('div');
            header.className = 'collapsible-header';
            var titleWrapper = document.createElement('div');
            titleWrapper.className = 'title-wrapper';
            
            // Try to determine a good title
            var captionText = 'Section';
            // Look for preceding heading or other context clues
            const prevHeading = collapsibleDiv.previousElementSibling;
            if (prevHeading && (prevHeading.tagName.match(/^H[1-6]$/))) {
                captionText = prevHeading.textContent.trim();
            }

            var icon = document.createElement('span');
            icon.className = 'icon';
            header.appendChild(titleWrapper);
            header.appendChild(icon);

            // Create content container and move content
            var content = document.createElement('div');
            content.className = 'collapsible-content';
            while (originalContent.firstChild) {
                content.appendChild(originalContent.firstChild);
            }

            // Assemble the new structure
            container.appendChild(header);
            container.appendChild(content);

            // Replace the original element
            collapsibleDiv.parentNode.insertBefore(container, collapsibleDiv);
            collapsibleDiv.parentNode.removeChild(collapsibleDiv);

            // Set up header text and behavior
            updateHeaderText(container, titleWrapper, captionText);
            setupCollapsible(header, container, titleWrapper, captionText);
        });
    }

    function shouldTransformExplicitCollapsibleTable(table) {
        if (!table || !table.matches || !table.matches('table.mw-collapsible')) {
            return false;
        }
        if (table.closest('.collapsible-container')) {
            return false;
        }
        return !table.matches(
            'table.infobox, table.wikitable, table.navbox, ' +
            'table.messagebox, table.ambox, table.mbox, table.notebox, ' +
            'table.gallery, table[role="presentation"]'
        );
    }

    function shouldTransformQuestDetailsTable(table) {
        if (!table || !table.matches || !table.matches('table.questdetails')) {
            return false;
        }
        if (table.closest('.collapsible-container')) {
            return false;
        }
        if (table.parentElement && table.parentElement.closest('table')) {
            return false;
        }
        return true;
    }

    function preloadCollapsibleImages() {
        const imageUrlsToPreload = new Set();
        const containers = document.querySelectorAll('.collapsible-container');
        containers.forEach(function(container) {
            const images = container.querySelectorAll('img');
            images.forEach(function(img) {
                const src = img.getAttribute('src');
                if (src) { imageUrlsToPreload.add(src); }
                const srcset = img.getAttribute('srcset');
                if (srcset) {
                    const sources = srcset.split(',').map(s => s.trim().split(/\s+/)[0]);
                    sources.forEach(sourceUrl => imageUrlsToPreload.add(sourceUrl));
                }
            });
        });
        imageUrlsToPreload.forEach(function(url) {
            const preloader = new Image();
            preloader.src = url;
            preloader.decode().catch(() => {});
        });
    }

    function initialize() {
        preloadCollapsibleImages();

        document.querySelectorAll('table.infobox').forEach((table, i) => {
            const switcherContainer = table.closest('.infobox-switch');
            const elementToTransform = switcherContainer || table;
            transformElement('table.infobox', 'Infobox', i, elementToTransform, table);
        });

        document.querySelectorAll('table.wikitable').forEach((el, i) => transformElement('table.wikitable', 'Table', i, el, el));
        document.querySelectorAll('table.navbox').forEach((el, i) => transformElement('table.navbox', 'Navigation', i, el, el));
        document.querySelectorAll('table.questdetails').forEach((el, i) => {
            if (shouldTransformQuestDetailsTable(el)) {
                transformElement('table.questdetails', 'Quest details', i, el, el);
            }
        });
        document.querySelectorAll('table.mw-collapsible').forEach((el, i) => {
            if (shouldTransformExplicitCollapsibleTable(el)) {
                transformElement('table.mw-collapsible', 'Table', i, el, el);
            }
        });
        
        transformSections();
        
        tryInitializeSwitcher();

        // Add CSS class to signal transforms are complete
        document.body.classList.add('js-transforms-complete');
        
        // CRITICAL FIX: Initialize MapLibre widgets after collapsible setup
        measureAndPreloadMaps();
        scheduleMapRemeasure();

        window.addEventListener('resize', scheduleMapRemeasure);
        window.addEventListener('orientationchange', scheduleMapRemeasure);
        window.addEventListener('pageshow', scheduleMapRemeasure);
        if (document.fonts && document.fonts.ready) {
            document.fonts.ready.then(scheduleMapRemeasure).catch(() => {});
        }
        document.querySelectorAll('img').forEach(function(img) {
            if (!img.complete) {
                img.addEventListener('load', scheduleMapRemeasure, { once: true });
                img.addEventListener('error', scheduleMapRemeasure, { once: true });
            }
        });
        if (window.ResizeObserver) {
            const resizeObserver = new ResizeObserver(scheduleMapRemeasure);
            resizeObserver.observe(document.body);
            document.querySelectorAll('.mw-kartographer-map').forEach(el => resizeObserver.observe(el));
            window.osrsMapResizeObserver = resizeObserver;
        }
        
        // Signal to native that styling and transforms are complete,
        // so the page can be revealed without FOUC.
        if (window.RenderTimeline && typeof window.RenderTimeline.log === 'function') {
            window.RenderTimeline.log('Event: StylingScriptsComplete:' + window.__osrsArticleLoadGeneration);
        }
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', initialize);
    } else {
        initialize();
    }
})();
