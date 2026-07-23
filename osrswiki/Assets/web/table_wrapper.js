/*
 * Table Wrapper Script for iOS
 * Creates scrollable wrappers for wide tables that exceed viewport width
 */
(function() {
    'use strict';

    const LOG_TAG = 'TableWrapper';

    function log(message) {
        console.log(`[${LOG_TAG}] ${message}`);
    }

    /**
     * Checks if a table is wider than its container and needs horizontal scrolling
     * @param {HTMLElement} table - The table element to check
     * @returns {boolean} True if table needs horizontal scrolling
     */
    function shouldWrapTable(table) {
        if (!table || table.tagName !== 'TABLE') {
            return false;
        }

        // Skip tables that are already wrapped
        if (table.parentElement && table.parentElement.classList.contains('scrollable-table-wrapper')) {
            return false;
        }

        // Skip tables inside collapsible containers that haven't been expanded yet
        const collapsibleContainer = table.closest('.collapsible-container');
        if (collapsibleContainer && collapsibleContainer.classList.contains('collapsed')) {
            return false;
        }

        // Get table's natural width vs container width
        const tableWidth = table.scrollWidth;
        const containerWidth = table.offsetWidth;
        
        log(`Table scrollWidth: ${tableWidth}, offsetWidth: ${containerWidth}`);
        
        // If table content is wider than the container, it needs wrapping
        return tableWidth > containerWidth;
    }

    /**
     * Wraps a table in a scrollable container
     * @param {HTMLElement} table - The table to wrap
     */
    function wrapTable(table) {
        // Create the wrapper div
        const wrapper = document.createElement('div');
        wrapper.className = 'scrollable-table-wrapper';
        wrapper.setAttribute('role', 'region');
        wrapper.setAttribute('aria-label', 'Scrollable table');
        wrapper.setAttribute('tabindex', '0'); // Make focusable for keyboard users

        // Insert wrapper before the table
        table.parentNode.insertBefore(wrapper, table);
        
        // Move table inside wrapper
        wrapper.appendChild(table);
        
        log(`Wrapped table with scrollWidth: ${table.scrollWidth}`);
    }

    /**
     * Process all wikitables on the page
     */
    function processWikitables() {
        const tables = document.querySelectorAll('table.wikitable');
        let wrappedCount = 0;
        
        tables.forEach(table => {
            if (shouldWrapTable(table)) {
                wrapTable(table);
                wrappedCount++;
            }
        });

        if (wrappedCount > 0) {
            log(`Wrapped ${wrappedCount} tables for horizontal scrolling`);
        }
    }

    /**
     * Process infobox tables that may need wrapping (like equipment bonus tables)
     */
    function processInfoboxTables() {
        const infoboxTables = document.querySelectorAll('table.infobox');
        let wrappedCount = 0;
        
        infoboxTables.forEach(table => {
            if (shouldWrapTable(table)) {
                wrapTable(table);
                wrappedCount++;
            }
        });

        if (wrappedCount > 0) {
            log(`Wrapped ${wrappedCount} infobox tables for horizontal scrolling`);
        }
    }

    /**
     * Initialize table wrapping
     */
    function initialize() {
        // Process tables immediately
        processWikitables();
        processInfoboxTables();

        // Set up observer for dynamically added content
        const observer = new MutationObserver(function(mutations) {
            let shouldProcess = false;
            
            mutations.forEach(function(mutation) {
                mutation.addedNodes.forEach(function(node) {
                    if (node.nodeType === Node.ELEMENT_NODE) {
                        // Check if new tables were added
                        if (node.tagName === 'TABLE' || node.querySelector && node.querySelector('table')) {
                            shouldProcess = true;
                        }
                    }
                });
            });

            if (shouldProcess) {
                log('New content detected, reprocessing tables');
                processWikitables();
                processInfoboxTables();
            }
        });

        // Start observing
        observer.observe(document.body, {
            childList: true,
            subtree: true
        });

        log('Table wrapper initialization complete');
    }

    // Initialize when DOM is ready
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', initialize);
    } else {
        initialize();
    }

    // Also run after collapsible content is revealed
    document.addEventListener('click', function(event) {
        const collapsibleHeader = event.target.closest('.collapsible-header');
        if (collapsibleHeader) {
            // Delay processing to allow collapse/expand animation to complete
            setTimeout(function() {
                processWikitables();
                processInfoboxTables();
            }, 300);
        }
    });

})();