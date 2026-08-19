/**
 * Modern, vanilla JS implementation of the infobox switcher.
 *
 * FOUC Fix Strategy: "Image Preloading & Decoding"
 * This script fixes the "flash" on the first switch by finding all potential
 * switcher images on page load and preloading them into the browser's cache.
 * It also uses non-destructive update methods for image elements to prevent
 * repaint flashes.
 */

function initializePage() {
    try {
        const mainInfobox = document.querySelector('.infobox-switch');
        if (!mainInfobox) return;

        const mainButtons = mainInfobox.querySelectorAll('.infobox-buttons .button');
        if (mainButtons.length === 0) return;

        // --- IMAGE PRELOADING (with srcset support) ---
        const imageUrlsToPreload = new Set();
        const resourceContainers = document.querySelectorAll('[class*="infobox-resources-"], .rsw-synced-switch');

        resourceContainers.forEach(container => {
            const images = container.querySelectorAll('img');
            images.forEach(img => {
                const src = img.getAttribute('src');
                if (src) { imageUrlsToPreload.add(src); }
                const srcset = img.getAttribute('srcset');
                if (srcset) {
                    const sources = srcset.split(',').map(s => s.trim().split(/\s+/)[0]);
                    sources.forEach(sourceUrl => imageUrlsToPreload.add(sourceUrl));
                }
            });
        });

        imageUrlsToPreload.forEach(url => {
            const preloader = new Image();
            preloader.src = url;
            preloader.decode().catch(() => {});
        });
        // --- END PRELOADER ---

        document.body.addEventListener('click', (event) => {
            const button = event.target.closest('.button');
            if (button && button.hasAttribute('data-switch-index')) {
                const switchIndex = button.getAttribute('data-switch-index');
                performSwitch(switchIndex);
            }
        });

        configureLegacySwitchers(mainButtons);

        if (mainButtons.length > 0) {
            // Select the authored default synchronously before RenderTimeline reveals the body.
            // Images for all states decode concurrently above; never click through hidden states.
            const buttonsContainer = mainInfobox.querySelector('.infobox-buttons');
            const defaultIndex = buttonsContainer && buttonsContainer.getAttribute('data-default-version');
            const selectedButton = mainInfobox.querySelector('.button-selected');
            const initialIndex = defaultIndex ||
                (selectedButton && selectedButton.getAttribute('data-switch-index')) ||
                mainButtons[0].getAttribute('data-switch-index');
            performSwitch(initialIndex);
            lockSwitcherMinBlockSize();
            mainInfobox.dataset.osrsSwitcherReady = 'true';
            document.querySelectorAll('.switch-infobox, .rsw-synced-switch').forEach(function(box) {
                box.dataset.osrsSwitcherReady = 'true';
            });
        }
    } catch (e) {
        console.error(`Switcher CRITICAL ERROR in initializePage: ${e.message}`);
    }
}

function performSwitch(switchIndex) {
    if (typeof switchIndex === 'undefined' || switchIndex === null) return;

    // Update button states
    document.querySelectorAll('.infobox-buttons, .switch-infobox-triggers').forEach(container => {
        const buttons = container.querySelectorAll('.button, .trigger');
        buttons.forEach((btn) => {
            btn.classList.remove('button-selected');
        });
        
        const btnToSelect = container.querySelector(`[data-switch-index="${switchIndex}"]`);
        if (btnToSelect) {
            btnToSelect.classList.add('button-selected');
        }
    });

    // Update infobox content
    const infoboxesToUpdate = document.querySelectorAll('.infobox-switch[data-resource-class]');
    infoboxesToUpdate.forEach(infobox => {
        const resourceClass = infobox.getAttribute('data-resource-class');
        const resources = resourceClass ? document.querySelector(resourceClass) : null;
        if (resources) {
            populatePlaceholders(infobox, resources, switchIndex);
        }
    });

    // Update synced galleries
    const syncedSwitches = document.querySelectorAll('.rsw-synced-switch');
    syncedSwitches.forEach(syncedSwitch => {
        const allItems = syncedSwitch.querySelectorAll('.rsw-synced-switch-item');
        allItems.forEach(item => item.classList.remove('showing'));
        const itemIndexToShow = parseInt(switchIndex, 10);
        if (allItems.length > itemIndexToShow) {
            const itemToShow = allItems[itemIndexToShow];
            if (itemToShow) {
                itemToShow.classList.add('showing');
            }
        }
    });
}

function populatePlaceholders(container, resources, switchIndex) {
    const placeholders = container.querySelectorAll('[data-attr-param]');
    placeholders.forEach(placeholder => {
        const paramName = placeholder.getAttribute('data-attr-param');
        if (!paramName) return;

        const resourceGroup = resources.querySelector(`[data-attr-param="${paramName}"]`);
        if (resourceGroup) {
            let newContentElement = resourceGroup.querySelector(`[data-attr-index="${switchIndex}"]`);
            if (!newContentElement) {
                newContentElement = resourceGroup.querySelector('[data-attr-index="0"]');
            }
            if (newContentElement) {
                replacePlaceholderFromResource(placeholder, newContentElement);
            }
        }
    });
}

function replacePlaceholderFromResource(placeholder, newContentElement) {
    const incoming = fixUrls(newContentElement.innerHTML);
    const oldImg = placeholder.querySelector('img');
    const scratch = document.createElement('div');
    scratch.innerHTML = incoming;
    const newImg = scratch.querySelector('img');
    if (oldImg && newImg) {
        updateExistingImage(oldImg, newImg);
        return;
    }
    placeholder.innerHTML = incoming;
}

function updateExistingImage(oldImg, newImg) {
    const copyAttrs = ['src', 'srcset', 'width', 'height', 'alt', 'class'];
    copyAttrs.forEach((attr) => {
        if (newImg.hasAttribute(attr)) {
            oldImg.setAttribute(attr, newImg.getAttribute(attr));
        } else if (attr === 'srcset' || attr === 'alt') {
            oldImg.removeAttribute(attr);
        }
    });
    const width = Number(newImg.getAttribute('width'));
    const height = Number(newImg.getAttribute('height'));
    if (width > 0 && height > 0) {
        oldImg.style.aspectRatio = width + ' / ' + height;
        oldImg.style.height = 'auto';
    }
}

function lockSwitcherMinBlockSize() {
    document.querySelectorAll('.infobox-switch[data-resource-class]').forEach((infobox) => {
        const resourceClass = infobox.getAttribute('data-resource-class');
        const resources = resourceClass ? document.querySelector(resourceClass) : null;
        if (!resources) return;

        const indices = Array.from(
            infobox.querySelectorAll('.infobox-buttons .button[data-switch-index]')
        ).map((button) => button.getAttribute('data-switch-index')).filter(Boolean);
        if (indices.length === 0) return;

        const probe = infobox.cloneNode(true);
        probe.setAttribute('aria-hidden', 'true');
        probe.style.cssText = [
            'position:absolute',
            'left:-10000px',
            'top:0',
            'visibility:hidden',
            'pointer-events:none',
            'width:max-content',
            'max-width:none',
            'min-width:0',
            'min-height:0',
            'table-layout:auto'
        ].join(';');
        infobox.parentNode.appendChild(probe);

        let maxHeight = infobox.getBoundingClientRect().height;
        let maxWidth = infobox.getBoundingClientRect().width;
        let maxLabelWidth = 0;
        indices.forEach((index) => {
            populatePlaceholders(probe, resources, index);
            const rect = probe.getBoundingClientRect();
            maxHeight = Math.max(maxHeight, rect.height);
            maxWidth = Math.max(maxWidth, rect.width);
            probe.querySelectorAll('th:not(.infobox-header):not([colspan])').forEach((th) => {
                maxLabelWidth = Math.max(maxLabelWidth, th.getBoundingClientRect().width);
            });
        });
        probe.remove();

        if (maxHeight > 0) {
            infobox.style.minHeight = Math.ceil(maxHeight) + 'px';
        }
        if (maxWidth > 0) {
            infobox.style.minWidth = Math.ceil(maxWidth) + 'px';
        }
        if (maxLabelWidth > 0) {
            const labelPx = Math.ceil(maxLabelWidth) + 'px';
            infobox.querySelectorAll('th:not(.infobox-header):not([colspan])').forEach((th) => {
                th.style.minWidth = labelPx;
            });
        }
    });
}

function configureLegacySwitchers(mainButtons) {
    const legacyTriggers = document.querySelectorAll('.switch-infobox-triggers');
    legacyTriggers.forEach((triggerContainer) => {
        const legacyButtons = triggerContainer.querySelectorAll('.trigger.button');
        legacyButtons.forEach(legacyButton => {
            const id = legacyButton.getAttribute('data-id');
            const correspondingMainButton = mainButtons[parseInt(id, 10) - 1];
            if (correspondingMainButton) {
                legacyButton.setAttribute('data-switch-index', correspondingMainButton.getAttribute('data-switch-index'));
            }
        });
        const parentBox = triggerContainer.closest('.switch-infobox');
        if (parentBox) {
            const loadingButton = parentBox.querySelector('.loading-button');
            if (loadingButton) loadingButton.style.display = 'none';
            // Images have already been decoded without mutating the visible selection.
            triggerContainer.style.display = 'flex';
        }
    });
}

const remoteWikiDomain = "https://oldschool.runescape.wiki";

const fixUrls = (htmlString) => {
    if (!htmlString) return "";
    const regex = /(src|srcset)\s*=\s*['"](\/(?!\/)[^'"]*)['"]/g;
    return htmlString.replace(regex, `$1="${remoteWikiDomain}$2"`);
};

mw.hook('wikipage.content').add(initializePage);
