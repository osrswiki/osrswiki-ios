(function () {
    'use strict';
    if (window.__osrsLiveArticleAssetWarm) {
        return;
    }
    window.__osrsLiveArticleAssetWarm = true;

    var notified = Object.create(null);
    var pending = [];
    var flushScheduled = false;

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

    function notify(urls) {
        var fresh = [];
        urls.forEach(function (url) {
            if (!url || notified[url]) {
                return;
            }
            notified[url] = true;
            fresh.push(url);
        });
        if (!fresh.length) {
            return;
        }
        pending = pending.concat(fresh);
        if (flushScheduled) {
            return;
        }
        flushScheduled = true;
        setTimeout(flush, 16);
    }

    function flush() {
        flushScheduled = false;
        if (!pending.length) {
            return;
        }
        var urls = pending;
        pending = [];
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

    function observe(el) {
        if (!el || el.__osrsLiveAssetWarmObserved) {
            return;
        }
        el.__osrsLiveAssetWarmObserved = true;
        if (typeof IntersectionObserver === 'undefined') {
            notify(elementUrls(el));
            return;
        }
        if (!window.__osrsLiveAssetWarmObserver) {
            window.__osrsLiveAssetWarmObserver = new IntersectionObserver(function (entries) {
                entries.forEach(function (entry) {
                    if (!entry.isIntersecting) {
                        return;
                    }
                    notify(elementUrls(entry.target));
                    window.__osrsLiveAssetWarmObserver.unobserve(entry.target);
                });
            }, { root: null, rootMargin: '100% 0px', threshold: 0 });
        }
        window.__osrsLiveAssetWarmObserver.observe(el);
    }

    function scan(root) {
        if (!root || !root.querySelectorAll) {
            return;
        }
        root.querySelectorAll('img, picture > source, video[poster]').forEach(observe);
    }

    function start() {
        scan(document);
        if (typeof MutationObserver === 'undefined' || !document.documentElement) {
            return;
        }
        var mutationObserver = new MutationObserver(function (records) {
            records.forEach(function (record) {
                record.addedNodes.forEach(function (node) {
                    if (node.nodeType !== 1) {
                        return;
                    }
                    if (node.matches && node.matches('img, picture > source, video[poster]')) {
                        observe(node);
                    }
                    scan(node);
                });
            });
        });
        mutationObserver.observe(document.documentElement, { childList: true, subtree: true });
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', start);
    } else {
        start();
    }
})();
