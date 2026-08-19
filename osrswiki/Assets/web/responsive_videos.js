// In-app YouTube playback for wiki embeds.
// Custom-scheme article documents (app-assets://) have no HTTPS Referer, so
// YouTube iframes fail with error 153. Native playback loads the embed as a
// top-level https://www.youtube.com/embed document instead. Do not leave a
// YouTube iframe in the article document when native playback is available.
(function() {
    'use strict';

    var WIKI_ORIGIN = 'https://oldschool.runescape.wiki';

    function log(message) {
        if (window.OsrsWikiBridge && typeof window.OsrsWikiBridge.log === 'function') {
            window.OsrsWikiBridge.log('[ResponsiveVideos] ' + message);
        }
    }

    function youtubeVideoId(src) {
        if (!src) return null;
        try {
            var url = new URL(src, WIKI_ORIGIN);
            var host = (url.hostname || '').replace(/^www\./, '');
            if (host === 'youtu.be') {
                return url.pathname.replace(/^\//, '').split('/')[0] || null;
            }
            if (host === 'youtube.com' || host === 'youtube-nocookie.com' || host === 'm.youtube.com') {
                if (url.searchParams.get('v')) return url.searchParams.get('v');
                var parts = url.pathname.split('/').filter(Boolean);
                var embedIndex = parts.indexOf('embed');
                if (embedIndex >= 0 && parts[embedIndex + 1]) return parts[embedIndex + 1];
                var shortsIndex = parts.indexOf('shorts');
                if (shortsIndex >= 0 && parts[shortsIndex + 1]) return parts[shortsIndex + 1];
            }
        } catch (e) {
            return null;
        }
        return null;
    }

    function embedSrc(videoId) {
        return 'https://www.youtube.com/embed/' + encodeURIComponent(videoId) +
            '?playsinline=1&rel=0&modestbranding=1&origin=' + encodeURIComponent(WIKI_ORIGIN);
    }

    function canPlayNative() {
        return !!(window.OsrsWikiBridge && typeof window.OsrsWikiBridge.playYouTube === 'function') ||
            !!(window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.osrsYouTube);
    }

    function playNative(videoId) {
        if (window.OsrsWikiBridge && typeof window.OsrsWikiBridge.playYouTube === 'function') {
            window.OsrsWikiBridge.playYouTube(videoId);
            return true;
        }
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.osrsYouTube) {
            window.webkit.messageHandlers.osrsYouTube.postMessage({ videoId: videoId });
            return true;
        }
        return false;
    }

    function ensureRelativeParent(node) {
        if (!node) return;
        if (window.getComputedStyle(node).position === 'static') {
            node.style.position = 'relative';
        }
    }

    function playOverlay(videoId) {
        var overlay = document.createElement('button');
        overlay.type = 'button';
        overlay.className = 'osrs-youtube-play-overlay';
        overlay.setAttribute('aria-label', 'Play video');
        overlay.style.cssText = [
            'position:absolute',
            'inset:0',
            'width:100%',
            'height:100%',
            'border:0',
            'padding:0',
            'cursor:pointer',
            'z-index:2',
            'background:#111 url("https://i.ytimg.com/vi/' + encodeURIComponent(videoId) + '/hqdefault.jpg") center/cover no-repeat'
        ].join(';');
        overlay.innerHTML = '<span style="display:flex;align-items:center;justify-content:center;width:100%;height:100%;background:rgba(0,0,0,0.28)"><span style="width:68px;height:48px;border-radius:12px;background:#f00;display:flex;align-items:center;justify-content:center"><span style="border-style:solid;border-width:10px 0 10px 18px;border-color:transparent transparent transparent #fff;margin-left:4px"></span></span></span>';
        overlay.addEventListener('click', function(event) {
            event.preventDefault();
            event.stopPropagation();
            if (!playNative(videoId)) {
                overlay.remove();
            }
        });
        return overlay;
    }

    function enhanceIframe(iframe) {
        if (!iframe || iframe.dataset.osrsYoutubeEnhanced === 'true') return;
        var videoId = youtubeVideoId(iframe.getAttribute('src') || iframe.getAttribute('data-src') || '');
        if (!videoId) return;
        iframe.dataset.osrsYoutubeEnhanced = 'true';

        if (canPlayNative()) {
            iframe.removeAttribute('src');
            iframe.setAttribute('data-osrs-youtube-id', videoId);
            iframe.setAttribute('aria-hidden', 'true');
            iframe.style.visibility = 'hidden';
            iframe.style.pointerEvents = 'none';
            var parent = iframe.parentNode;
            ensureRelativeParent(parent);
            if (parent) parent.appendChild(playOverlay(videoId));
            return;
        }

        iframe.setAttribute('referrerpolicy', 'strict-origin-when-cross-origin');
        iframe.setAttribute('allow', 'accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share');
        iframe.setAttribute('allowfullscreen', '');
        iframe.src = embedSrc(videoId);
    }

    function enhanceAll() {
        document.querySelectorAll('iframe[src*="youtube"], iframe[src*="youtu.be"], iframe[data-src*="youtube"]').forEach(enhanceIframe);
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', enhanceAll);
    } else {
        enhanceAll();
    }
    document.addEventListener('DOMContentLoaded', enhanceAll);
    if (window.mw && mw.hook) {
        mw.hook('wikipage.content').add(enhanceAll);
    }
    log('YouTube embed enhancer installed');
})();
