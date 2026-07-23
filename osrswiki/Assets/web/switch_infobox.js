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
            const firstIndex = mainButtons[0].getAttribute('data-switch-index');
            performSwitch(firstIndex);
            
            // Stabilize infobox width by measuring all states
            stabilizeInfoboxWidth(mainInfobox, mainButtons);
        }
    } catch (e) {
        console.error(`Switcher CRITICAL ERROR in initializePage: ${e.message}`);
    }
}

function performSwitch(switchIndex) {
    if (typeof switchIndex === 'undefined' || switchIndex === null) return;

    console.log(`[LAYOUT DEBUG] performSwitch called with index: ${switchIndex}`);

    // Update button states
    document.querySelectorAll('.infobox-buttons, .switch-infobox-triggers').forEach(container => {
        // Log container info before changes
        const computedStyle = window.getComputedStyle(container);
        const rect = container.getBoundingClientRect();
        console.log(`[LAYOUT DEBUG] Container before switch - display: ${computedStyle.display}, grid-template-columns: ${computedStyle.gridTemplateColumns}, width: ${rect.width}px, height: ${rect.height}px`);
        
        const buttons = container.querySelectorAll('.button, .trigger');
        console.log(`[LAYOUT DEBUG] Container has ${buttons.length} buttons`);
        
        buttons.forEach((btn, index) => {
            const btnRect = btn.getBoundingClientRect();
            const btnStyle = window.getComputedStyle(btn);
            console.log(`[LAYOUT DEBUG] Button ${index}: width: ${btnRect.width}px, height: ${btnRect.height}px, text: "${btn.textContent.trim()}"`);
            btn.classList.remove('button-selected');
        });
        
        const btnToSelect = container.querySelector(`[data-switch-index="${switchIndex}"]`);
        if (btnToSelect) {
            btnToSelect.classList.add('button-selected');
            console.log(`[LAYOUT DEBUG] Selected button: "${btnToSelect.textContent.trim()}"`);
        }
        
        // Log container info after changes
        setTimeout(() => {
            const newComputedStyle = window.getComputedStyle(container);
            const newRect = container.getBoundingClientRect();
            console.log(`[LAYOUT DEBUG] Container after switch - display: ${newComputedStyle.display}, grid-template-columns: ${newComputedStyle.gridTemplateColumns}, width: ${newRect.width}px, height: ${newRect.height}px`);
            
            // Check if layout changed
            if (Math.abs(rect.width - newRect.width) > 1 || Math.abs(rect.height - newRect.height) > 1) {
                console.warn(`[LAYOUT DEBUG] ⚠️ LAYOUT SHIFT DETECTED! Width: ${rect.width}px → ${newRect.width}px, Height: ${rect.height}px → ${newRect.height}px`);
            }
        }, 100);
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
            // Restore display flex - now that we have width stabilization, this is safe
            console.log(`[LAYOUT DEBUG] configureLegacySwitchers: Setting display flex for container with ${triggerContainer.querySelectorAll('.button, .trigger').length} buttons`);
            triggerContainer.style.display = 'flex';
        }
    });
}

function stabilizeInfoboxWidth(mainInfobox, mainButtons) {
    try {
        console.log(`[LAYOUT DEBUG] === STARTING WIDTH STABILIZATION ===`);
        console.log(`[LAYOUT DEBUG] Infobox element:`, mainInfobox);
        console.log(`[LAYOUT DEBUG] Number of buttons: ${mainButtons.length}`);
        
        // Log initial state measurements
        const buttonContainer = mainInfobox.querySelector('.infobox-buttons, .switch-infobox-triggers');
        const table = mainInfobox.querySelector('table');
        
        console.log(`[LAYOUT DEBUG] INITIAL MEASUREMENTS:`);
        console.log(`[LAYOUT DEBUG] - Infobox width: ${mainInfobox.offsetWidth}px`);
        console.log(`[LAYOUT DEBUG] - Button container width: ${buttonContainer ? buttonContainer.offsetWidth : 'N/A'}px`);
        console.log(`[LAYOUT DEBUG] - Table width: ${table ? table.offsetWidth : 'N/A'}px`);
        
        // Store original state
        const originalSelectedButton = mainInfobox.querySelector('.button-selected');
        const originalIndex = originalSelectedButton ? originalSelectedButton.getAttribute('data-switch-index') : '0';
        console.log(`[LAYOUT DEBUG] Original selected index: ${originalIndex}`);
        
        let maxWidth = 0;
        const measurements = [];
        
        // Sequential measurement function to avoid async timing issues
        function measureNextState(buttonIndex) {
            if (buttonIndex >= mainButtons.length) {
                // All measurements complete
                console.log(`[LAYOUT DEBUG] === ALL MEASUREMENTS COMPLETE ===`);
                measurements.forEach(m => {
                    console.log(`[LAYOUT DEBUG] State ${m.index}: infobox=${m.infoboxWidth}px, buttons=${m.buttonContainerWidth}px, table=${m.tableWidth}px`);
                });
                
                const minWidth = Math.min(...measurements.map(m => m.infoboxWidth));
                const maxButtonWidth = Math.max(...measurements.map(m => m.buttonContainerWidth));
                const maxTableWidth = Math.max(...measurements.map(m => m.tableWidth));
                
                console.log(`[LAYOUT DEBUG] Width ranges:`);
                console.log(`[LAYOUT DEBUG] - Infobox: ${minWidth}px - ${maxWidth}px (difference: ${maxWidth - minWidth}px)`);
                console.log(`[LAYOUT DEBUG] - Button container: ${Math.min(...measurements.map(m => m.buttonContainerWidth))}px - ${maxButtonWidth}px`);
                console.log(`[LAYOUT DEBUG] - Table: ${Math.min(...measurements.map(m => m.tableWidth))}px - ${maxTableWidth}px`);
                
                // Determine what element to stabilize based on which varies most
                const infoboxVariance = maxWidth - minWidth;
                const tableVariance = maxTableWidth - Math.min(...measurements.map(m => m.tableWidth));
                
                console.log(`[LAYOUT DEBUG] Variance analysis:`);
                console.log(`[LAYOUT DEBUG] - Infobox variance: ${infoboxVariance}px`);
                console.log(`[LAYOUT DEBUG] - Table variance: ${tableVariance}px`);
                
                // Apply stabilization to table if it has significant variance, otherwise to infobox
                if (table && tableVariance > 5) {
                    // Stabilize the table width (more targeted)
                    const stabilizedTableWidth = maxTableWidth + 5; // Smaller buffer for table
                    table.style.minWidth = stabilizedTableWidth + 'px';
                    console.log(`[LAYOUT DEBUG] Applied table min-width: ${stabilizedTableWidth}px (table approach)`);
                } else {
                    // Fallback to infobox stabilization with reduced buffer
                    const stabilizedWidth = maxWidth + 5; // Reduced buffer
                    mainInfobox.style.minWidth = stabilizedWidth + 'px';
                    console.log(`[LAYOUT DEBUG] Applied infobox min-width: ${stabilizedWidth}px (infobox approach)`);
                }
                
                // Return to original state
                performSwitch(originalIndex);
                
                console.log(`[LAYOUT DEBUG] === WIDTH STABILIZATION COMPLETE ===`);
                return;
            }
            
            const button = mainButtons[buttonIndex];
            const switchIndex = button.getAttribute('data-switch-index');
            console.log(`[LAYOUT DEBUG] Measuring state ${switchIndex} (button ${buttonIndex + 1}/${mainButtons.length})`);
            
            performSwitch(switchIndex);
            
            // Give DOM time to update before measuring
            setTimeout(() => {
                const infoboxWidth = mainInfobox.offsetWidth;
                const buttonContainerWidth = buttonContainer ? buttonContainer.offsetWidth : 0;
                const tableWidth = table ? table.offsetWidth : 0;
                
                measurements.push({ 
                    index: switchIndex, 
                    infoboxWidth: infoboxWidth,
                    buttonContainerWidth: buttonContainerWidth,
                    tableWidth: tableWidth
                });
                
                console.log(`[LAYOUT DEBUG] State ${switchIndex} measurements:`);
                console.log(`[LAYOUT DEBUG] - Infobox: ${infoboxWidth}px`);
                console.log(`[LAYOUT DEBUG] - Button container: ${buttonContainerWidth}px`);
                console.log(`[LAYOUT DEBUG] - Table: ${tableWidth}px`);
                
                maxWidth = Math.max(maxWidth, infoboxWidth);
                
                // Recursively measure next state
                measureNextState(buttonIndex + 1);
            }, 150); // Slightly longer delay to ensure DOM updates
        }
        
        // Start measuring from the first button
        measureNextState(0);
        
    } catch (e) {
        console.error(`[LAYOUT DEBUG] Error in stabilizeInfoboxWidth: ${e.message}`);
    }
}

const remoteWikiDomain = "https://oldschool.runescape.wiki";

const fixUrls = (htmlString) => {
    if (!htmlString) return "";
    const regex = /(src|srcset)\s*=\s*['"](\/(?!\/)[^'"]*)['"]/g;
    return htmlString.replace(regex, `$1="${remoteWikiDomain}$2"`);
};

mw.hook('wikipage.content').add(initializePage);
