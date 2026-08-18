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
                // For the large equipped-cape images, update attributes directly to prevent repaint flash.
                if ((paramName === 'image' || paramName === 'altimage') && container.classList.contains('infobox-bonuses')) {
                    const oldImg = placeholder.querySelector('img');
                    const newImg = newContentElement.querySelector('img');
                    if (oldImg && newImg) {
                        oldImg.src = newImg.src;
                        if (newImg.hasAttribute('srcset')) {
                            oldImg.srcset = newImg.getAttribute('srcset');
                        } else {
                            oldImg.removeAttribute('srcset');
                        }
                    } else {
                        placeholder.innerHTML = fixUrls(newContentElement.innerHTML); // Fallback
                    }
                } else {
                    // For all other content, standard replacement is fine.
                    placeholder.innerHTML = fixUrls(newContentElement.innerHTML);
                }
            }
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
