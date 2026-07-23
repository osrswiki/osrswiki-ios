// Simple responsive videos - WebChromeClient handles YouTube navigation
(function() {
    'use strict';

    function log(message) {
        if (window.OsrsWikiBridge && typeof window.OsrsWikiBridge.log === 'function') {
            window.OsrsWikiBridge.log('[ResponsiveVideos] ' + message);
        }
    }
    
    log('Responsive videos script executing');
    
    // No custom JavaScript needed - the native YouTube "Watch on YouTube" button
    // is now intercepted by WebChromeClient.onCreateWindow()
    
    log('WebChromeClient handles YouTube navigation - no custom JS needed');

})();