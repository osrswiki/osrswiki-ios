(function() {
    'use strict';

    /**
     * Mobile viewport area cap for content images.
     * 
     * Policy: If an image's rendered size would occupy more than 50% of the viewport area,
     * scale it down uniformly (preserving aspect ratio) so rendered area ≤ 50% viewport area.
     * 
     * Target: Portrait images and large content images that would dominate a phone screen.
     * Excludes: Small icons, inventory images, UI chrome, map tiles.
     * 
     * Approach: Measure natural/attributed dimensions vs visual viewport, apply max-width/max-height
     * only when area threshold exceeded. Small images remain untouched.
     */

    const MAX_VIEWPORT_AREA_RATIO = 0.5; // 50% of viewport area
    const EXCLUDED_CLASSES = [
        'inventory-image',
        'mw-file-element', // Small inline semantic images
        'osrs-inline-icon',
        'scp', // Skill/item template icons in tables
    ];
    const EXCLUDED_SELECTORS = [
        '.wikitable img', // Table icons (already sized at ~22px)
        '.infobox-bonuses img', // Equipment stat icons
        '.navbox img',
        '.mw-kartographer-map img', // Map tiles
        'figure.mw-default-size img', // Small inline figures
    ].join(', ');

    function isExcludedImage(img) {
        // Check excluded classes
        for (const cls of EXCLUDED_CLASSES) {
            if (img.classList.contains(cls)) {
                return true;
            }
        }
        
        // Check if image is in an excluded selector context
        if (img.matches && img.matches(EXCLUDED_SELECTORS)) {
            return true;
        }
        
        // Check parent containers
        if (img.closest('.inventory-image, .scp, .wikitable, .infobox-bonuses, .navbox')) {
            return true;
        }
        
        return false;
    }

    function getImageDimensions(img) {
        // Try attributed dimensions first (from MediaWiki markup)
        const attrWidth = img.getAttribute('width');
        const attrHeight = img.getAttribute('height');
        
        if (attrWidth && attrHeight) {
            return {
                width: parseInt(attrWidth, 10),
                height: parseInt(attrHeight, 10),
                source: 'attributed'
            };
        }
        
        // Fall back to natural dimensions if available
        if (img.naturalWidth && img.naturalHeight) {
            return {
                width: img.naturalWidth,
                height: img.naturalHeight,
                source: 'natural'
            };
        }
        
        // Last resort: computed/rendered dimensions
        const rect = img.getBoundingClientRect();
        if (rect.width > 0 && rect.height > 0) {
            return {
                width: Math.round(rect.width),
                height: Math.round(rect.height),
                source: 'rendered'
            };
        }
        
        return null;
    }

    function applyAreaCap(img) {
        if (isExcludedImage(img)) {
            return;
        }
        
        const dims = getImageDimensions(img);
        if (!dims) {
            return;
        }
        
        const viewportWidth = window.innerWidth || document.documentElement.clientWidth;
        const viewportHeight = window.innerHeight || document.documentElement.clientHeight;
        const viewportArea = viewportWidth * viewportHeight;
        const maxArea = viewportArea * MAX_VIEWPORT_AREA_RATIO;
        
        const imageArea = dims.width * dims.height;
        
        // If image area is within limit, don't touch it
        if (imageArea <= maxArea) {
            return;
        }
        
        // Image exceeds 50% viewport area - scale it down uniformly
        // Calculate scale factor to bring area down to exactly 50%, then also
        // keep the result inside the viewport width so a square cap cannot
        // overflow a portrait phone column.
        const scaleFactor = Math.sqrt(maxArea / imageArea);
        let targetWidth = Math.round(dims.width * scaleFactor);
        let targetHeight = Math.round(dims.height * scaleFactor);
        if (targetWidth > viewportWidth && dims.width > 0) {
            targetWidth = viewportWidth;
            targetHeight = Math.round(targetWidth * (dims.height / dims.width));
        }
        
        // Apply as max-width/max-height to preserve aspect ratio and allow smaller sizes
        img.style.maxWidth = targetWidth + 'px';
        img.style.maxHeight = targetHeight + 'px';
        img.style.width = 'auto';
        img.style.height = 'auto';
        img.style.objectFit = 'contain';
        
        // Mark as capped for debugging
        img.dataset.osrsAreaCapped = 'true';
        
        if (window.OsrsWikiBridge && typeof window.OsrsWikiBridge.log === 'function') {
            window.OsrsWikiBridge.log(
                '[ImageAreaCap] Capped ' + (img.alt || 'image') + 
                ': ' + dims.width + 'x' + dims.height + 
                ' (' + Math.round(imageArea / 1000) + 'k area, ' + 
                Math.round((imageArea / viewportArea) * 100) + '% viewport)' +
                ' → ' + targetWidth + 'x' + targetHeight
            );
        }
    }

    function processContentImages() {
        // Target: content images in articles/infoboxes that could dominate the screen
        const selectors = [
            '.mw-parser-output img',
            '.infobox img',
            '.infobox-full-width-content img',
            'figure[typeof^="mw:File"] img',
            '.osrs-balanced-portrait'
        ];
        
        const images = document.querySelectorAll(selectors.join(', '));
        images.forEach(applyAreaCap);
    }

    // Process images after load and on resize/orientation change
    function scheduleImageAreaCheck() {
        const schedule = window.requestAnimationFrame || window.setTimeout;
        schedule(processContentImages, 16);
    }

    // Run on load
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', scheduleImageAreaCheck, { once: true });
    } else {
        scheduleImageAreaCheck();
    }

    // Re-process on window resize (viewport size changes)
    window.addEventListener('resize', scheduleImageAreaCheck, { passive: true });
    window.addEventListener('orientationchange', scheduleImageAreaCheck, { passive: true });

    // Re-process when images finish loading
    window.addEventListener('load', scheduleImageAreaCheck, { once: true });

    // Expose for testing/debugging
    window.OSRSImageAreaCap = {
        process: processContentImages,
        applyTo: applyAreaCap
    };

})();
