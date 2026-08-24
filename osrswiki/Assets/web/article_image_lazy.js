(function () {
    'use strict';
    if (window.__osrsArticleImageLazy) {
        return;
    }
    window.__osrsArticleImageLazy = true;

    function restoreDeferredImage(image) {
        if (!image || image.tagName !== 'IMG') {
            return false;
        }
        var src = image.getAttribute('data-osrs-deferred-src');
        if (src) {
            image.setAttribute('src', src);
            image.removeAttribute('data-osrs-deferred-src');
        }
        var srcset = image.getAttribute('data-osrs-deferred-srcset');
        if (srcset) {
            image.setAttribute('srcset', srcset);
            image.removeAttribute('data-osrs-deferred-srcset');
        }
        var sizes = image.getAttribute('data-osrs-deferred-sizes');
        if (sizes) {
            image.setAttribute('sizes', sizes);
            image.removeAttribute('data-osrs-deferred-sizes');
        }
        image.classList.remove('osrs-deferred-offscreen-image');
        image.classList.remove('osrs-deferred-table-image');
        return !!src || !!srcset;
    }

    window.osrsRestoreDeferredImage = restoreDeferredImage;

    function observe(image) {
        if (!image || image.__osrsLazyObserved) {
            return;
        }
        image.__osrsLazyObserved = true;
        if (typeof IntersectionObserver === 'undefined') {
            restoreDeferredImage(image);
            return;
        }
        if (!window.__osrsArticleImageLazyObserver) {
            window.__osrsArticleImageLazyObserver = new IntersectionObserver(function (entries) {
                entries.forEach(function (entry) {
                    if (!entry.isIntersecting) {
                        return;
                    }
                    restoreDeferredImage(entry.target);
                    window.__osrsArticleImageLazyObserver.unobserve(entry.target);
                });
            }, { root: null, rootMargin: '100% 0px', threshold: 0 });
        }
        window.__osrsArticleImageLazyObserver.observe(image);
    }

    function scan(root) {
        if (!root || !root.querySelectorAll) {
            return;
        }
        root.querySelectorAll('img[data-osrs-deferred-src]').forEach(observe);
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
                    if (node.matches && node.matches('img[data-osrs-deferred-src]')) {
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
