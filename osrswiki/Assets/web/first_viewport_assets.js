(function () {
    'use strict';
    if (window.__osrsFirstViewportAssets) {
        return;
    }
    window.__osrsFirstViewportAssets = true;
    window.__osrsFirstViewPainted = false;
    window.__osrsFirstViewportSettled = false;

    var reportedComplete = false;
    var reportedSettled = false;
    var paintedAtMs = null;

    function srcsetUrls(value) {
        if (!value) {
            return [];
        }
        var withoutData = String(value).replace(/data:[^\s,]+(?:\s+\d+(?:\.\d+)?[wx])?/gi, '');
        return withoutData.split(',').map(function (part) {
            var token = part.trim().split(/\s+/)[0];
            return token || '';
        }).filter(Boolean);
    }

    function elementUrls(el) {
        var urls = [];
        ['src', 'data-src', 'data-osrs-deferred-src', 'data-original', 'data-lazy-src'].forEach(function (name) {
            var value = el.getAttribute(name);
            if (value) {
                urls.push(value);
            }
        });
        ['srcset', 'data-srcset', 'data-osrs-deferred-srcset', 'data-lazy-srcset'].forEach(function (name) {
            urls = urls.concat(srcsetUrls(el.getAttribute(name)));
        });
        if (el.tagName === 'VIDEO') {
            var poster = el.getAttribute('poster');
            if (poster) {
                urls.push(poster);
            }
        }
        return urls;
    }

    // Painted completeness: one URL per element (currentSrc / src), not every srcset candidate.
    function chosenElementUrls(el) {
        var urls = [];
        if (el.tagName === 'IMG' && el.currentSrc) {
            urls.push(el.currentSrc);
            return urls;
        }
        var src = el.getAttribute('src') || el.getAttribute('data-src') ||
            el.getAttribute('data-original') || el.getAttribute('data-lazy-src');
        if (src) {
            urls.push(src);
            return urls;
        }
        if (el.tagName === 'VIDEO') {
            var poster = el.getAttribute('poster');
            if (poster) {
                urls.push(poster);
            }
            return urls;
        }
        var set = srcsetUrls(
            el.getAttribute('srcset') || el.getAttribute('data-srcset') ||
            el.getAttribute('data-osrs-deferred-srcset') || el.getAttribute('data-lazy-srcset')
        );
        if (set.length) {
            urls.push(set[0]);
        }
        return urls;
    }

    function narrowPaintedEnabled() {
        return window.__osrsNarrowFirstViewportPaintedSet !== false;
    }

    function unique(urls) {
        var seen = Object.create(null);
        var out = [];
        urls.forEach(function (url) {
            if (!url || seen[url]) {
                return;
            }
            seen[url] = true;
            out.push(url);
        });
        return out;
    }

    function addFrom(node, urls) {
        if (!node || !node.querySelectorAll) {
            return;
        }
        node.querySelectorAll('img, picture > source, video[poster]').forEach(function (el) {
            Array.prototype.push.apply(urls, elementUrls(el));
        });
    }

    function addFromChosen(node, urls) {
        if (!node || !node.querySelectorAll) {
            return;
        }
        node.querySelectorAll('img, picture > source, video[poster]').forEach(function (el) {
            Array.prototype.push.apply(urls, chosenElementUrls(el));
        });
    }

    function authoredDefaultIndex(root) {
        var infobox = root.querySelector(
            '.infobox-switch, .collapsible-primary-infobox, .switch-infobox'
        );
        if (!infobox) {
            return '0';
        }
        var buttonsContainer = infobox.querySelector('.infobox-buttons');
        var defaultIndex = buttonsContainer && buttonsContainer.getAttribute('data-default-version');
        if (defaultIndex) {
            return defaultIndex;
        }
        var selectedButton = infobox.querySelector('.button-selected');
        if (selectedButton && selectedButton.getAttribute('data-switch-index')) {
            return selectedButton.getAttribute('data-switch-index');
        }
        var firstButton = infobox.querySelector('[data-switch-index]');
        if (firstButton && firstButton.getAttribute('data-switch-index')) {
            return firstButton.getAttribute('data-switch-index');
        }
        return '0';
    }

    function collectDefaultSwitcherPane(root) {
        var urls = [];
        var infobox = root.querySelector(
            '.infobox-switch, .collapsible-primary-infobox, .switch-infobox, table.infobox, .infobox'
        );
        var index = authoredDefaultIndex(root);
        if (infobox) {
            addFromChosen(infobox, urls);
            var resourceClass = infobox.getAttribute('data-resource-class');
            if (resourceClass) {
                try {
                    var pool = root.querySelector(resourceClass);
                    if (pool) {
                        pool.querySelectorAll('[data-attr-index="' + index + '"]').forEach(function (node) {
                            addFromChosen(node, urls);
                        });
                    }
                } catch (ignore) {}
            }
        }
        root.querySelectorAll('[data-attr-param] [data-attr-index="' + index + '"]').forEach(function (node) {
            addFromChosen(node, urls);
        });
        var matchedItem = false;
        root.querySelectorAll('.switch-infobox .item').forEach(function (node) {
            var itemIndex = node.getAttribute('data-switch-index') || node.getAttribute('data-attr-index');
            if (itemIndex === index) {
                matchedItem = true;
                addFromChosen(node, urls);
            }
        });
        if (!matchedItem) {
            var firstItem = root.querySelector('.switch-infobox .item');
            if (firstItem) {
                addFromChosen(firstItem, urls);
            }
        }
        root.querySelectorAll('.infobox-bonuses-image.render-m, .infobox-bonuses-image.render-f').forEach(function (el) {
            Array.prototype.push.apply(urls, chosenElementUrls(el));
            addFromChosen(el, urls);
        });
        return urls;
    }

    function collectSwitcherSlot(root) {
        var urls = [];
        var infobox = root.querySelector(
            '.infobox-switch, .collapsible-primary-infobox, .switch-infobox, table.infobox, .infobox'
        );
        if (infobox) {
            addFrom(infobox, urls);
            var resourceClass = infobox.getAttribute('data-resource-class');
            if (resourceClass) {
                try {
                    addFrom(root.querySelector(resourceClass), urls);
                } catch (ignore) {}
            }
            addFrom(root.querySelector('.infobox-switch-resources'), urls);
            root.querySelectorAll('[class*="infobox-resources-"]').forEach(function (node) {
                addFrom(node, urls);
            });
            root.querySelectorAll('[data-attr-param] [data-attr-index]').forEach(function (node) {
                addFrom(node, urls);
            });
        }
        root.querySelectorAll('.switch-infobox .item').forEach(function (node) {
            addFrom(node, urls);
        });
        root.querySelectorAll('.infobox-bonuses-image.render-m, .infobox-bonuses-image.render-f').forEach(function (el) {
            Array.prototype.push.apply(urls, elementUrls(el));
            addFrom(el, urls);
        });
        return urls;
    }

    function collectLeadBeforeHeading(root) {
        var urls = [];
        var nodes = root.querySelectorAll('img, picture > source, video[poster], h2, .mw-heading');
        for (var i = 0; i < nodes.length; i++) {
            var node = nodes[i];
            if (node.matches && (node.matches('h2') || node.matches('.mw-heading'))) {
                break;
            }
            if (node.matches && (node.matches('img, picture > source, video[poster]'))) {
                Array.prototype.push.apply(urls, elementUrls(node));
            }
        }
        return urls;
    }

    function collectIntersecting() {
        var urls = [];
        var viewportHeight = window.innerHeight || 0;
        document.querySelectorAll('img, picture > source, video[poster]').forEach(function (el) {
            var rect = el.getBoundingClientRect();
            if (rect.bottom <= 0 || rect.top >= viewportHeight) {
                return;
            }
            if ((rect.width + rect.height) <= 0) {
                return;
            }
            Array.prototype.push.apply(urls, elementUrls(el));
        });
        return urls;
    }

    function collectIntersectingChosen() {
        var urls = [];
        var viewportHeight = window.innerHeight || 0;
        document.querySelectorAll('img, picture > source, video[poster]').forEach(function (el) {
            var rect = el.getBoundingClientRect();
            if (rect.bottom <= 0 || rect.top >= viewportHeight) {
                return;
            }
            if ((rect.width + rect.height) <= 0) {
                return;
            }
            Array.prototype.push.apply(urls, chosenElementUrls(el));
        });
        return urls;
    }

    function slotUrls() {
        return unique(collectSwitcherSlot(document).concat(collectLeadBeforeHeading(document)));
    }

    function paintedUrls() {
        if (!narrowPaintedEnabled()) {
            return unique(slotUrls().concat(collectIntersecting()));
        }
        return unique(collectDefaultSwitcherPane(document).concat(collectIntersectingChosen()));
    }

    function notify(urls) {
        if (!urls.length) {
            return;
        }
        try {
            if (window.OsrsWikiBridge && typeof window.OsrsWikiBridge.warmNearViewportAssets === 'function') {
                window.OsrsWikiBridge.warmNearViewportAssets(JSON.stringify(urls));
            }
        } catch (ignore) {}
        try {
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.osrsLiveAssetWarm) {
                window.webkit.messageHandlers.osrsLiveAssetWarm.postMessage({ urls: urls });
            }
        } catch (ignore) {}
    }

    function firstViewPayload() {
        var payload = { complete: true };
        if (typeof window.__osrsArticleLoadGeneration === 'number') {
            payload.generation = window.__osrsArticleLoadGeneration;
        }
        return payload;
    }

    function dispatchFirstViewEvent() {
        try {
            window.dispatchEvent(new CustomEvent('osrs-first-view-complete'));
        } catch (ignore) {}
        try {
            if (window.RenderTimeline && typeof window.RenderTimeline.log === 'function') {
                var generation = window.__osrsArticleLoadGeneration;
                window.RenderTimeline.log(
                    typeof generation === 'number'
                        ? 'Event: FirstViewPainted:' + generation
                        : 'Event: FirstViewPainted'
                );
            }
        } catch (ignore) {}
    }

    function dispatchViewportSettledEvent() {
        try {
            window.dispatchEvent(new CustomEvent('osrs-first-viewport-settled'));
        } catch (ignore) {}
        try {
            if (window.RenderTimeline && typeof window.RenderTimeline.log === 'function') {
                var generation = window.__osrsArticleLoadGeneration;
                window.RenderTimeline.log(
                    typeof generation === 'number'
                        ? 'Event: FirstViewportSettled:' + generation
                        : 'Event: FirstViewportSettled'
                );
            }
        } catch (ignore) {}
    }

    function postComplete() {
        dispatchFirstViewEvent();
        var payload = firstViewPayload();
        try {
            if (window.OsrsWikiBridge && typeof window.OsrsWikiBridge.firstViewComplete === 'function') {
                window.OsrsWikiBridge.firstViewComplete();
            }
        } catch (ignore) {}
        try {
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.osrsFirstViewComplete) {
                window.webkit.messageHandlers.osrsFirstViewComplete.postMessage(payload);
            }
        } catch (ignore) {}
        console.log('osrsFirstViewComplete');
    }

    function stabilitySnapshot() {
        var s = window.__osrsLayoutStability || {};
        return {
            maxTopDelta: typeof s.maxTopDelta === 'number' ? s.maxTopDelta : null,
            maxHeightDelta: typeof s.maxHeightDelta === 'number' ? s.maxHeightDelta : null
        };
    }

    function settledPayload() {
        var snap = stabilitySnapshot();
        var payload = {
            complete: true,
            maxTopDelta: snap.maxTopDelta,
            maxHeightDelta: snap.maxHeightDelta
        };
        if (typeof window.__osrsArticleLoadGeneration === 'number') {
            payload.generation = window.__osrsArticleLoadGeneration;
        }
        if (paintedAtMs != null) {
            payload.tPaintedMs = paintedAtMs;
        }
        payload.tSettledMs = performance.now();
        return payload;
    }

    function dispatchSettledEvent() {
        try {
            window.dispatchEvent(new CustomEvent('osrs-first-viewport-settled'));
        } catch (ignore) {}
        try {
            if (window.RenderTimeline && typeof window.RenderTimeline.log === 'function') {
                var generation = window.__osrsArticleLoadGeneration;
                window.RenderTimeline.log(
                    typeof generation === 'number'
                        ? 'Event: FirstViewportSettled:' + generation
                        : 'Event: FirstViewportSettled'
                );
            }
        } catch (ignore) {}
    }

    function postSettled() {
        dispatchSettledEvent();
        var payload = settledPayload();
        try {
            if (window.OsrsWikiBridge && typeof window.OsrsWikiBridge.firstViewportSettled === 'function') {
                window.OsrsWikiBridge.firstViewportSettled(JSON.stringify(payload));
            }
        } catch (ignore) {}
        try {
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.osrsFirstViewportSettled) {
                window.webkit.messageHandlers.osrsFirstViewportSettled.postMessage(payload);
            }
        } catch (ignore) {}
        console.log('osrsFirstViewportSettled');
    }

    function reportSettled() {
        window.__osrsFirstViewportSettled = true;
        if (reportedSettled) {
            return;
        }
        reportedSettled = true;
        postSettled();
    }

    function waitForStabilitySampleThenSettle() {
        // Phase A: report-only — emit after sample finishes (or 2s fallback), attach deltas.
        // Do not gate reveal. Thresholds stay open questions from the spec.
        var tries = 0;
        function tick() {
            var s = window.__osrsLayoutStability;
            if (s && Array.isArray(s.samples) && s.samples.length >= 32) {
                reportSettled();
                return;
            }
            tries += 1;
            if (tries > 120) { // ~2s at 60fps + rAF slack
                reportSettled();
                return;
            }
            requestAnimationFrame(tick);
        }
        requestAnimationFrame(tick);
    }

    function reportComplete() {
        window.__osrsFirstViewPainted = true;
        paintedAtMs = performance.now();
        if (reportedComplete) {
            return;
        }
        reportedComplete = true;
        postComplete();
        waitForStabilitySampleThenSettle();
    }

    function reportViewportSettled() {
        dispatchViewportSettledEvent();
    }

    function elementHasDecodedUrl(el, url) {
        if (!el || el.tagName !== 'IMG' || !url) {
            return false;
        }
        if (!(el.complete && el.naturalWidth > 0)) {
            return false;
        }
        var candidates = [el.currentSrc, el.src];
        ['src', 'data-src', 'data-osrs-deferred-src', 'data-original', 'data-lazy-src'].forEach(function (name) {
            candidates.push(el.getAttribute(name));
        });
        for (var i = 0; i < candidates.length; i++) {
            if (candidates[i] && candidates[i] === url) {
                return true;
            }
        }
        return false;
    }

    function domImageAlreadyDecoded(url) {
        if (!url) {
            return true;
        }
        var nodes = document.querySelectorAll('img');
        for (var i = 0; i < nodes.length; i++) {
            if (elementHasDecodedUrl(nodes[i], url)) {
                return true;
            }
        }
        return false;
    }

    function decodeUrl(url) {
        if (domImageAlreadyDecoded(url)) {
            return Promise.resolve();
        }
        return new Promise(function (resolve) {
            var img = new Image();
            var settled = false;
            function finish() {
                if (settled) {
                    return;
                }
                settled = true;
                resolve();
            }
            img.onload = finish;
            img.onerror = finish;
            img.src = url;
            if (typeof img.decode === 'function') {
                img.decode().then(finish, finish);
            }
        });
    }

    function watchComplete() {
        var urls = paintedUrls();
        var timeout = setTimeout(reportComplete, 15000);
        var wait = urls.length ? Promise.all(urls.map(decodeUrl)) : Promise.resolve();
        wait.then(function () {
            clearTimeout(timeout);
            reportComplete();
            reportViewportSettled();
        });
    }

    window.osrsCollectFirstViewportUrls = function () {
        return paintedUrls();
    };

    window.osrsNotifyFirstViewComplete = function () {
        window.__osrsFirstViewPainted = true;
        postComplete();
    };

    window.osrsNotifyFirstViewportSettled = reportSettled;

    window.osrsWatchFirstViewComplete = watchComplete;

    function sampleLayoutStability() {
        var target = document.querySelector(
            '.infobox-switch, .collapsible-primary-infobox, table.infobox, .infobox'
        );
        window.__osrsLayoutStability = window.__osrsLayoutStability || {
            samples: [],
            maxTopDelta: 0,
            maxHeightDelta: 0
        };
        if (!target || typeof target.getBoundingClientRect !== 'function') {
            return;
        }
        var samples = [];
        var frames = 0;
        function tick() {
            var rect = target.getBoundingClientRect();
            samples.push({
                t: performance.now(),
                top: rect.top,
                height: rect.height,
                width: rect.width
            });
            frames += 1;
            if (frames < 32) {
                requestAnimationFrame(tick);
                return;
            }
            var tops = samples.map(function (sample) { return sample.top; });
            var heights = samples.map(function (sample) { return sample.height; });
            window.__osrsLayoutStability = {
                samples: samples,
                maxTopDelta: Math.max.apply(null, tops) - Math.min.apply(null, tops),
                maxHeightDelta: Math.max.apply(null, heights) - Math.min.apply(null, heights)
            };
        }
        requestAnimationFrame(tick);
    }

    function start() {
        notify(paintedUrls());
        watchComplete();
        sampleLayoutStability();
    }

    // Article HTML is already in the document when this classic script runs
    // (it sits after the body content). readyState is still "loading" until
    // later parser-blocking tags finish — do not wait for DCL when body exists.
    if (document.body) {
        start();
    } else {
        document.addEventListener('DOMContentLoaded', start);
    }
})();
