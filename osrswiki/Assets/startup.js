/**
 * This file is where we decide whether to initialise the modern support browser run-time.
 *
 * - Beware: This file MUST parse without errors on even the most ancient of browsers!
 */
/* eslint-disable no-implicit-globals */
/* global $CODE, RLQ:true, NORLQ:true */

/**
 * See <https://www.mediawiki.org/wiki/Compatibility#Browsers>
 *
 * Browsers that pass these checks get served our modern run-time. This includes all Grade A
 * browsers, and some Grade C and Grade X browsers.
 *
 * The following browsers are known to pass these checks:
 * - Chrome 63+
 * - Edge 79+
 * - Opera 50+
 * - Firefox 58+
 * - Safari 11.1+
 * - Mobile Safari 11.2+ (iOS 11+)
 * - Android 5.0+
 *
 * @private
 * @return {boolean} User agent is compatible with MediaWiki JS
 */
function isCompatible() {
	return !!(
		// Ensure DOM Level 4 features (including Selectors API).
		//
		// https://caniuse.com/#feat=queryselector
		'querySelector' in document &&

		// Ensure HTML 5 features (including Web Storage API)
		//
		// https://caniuse.com/#feat=namevalue-storage
		// https://blog.whatwg.org/this-week-in-html-5-episode-30
		'localStorage' in window &&

		// Ensure ES2015 runtime API (a.k.a. ES6)
		//
		// In practice, Promise.finally is a good proxy for overall ES6 support and
		// rejects most unsupporting browsers in one sweep. The feature itself
		// was specified in ES2018, however.
		// https://caniuse.com/promise-finally
		// Chrome 63+, Edge 18+, Opera 50+, Safari 11.1+, Firefox 58+, iOS 11+
		//
		// ES6 RegExp.prototype.flags
		// https://caniuse.com/mdn-javascript_builtins_regexp_flags
		// Edge 79+ (Chromium-based, rejects MSEdgeHTML-based Edge <= 18)
		//
		// eslint-disable-next-line es-x/no-promise, es-x/no-promise-prototype-finally, dot-notation
		typeof Promise === 'function' && Promise.prototype[ 'finally' ] &&
		// eslint-disable-next-line es-x/no-regexp-prototype-flags
		/./g.flags === 'g' &&

		// Ensure ES2017 grammar and syntax support, including:
		// - ES6 Arrow Functions (with default params)
		// - ES2017 Trailing comma in function params
		// - ES2017 Async Functions
		//
		// https://caniuse.com/mdn-javascript_grammar_trailing_commas_trailing_commas_in_functions
		// Chrome 58+, Edge 14+, Safari 10+, Firefox 52+, Opera 45+
		//
		// https://caniuse.com/async-functions
		// Chrome 55+, Edge 15+, Safari 11+, Firefox 52+, Opera 42+
		//
		// Based on Benjamin De Cock's snippet here:
		// https://gist.github.com/bendc/d7f3dbc83d0f65ca0433caf90378cd95
		( function () {
			try {
				// eslint-disable-next-line no-new, no-new-func
				new Function( 'async (a = 0,) => a' );
				return true;
			} catch ( e ) {
				return false;
			}
		}() )
	);
}

if ( !isCompatible() ) {
	// Handle basic supported browsers (Grade C).
	// Undo speculative modern (Grade A) root CSS class `<html class="client-js">`.
	// See ResourceLoaderClientHtml::getDocumentAttributes().
	document.documentElement.className = document.documentElement.className
		.replace( /(^|\s)client-js(\s|$)/, '$1client-nojs$2' );

	// Process any callbacks for basic support (Grade C).
	while ( window.NORLQ && NORLQ[ 0 ] ) {
		NORLQ.shift()();
	}
	NORLQ = {
		push: function ( fn ) {
			fn();
		}
	};

	// Clear and disable the modern (Grade A) queue.
	RLQ = {
		push: function () {}
	};
} else {
	// Handle modern (Grade A).

	if ( window.performance && performance.mark ) {
		performance.mark( 'mwStartup' );
	}

	// This embeds mediawiki.js, which defines 'mw' and 'mw.loader'.
	/**
 * Base library for MediaWiki.
 */
/* global $CODE */

( function () {
	'use strict';

	var con = window.console;

	/**
	 * @class mw.Map
	 * @classdesc Collection of values by string keys.
	 *
	 * This is an internal class that backs the mw.config and mw.messages APIs.
	 *
	 * It allows reading and writing to the collection via public methods,
	 * and allows batch iteraction for all its methods.
	 *
	 * For mw.config, scripts sometimes choose to "import" a set of keys locally,
	 * like so:
	 *
	 * ```
	 * var conf = mw.config.get( [ 'wgServerName', 'wgUserName', 'wgPageName' ] );
	 * conf.wgServerName; // "example.org"
	 * ```
	 *
	 * Check the existence ("AND" condition) of multiple keys:
	 *
	 * ```
	 * if ( mw.config.exists( [ 'wgFoo', 'wgBar' ] ) );
	 * ```
	 *
	 * For mw.messages, the {@link mw.Map#set} method allows mw.loader and mw.Api to essentially
	 * extend the object, and batch-apply all their loaded values in one go:
	 *
	 * ```
	 * mw.messages.set( { "mon": "Monday", "tue": "Tuesday" } );
	 * ```
	 *
	 * @hideconstructor
	 */
	function Map() {
		this.values = Object.create( null );
	}

	Map.prototype = /** @lends mw.Map.prototype */ {
		constructor: Map,

		/**
		 * Get the value of one or more keys.
		 *
		 * If called with no arguments, all values are returned.
		 *
		 * @param {string|Array} [selection] Key or array of keys to retrieve values for.
		 * @param {any} [fallback=null] Value for keys that don't exist.
		 * @return {any|Object|null} If selection was a string, returns the value,
		 *  If selection was an array, returns an object of key/values.
		 *  If no selection is passed, a new object with all key/values is returned.
		 */
		get: function ( selection, fallback ) {
			if ( arguments.length < 2 ) {
				fallback = null;
			}

			if ( typeof selection === 'string' ) {
				return selection in this.values ?
					this.values[ selection ] :
					fallback;
			}

			var results;
			if ( Array.isArray( selection ) ) {
				results = {};
				for ( var i = 0; i < selection.length; i++ ) {
					if ( typeof selection[ i ] === 'string' ) {
						results[ selection[ i ] ] = selection[ i ] in this.values ?
							this.values[ selection[ i ] ] :
							fallback;
					}
				}
				return results;
			}

			if ( selection === undefined ) {
				results = {};
				for ( var key in this.values ) {
					results[ key ] = this.values[ key ];
				}
				return results;
			}

			// Invalid selection key
			return fallback;
		},

		/**
		 * Set one or more key/value pairs.
		 *
		 * @param {string|Object} selection Key to set value for, or object mapping keys to values
		 * @param {any} [value] Value to set (optional, only in use when key is a string)
		 * @return {boolean} True on success, false on failure
		 */
		set: function ( selection, value ) {
			// Use `arguments.length` because `undefined` is also a valid value.
			if ( arguments.length > 1 ) {
				// Set one key
				if ( typeof selection === 'string' ) {
					this.values[ selection ] = value;
					return true;
				}
			} else if ( typeof selection === 'object' ) {
				// Set multiple keys
				for ( var key in selection ) {
					this.values[ key ] = selection[ key ];
				}
				return true;
			}
			return false;
		},

		/**
		 * Check if a given key exists in the map.
		 *
		 * @param {string} selection Key to check
		 * @return {boolean} True if the key exists
		 */
		exists: function ( selection ) {
			return typeof selection === 'string' && selection in this.values;
		}
	};

	/**
	 * Write a verbose message to the browser's console in debug mode.
	 *
	 * In ResourceLoader debug mode, this writes to the browser's console.
	 * In production mode, it is a no-op.
	 *
	 * See {@link mw.log} for other logging methods.
	 *
	 * @memberof mw
	 * @variation 2
	 * @param {...string} msg Messages to output to console.
	 */
	var log = function () {
		console.log.apply( console, arguments );
	};

	/**
	 * Write a message to the browser console's warning channel.
	 *
	 * @memberof mw.log
	 * @method warn
	 * @param {...string} msg Messages to output to console
	 */
	log.warn = Function.prototype.bind.call( con.warn, con );

	/**
	 * Base library for MediaWiki.
	 *
	 * Exposed globally as `mw`, with `mediaWiki` as alias. `mw` code can be considered stable and follows the
	 * [frontend stable interface policy](https://www.mediawiki.org/wiki/Special:MyLanguage/Stable_interface_policy/Frontend).
	 *
	 * @namespace mw
	 */
	var mw = /** @lends mw */ {
		/**
		 * Get the current time, measured in milliseconds since January 1, 1970 (UTC).
		 *
		 * On browsers that implement the Navigation Timing API, this function will produce
		 * floating-point values with microsecond precision that are guaranteed to be monotonic.
		 * On all other browsers, it will fall back to using `Date`.
		 *
		 * @return {number} Current time
		 */
		now: function () {
			// Optimisation: Cache and re-use the chosen implementation.
			// Optimisation: Avoid startup overhead by re-defining on first call instead of IIFE.
			var perf = window.performance;
			var navStart = perf && perf.timing && perf.timing.navigationStart;

			// Define the relevant shortcut
			mw.now = navStart && perf.now ?
				function () {
					return navStart + perf.now();
				} :
				Date.now;

			return mw.now();
		},

		/**
		 * List of all analytic events emitted so far.
		 *
		 * Exposed only for use by mediawiki.base.
		 *
		 * @private
		 * @property {Array}
		 */
		trackQueue: [],

		/**
		 * Track `'resourceloader.exception'` event and send it to the window console.
		 *
		 * This exists for internal use by mw.loader only, to remember and buffer
		 * very early events for `mw.trackSubscribe( 'resourceloader.exception' )`
		 * even while `mediawiki.base` and `mw.track` are still in-flight.
		 *
		 * @private
		 * @param {Object} data
		 * @param {Error} [data.exception]
		 * @param {string} data.source Error source
		 * @param {string} [data.module] Name of module which caused the error
		 */
		trackError: function ( data ) {
			if ( mw.track ) {
				mw.track( 'resourceloader.exception', data );
			} else {
				mw.trackQueue.push( { topic: 'resourceloader.exception', data: data } );
			}

			// Log an error message to window.console, even in production mode.
			var e = data.exception;
			var msg = ( e ? 'Exception' : 'Error' ) +
				' in ' + data.source +
				( data.module ? ' in module ' + data.module : '' ) +
				( e ? ':' : '.' );

			con.log( msg );

			// If we have an exception object, log it to the warning channel to trigger
			// proper stacktraces in browsers that support it.
			if ( e ) {
				con.warn( e );
			}
		},

		// Expose mw.Map
		Map: Map,

		/**
		 * Map of configuration values.
		 *
		 * Check out [the complete list of configuration values](https://www.mediawiki.org/wiki/Manual:Interface/JavaScript#mw.config)
		 * on mediawiki.org.
		 *
		 * @type {mw.Map}
		 */
		config: new Map(),

		/**
		 * Store for messages.
		 *
		 * @type {mw.Map}
		 */
		messages: new Map(),

		/**
		 * Store for templates associated with a module.
		 *
		 * @type {mw.Map}
		 */
		templates: new Map(),

		// Expose mw.log
		log: log

		// mw.loader is defined in a separate file that is appended to this
	};

	// Attach to window and globally alias
	window.mw = window.mediaWiki = mw;

	window.QUnit = undefined;
}() );
/*!
 * Defines mw.loader, the infrastructure for loading ResourceLoader
 * modules.
 *
 * This file is appended directly to the code in startup/mediawiki.js
 */
/* global $VARS, $CODE, mw */

( function () {
	'use strict';

	var store,
		hasOwn = Object.hasOwnProperty;

	/**
	 * Client for ResourceLoader server end point.
	 *
	 * This client is in charge of maintaining the module registry and state
	 * machine, initiating network (batch) requests for loading modules, as
	 * well as dependency resolution and execution of source code.
	 *
	 * @see <https://www.mediawiki.org/wiki/ResourceLoader/Features>
	 * @namespace mw.loader
	 */

	/**
	 * FNV132 hash function
	 *
	 * This function implements the 32-bit version of FNV-1.
	 * It is equivalent to hash( 'fnv132', ... ) in PHP, except
	 * its output is base 36 rather than hex.
	 * See <https://en.wikipedia.org/wiki/Fowler–Noll–Vo_hash_function>
	 *
	 * @private
	 * @param {string} str String to hash
	 * @return {string} hash as a five-character base 36 string
	 */
	function fnv132( str ) {
		var hash = 0x811C9DC5;

		/* eslint-disable no-bitwise */
		for ( var i = 0; i < str.length; i++ ) {
			hash += ( hash << 1 ) + ( hash << 4 ) + ( hash << 7 ) + ( hash << 8 ) + ( hash << 24 );
			hash ^= str.charCodeAt( i );
		}

		hash = ( hash >>> 0 ).toString( 36 ).slice( 0, 5 );
		/* eslint-enable no-bitwise */

		while ( hash.length < 5 ) {
			hash = '0' + hash;
		}
		return hash;
	}

	/**
	 * Fired via mw.track on various resource loading errors.
	 *
	 * eslint-disable jsdoc/valid-types
	 *
	 * @event ~'resourceloader.exception'
	 * @ignore
	 * @param {Error|Mixed} e The error that was thrown. Almost always an Error
	 *   object, but in theory module code could manually throw something else, and that
	 *   might also end up here.
	 * @param {string} [module] Name of the module which caused the error. Omitted if the
	 *   error is not module-related or the module cannot be easily identified due to
	 *   batched handling.
	 * @param {string} source Source of the error. Possible values:
	 *
	 *   - load-callback: exception thrown by user callback
	 *   - module-execute: exception thrown by module code
	 *   - resolve: failed to sort dependencies for a module in mw.loader.load
	 *   - store-eval: could not evaluate module code cached in localStorage
	 *   - store-localstorage-json: JSON conversion error in mw.loader.store
	 *   - store-localstorage-update: localStorage conversion error in mw.loader.store.
	 */

	/**
	 * Mapping of registered modules.
	 *
	 * See #implement and #execute for exact details on support for script, style and messages.
	 *
	 * @example // Format:
	 * {
	 *     'moduleName': {
	 *         // From mw.loader.register()
	 *         'version': '#####' (five-character hash)
	 *         'dependencies': ['required.foo', 'bar.also', ...]
	 *         'group': string, integer, (or) null
	 *         'source': 'local', (or) 'anotherwiki'
	 *         'skip': 'return !!window.Example;', (or) null, (or) boolean result of skip
	 *         'module': export Object
	 *
	 *         // Set by execute() or mw.loader.state()
	 *         // See mw.loader.getState() for documentation of the state machine
	 *         'state': 'registered', 'loading', 'loaded', 'executing', 'ready', 'error', or 'missing'
	 *
	 *         // Optionally added at run-time by mw.loader.impl()
	 *         'script': closure, array of urls, or string
	 *         'style': { ... } (see #execute)
	 *         'messages': { 'key': 'value', ... }
	 *     }
	 * }
	 *
	 * @property {Object}
	 * @private
	 */
	var registry = Object.create( null ),
		// Mapping of sources, keyed by source-id, values are strings.
		//
		// Format:
		//
		//     {
		//         'sourceId': 'http://example.org/w/load.php'
		//     }
		//
		sources = Object.create( null ),

		// For queueModuleScript()
		handlingPendingRequests = false,
		pendingRequests = [],

		// List of modules to be loaded
		queue = [],

		/**
		 * List of callback jobs waiting for modules to be ready.
		 *
		 * Jobs are created by #enqueue() and run by #doPropagation().
		 * Typically when a job is created for a module, the job's dependencies contain
		 * both the required module and all its recursive dependencies.
		 *
		 * @example // Format:
		 * {
		 *     'dependencies': [ module names ],
		 *     'ready': Function callback
		 *     'error': Function callback
		 * }
		 *
		 * @property {Object[]} jobs
		 * @private
		 */
		jobs = [],

		// For #setAndPropagate() and #doPropagation()
		willPropagate = false,
		errorModules = [],

		/**
		 * @private
		 * @property {Array} baseModules
		 */
		baseModules = [
    "jquery",
    "mediawiki.base"
],

		/**
		 * For #addEmbeddedCSS() and #addLink()
		 *
		 * @private
		 * @property {HTMLElement|null} marker
		 */
		marker = document.querySelector( 'meta[name="ResourceLoaderDynamicStyles"]' ),

		// For #addEmbeddedCSS()
		lastCssBuffer;

	/**
	 * Append an HTML element to `document.head` or before a specified node.
	 *
	 * @private
	 * @param {HTMLElement} el
	 * @param {Node|null} [nextNode]
	 */
	function addToHead( el, nextNode ) {
		if ( nextNode && nextNode.parentNode ) {
			nextNode.parentNode.insertBefore( el, nextNode );
		} else {
			document.head.appendChild( el );
		}
	}

	/**
	 * Create a new style element and add it to the DOM.
	 * Stable for use in gadgets.
	 *
	 * @method mw.loader.addStyleTag
	 * @param {string} text CSS text
	 * @param {Node|null} [nextNode] The element where the style tag
	 *  should be inserted before
	 * @return {HTMLStyleElement} Reference to the created style element
	 */
	function newStyleTag( text, nextNode ) {
		var el = document.createElement( 'style' );
		el.appendChild( document.createTextNode( text ) );
		addToHead( el, nextNode );
		return el;
	}

	/**
	 * @private
	 * @param {Object} cssBuffer
	 */
	function flushCssBuffer( cssBuffer ) {
		// Make sure the next call to addEmbeddedCSS() starts a new buffer.
		// This must be done before we run the callbacks, as those may end up
		// queueing new chunks which would be lost otherwise (T105973).
		//
		// There can be more than one buffer in-flight (given "@import", and
		// generally due to race conditions). Only tell addEmbeddedCSS() to
		// start a new buffer if we're currently flushing the last one that it
		// started. If we're flushing an older buffer, keep the last one open.
		if ( cssBuffer === lastCssBuffer ) {
			lastCssBuffer = null;
		}
		newStyleTag( cssBuffer.cssText, marker );
		for ( var i = 0; i < cssBuffer.callbacks.length; i++ ) {
			cssBuffer.callbacks[ i ]();
		}
	}

	/**
	 * Add a bit of CSS text to the current browser page.
	 *
	 * The creation and insertion of the `<style>` element is debounced for two reasons:
	 *
	 * - Performing the insertion before the next paint round via requestAnimationFrame
	 *   avoids forced or wasted style recomputations, which are expensive in browsers.
	 * - Reduce how often new stylesheets are inserted by letting additional calls to this
	 *   function accumulate into a buffer for at least one JavaScript tick. Modules are
	 *   received from the server in batches, which means there is likely going to be many
	 *   calls to this function in a row within the same tick / the same call stack.
	 *   See also T47810.
	 *
	 * @private
	 * @param {string} cssText CSS text to be added in a `<style>` tag.
	 * @param {Function} callback Called after the insertion has occurred.
	 */
	function addEmbeddedCSS( cssText, callback ) {
		// Start a new buffer if one of the following is true:
		// - We've never started a buffer before, this will be our first.
		// - The last buffer we created was flushed meanwhile, so start a new one.
		// - The next CSS chunk syntactically needs to be at the start of a stylesheet (T37562).
		if ( !lastCssBuffer || cssText.startsWith( '@import' ) ) {
			lastCssBuffer = {
				cssText: '',
				callbacks: []
			};
			requestAnimationFrame( flushCssBuffer.bind( null, lastCssBuffer ) );
		}

		// Linebreak for somewhat distinguishable sections
		lastCssBuffer.cssText += '\n' + cssText;
		lastCssBuffer.callbacks.push( callback );
	}

	/**
	 * See also `ResourceLoader.php#makeVersionQuery` on the server.
	 *
	 * @private
	 * @param {string[]} modules List of module names
	 * @return {string} Hash of concatenated version hashes.
	 */
	function getCombinedVersion( modules ) {
		var hashes = modules.reduce( function ( result, module ) {
			return result + registry[ module ].version;
		}, '' );
		return fnv132( hashes );
	}

	/**
	 * Determine whether all dependencies are in state 'ready', which means we may
	 * execute the module or job now.
	 *
	 * @private
	 * @param {string[]} modules Names of modules to be checked
	 * @return {boolean} True if all modules are in state 'ready', false otherwise
	 */
	function allReady( modules ) {
		for ( var i = 0; i < modules.length; i++ ) {
			if ( mw.loader.getState( modules[ i ] ) !== 'ready' ) {
				return false;
			}
		}
		return true;
	}

	/**
	 * Determine whether all direct and base dependencies are in state 'ready'
	 *
	 * @private
	 * @param {string} module Name of the module to be checked
	 * @return {boolean} True if all direct/base dependencies are in state 'ready'; false otherwise
	 */
	function allWithImplicitReady( module ) {
		return allReady( registry[ module ].dependencies ) &&
			( baseModules.indexOf( module ) !== -1 || allReady( baseModules ) );
	}

	/**
	 * Determine whether all dependencies are in state 'ready', which means we may
	 * execute the module or job now.
	 *
	 * @private
	 * @param {string[]} modules Names of modules to be checked
	 * @return {boolean|string} False if no modules are in state 'error' or 'missing';
	 *  failed module otherwise
	 */
	function anyFailed( modules ) {
		for ( var i = 0; i < modules.length; i++ ) {
			var state = mw.loader.getState( modules[ i ] );
			if ( state === 'error' || state === 'missing' ) {
				return modules[ i ];
			}
		}
		return false;
	}

	/**
	 * Handle propagation of module state changes and reactions to them.
	 *
	 * - When a module reaches a failure state, this should be propagated to
	 *   modules that depend on the failed module.
	 * - When a module reaches a final state, pending job callbacks for the
	 *   module from mw.loader.using() should be called.
	 * - When a module reaches the 'ready' state from #execute(), consider
	 *   executing dependent modules now having their dependencies satisfied.
	 * - When a module reaches the 'loaded' state from mw.loader.impl,
	 *   consider executing it, if it has no unsatisfied dependencies.
	 *
	 * @private
	 */
	function doPropagation() {
		var didPropagate = true;
		var module;

		// Keep going until the last iteration performed no actions.
		while ( didPropagate ) {
			didPropagate = false;

			// Stage 1: Propagate failures
			while ( errorModules.length ) {
				var errorModule = errorModules.shift(),
					baseModuleError = baseModules.indexOf( errorModule ) !== -1;
				for ( module in registry ) {
					if ( registry[ module ].state !== 'error' && registry[ module ].state !== 'missing' ) {
						if ( baseModuleError && baseModules.indexOf( module ) === -1 ) {
							// Propate error from base module to all regular (non-base) modules
							registry[ module ].state = 'error';
							didPropagate = true;
						} else if ( registry[ module ].dependencies.indexOf( errorModule ) !== -1 ) {
							// Propagate error from dependency to depending module
							registry[ module ].state = 'error';
							// .. and propagate it further
							errorModules.push( module );
							didPropagate = true;
						}
					}
				}
			}

			// Stage 2: Execute 'loaded' modules with no unsatisfied dependencies
			for ( module in registry ) {
				if ( registry[ module ].state === 'loaded' && allWithImplicitReady( module ) ) {
					// Recursively execute all dependent modules that were already loaded
					// (waiting for execution) and no longer have unsatisfied dependencies.
					// Base modules may have dependencies amongst eachother to ensure correct
					// execution order. Regular modules wait for all base modules.
					execute( module );
					didPropagate = true;
				}
			}

			// Stage 3: Invoke job callbacks that are no longer blocked
			for ( var i = 0; i < jobs.length; i++ ) {
				var job = jobs[ i ];
				var failed = anyFailed( job.dependencies );
				if ( failed !== false || allReady( job.dependencies ) ) {
					jobs.splice( i, 1 );
					i -= 1;
					try {
						if ( failed !== false && job.error ) {
							job.error( new Error( 'Failed dependency: ' + failed ), job.dependencies );
						} else if ( failed === false && job.ready ) {
							job.ready();
						}
					} catch ( e ) {
						// A user-defined callback raised an exception.
						// Swallow it to protect our state machine!
						mw.trackError( {
							exception: e,
							source: 'load-callback'
						} );
					}
					didPropagate = true;
				}
			}
		}

		willPropagate = false;
	}

	/**
	 * Update a module's state in the registry and make sure any necessary
	 * propagation will occur, by adding a (debounced) call to doPropagation().
	 * See #doPropagation for more about propagation.
	 * See #registry for more about how states are used.
	 *
	 * @private
	 * @param {string} module
	 * @param {string} state
	 */
	function setAndPropagate( module, state ) {
		registry[ module ].state = state;
		if ( state === 'ready' ) {
			// Queue to later be synced to the local module store.
			store.add( module );
		} else if ( state === 'error' || state === 'missing' ) {
			errorModules.push( module );
		} else if ( state !== 'loaded' ) {
			// We only have something to do in doPropagation for the
			// 'loaded', 'ready', 'error', and 'missing' states.
			// Avoid scheduling and propagation cost for frequent and short-lived
			// transition states, such as 'loading' and 'executing'.
			return;
		}
		if ( willPropagate ) {
			// Already scheduled, or, we're already in a doPropagation stack.
			return;
		}
		willPropagate = true;
		// Yield for two reasons:
		// * Allow successive calls to mw.loader.impl() from the same
		//   load.php response, or from the same asyncEval() to be in the
		//   propagation batch.
		// * Allow the browser to breathe between the reception of
		//   module source code and the execution of it.
		//
		// Use a high priority because the user may be waiting for interactions
		// to start being possible. But, first provide a moment (up to 'timeout')
		// for native input event handling (e.g. scrolling/typing/clicking).
		mw.requestIdleCallback( doPropagation, { timeout: 1 } );
	}

	/**
	 * Resolve dependencies and detect circular references.
	 *
	 * @private
	 * @param {string} module Name of the top-level module whose dependencies shall be
	 *  resolved and sorted.
	 * @param {Array} resolved Returns a topological sort of the given module and its
	 *  dependencies, such that later modules depend on earlier modules. The array
	 *  contains the module names. If the array contains already some module names,
	 *  this function appends its result to the pre-existing array.
	 * @param {Set} [unresolved] Used to detect loops in the dependency graph.
	 * @throws {Error} If an unknown module or a circular dependency is encountered
	 */
	function sortDependencies( module, resolved, unresolved ) {
		if ( !( module in registry ) ) {
			throw new Error( 'Unknown module: ' + module );
		}

		if ( typeof registry[ module ].skip === 'string' ) {
			// eslint-disable-next-line no-new-func
			var skip = ( new Function( registry[ module ].skip )() );
			registry[ module ].skip = !!skip;
			if ( skip ) {
				registry[ module ].dependencies = [];
				setAndPropagate( module, 'ready' );
				return;
			}
		}

		// Create unresolved if not passed in
		if ( !unresolved ) {
			unresolved = new Set();
		}

		// Track down dependencies
		var deps = registry[ module ].dependencies;
		unresolved.add( module );
		for ( var i = 0; i < deps.length; i++ ) {
			if ( resolved.indexOf( deps[ i ] ) === -1 ) {
				if ( unresolved.has( deps[ i ] ) ) {
					throw new Error(
						'Circular reference detected: ' + module + ' -> ' + deps[ i ]
					);
				}

				sortDependencies( deps[ i ], resolved, unresolved );
			}
		}

		resolved.push( module );
	}

	/**
	 * Get names of module that a module depends on, in their proper dependency order.
	 *
	 * @private
	 * @param {string[]} modules Array of string module names
	 * @return {Array} List of dependencies, including 'module'.
	 * @throws {Error} If an unregistered module or a dependency loop is encountered
	 */
	function resolve( modules ) {
		// Always load base modules
		var resolved = baseModules.slice();
		for ( var i = 0; i < modules.length; i++ ) {
			sortDependencies( modules[ i ], resolved );
		}
		return resolved;
	}

	/**
	 * Like #resolve(), except it will silently ignore modules that
	 * are missing or have missing dependencies.
	 *
	 * @private
	 * @param {string[]} modules Array of string module names
	 * @return {Array} List of dependencies.
	 */
	function resolveStubbornly( modules ) {
		// Always load base modules
		var resolved = baseModules.slice();
		for ( var i = 0; i < modules.length; i++ ) {
			var saved = resolved.slice();
			try {
				sortDependencies( modules[ i ], resolved );
			} catch ( err ) {
				resolved = saved;
				// This module is not currently known, or has invalid dependencies.
				//
				// Most likely due to a cached reference after the module was
				// removed, otherwise made redundant, or omitted from the registry
				// by the ResourceLoader "target" system.
				//
				// These errors can be common, e.g. queuing an unavailable module
				// unconditionally from the server-side is OK and should fail gracefully.
				mw.log.warn( 'Skipped unavailable module ' + modules[ i ] );

				// Do not track this error as an exception when the module:
				// - Is valid, but gracefully filtered out by target system.
				// - Was recently valid, but is still referenced in stale cache.
				//
				// Basically the only reason to track this as exception is when the error
				// was circular or invalid dependencies. What the above scenarios have in
				// common is that they don't register the module client-side.
				if ( modules[ i ] in registry ) {
					mw.trackError( {
						exception: err,
						source: 'resolve'
					} );
				}
			}
		}
		return resolved;
	}

	/**
	 * Resolve a relative file path.
	 *
	 * For example, resolveRelativePath( '../foo.js', 'resources/src/bar/bar.js' )
	 * returns 'resources/src/foo.js'.
	 *
	 * @private
	 * @param {string} relativePath Relative file path, starting with ./ or ../
	 * @param {string} basePath Path of the file (not directory) relativePath is relative to
	 * @return {string|null} Resolved path, or null if relativePath does not start with ./ or ../
	 */
	function resolveRelativePath( relativePath, basePath ) {

		var relParts = relativePath.match( /^((?:\.\.?\/)+)(.*)$/ );
		if ( !relParts ) {
			return null;
		}

		var baseDirParts = basePath.split( '/' );
		// basePath looks like 'foo/bar/baz.js', so baseDirParts looks like [ 'foo', 'bar, 'baz.js' ]
		// Remove the file component at the end, so that we are left with only the directory path
		baseDirParts.pop();

		var prefixes = relParts[ 1 ].split( '/' );
		// relParts[ 1 ] looks like '../../', so prefixes looks like [ '..', '..', '' ]
		// Remove the empty element at the end
		prefixes.pop();

		// For every ../ in the path prefix, remove one directory level from baseDirParts
		var prefix;
		var reachedRoot = false;
		while ( ( prefix = prefixes.pop() ) !== undefined ) {
			if ( prefix === '..' ) {
				// Once we reach the package's base dir, preserve all remaining "..".
				reachedRoot = !baseDirParts.length || reachedRoot;
				if ( !reachedRoot ) {
					baseDirParts.pop();
				} else {
					baseDirParts.push( prefix );
				}
			}
		}

		// If there's anything left of the base path, prepend it to the file path
		return ( baseDirParts.length ? baseDirParts.join( '/' ) + '/' : '' ) + relParts[ 2 ];
	}

	/**
	 * Make a require() function scoped to a package file
	 *
	 * @private
	 * @param {Object} moduleObj Module object from the registry
	 * @param {string} basePath Path of the file this is scoped to. Used for relative paths.
	 * @return {Function}
	 */
	function makeRequireFunction( moduleObj, basePath ) {
		return function require( moduleName ) {
			var fileName = resolveRelativePath( moduleName, basePath );
			if ( fileName === null ) {
				// Not a relative path, so it's either a module name or,
				// (if in test mode) a private file imported from another module.
				return mw.loader.require( moduleName );
			}

			if ( hasOwn.call( moduleObj.packageExports, fileName ) ) {
				// File has already been executed, return the cached result
				return moduleObj.packageExports[ fileName ];
			}

			var scriptFiles = moduleObj.script.files;
			if ( !hasOwn.call( scriptFiles, fileName ) ) {
				throw new Error( 'Cannot require undefined file ' + fileName );
			}

			var result,
				fileContent = scriptFiles[ fileName ];
			if ( typeof fileContent === 'function' ) {
				var moduleParam = { exports: {} };
				fileContent( makeRequireFunction( moduleObj, fileName ), moduleParam, moduleParam.exports );
				result = moduleParam.exports;
			} else {
				// fileContent is raw data (such as a JSON object), just pass it through
				result = fileContent;
			}
			moduleObj.packageExports[ fileName ] = result;
			return result;
		};
	}

	/**
	 * Load and execute a script.
	 *
	 * @private
	 * @param {string} src URL to script, will be used as the src attribute in the script tag
	 * @param {Function} [callback] Callback to run after request resolution
	 * @param {string[]} [modules] List of modules being requested, for state to be marked as error
	 * in case the script fails to load
	 * @return {HTMLElement}
	 */
	function addScript( src, callback, modules ) {
		// Use a <script> element rather than XHR. Using XHR changes the request
		// headers (potentially missing a cache hit), and reduces caching in general
		// since browsers cache XHR much less (if at all). And XHR means we retrieve
		// text, so we'd need to eval, which then messes up line numbers.
		// The drawback is that <script> does not offer progress events, feedback is
		// only given after downloading, parsing, and execution have completed.
		var script = document.createElement( 'script' );
		script.src = src;
		function onComplete() {
			if ( script.parentNode ) {
				script.parentNode.removeChild( script );
			}
			if ( callback ) {
				callback();
				callback = null;
			}
		}
		script.onload = onComplete;
		script.onerror = function () {
			onComplete();
			if ( modules ) {
				for ( var i = 0; i < modules.length; i++ ) {
					setAndPropagate( modules[ i ], 'error' );
				}
			}
		};
		document.head.appendChild( script );
		return script;
	}

	/**
	 * Queue the loading and execution of a script for a particular module.
	 *
	 * This does for legacy debug mode what runScript() does for production.
	 *
	 * @private
	 * @param {string} src URL of the script
	 * @param {string} moduleName Name of currently executing module
	 * @param {Function} callback Callback to run after addScript() resolution
	 */
	function queueModuleScript( src, moduleName, callback ) {
		pendingRequests.push( function () {
			// Keep in sync with execute()/runScript().
			if ( moduleName !== 'jquery' ) {
				window.require = mw.loader.require;
				window.module = registry[ moduleName ].module;
			}
			addScript( src, function () {
				// 'module.exports' should not persist after the file is executed to
				// avoid leakage to unrelated code. 'require' should be kept, however,
				// as asynchronous access to 'require' is allowed and expected. (T144879)
				delete window.module;
				callback();
				// Start the next one (if any)
				if ( pendingRequests[ 0 ] ) {
					pendingRequests.shift()();
				} else {
					handlingPendingRequests = false;
				}
			} );
		} );
		if ( !handlingPendingRequests && pendingRequests[ 0 ] ) {
			handlingPendingRequests = true;
			pendingRequests.shift()();
		}
	}

	/**
	 * Utility function for execute()
	 *
	 * @ignore
	 * @param {string} url URL
	 * @param {string} [media] Media attribute
	 * @param {Node|null} [nextNode]
	 * @return {HTMLElement}
	 */
	function addLink( url, media, nextNode ) {
		var el = document.createElement( 'link' );

		el.rel = 'stylesheet';
		if ( media ) {
			el.media = media;
		}
		// If you end up here from an IE exception "SCRIPT: Invalid property value.",
		// see #addEmbeddedCSS, T33676, T43331, and T49277 for details.
		el.href = url;

		addToHead( el, nextNode );
		return el;
	}

	/**
	 * Evaluate in the global scope.
	 *
	 * This is used by MediaWiki user scripts, where it is (for example)
	 * important that `var` makes a global variable.
	 *
	 * @private
	 * @param {string} code JavaScript code
	 */
	function globalEval( code ) {
		var script = document.createElement( 'script' );
		script.text = code;
		document.head.appendChild( script );
		script.parentNode.removeChild( script );
	}

	/**
	 * Evaluate JS code using indirect eval().
	 *
	 * This is used by mw.loader.store. It is important that we protect the
	 * integrity of mw.loader's private variables (from accidental clashes
	 * or re-assignment), which means we can't use regular `eval()`.
	 *
	 * Optimization: This exists separately from globalEval(), because that
	 * involves slow DOM overhead.
	 *
	 * @private
	 * @param {string} code JavaScript code
	 */
	function indirectEval( code ) {
		// See http://perfectionkills.com/global-eval-what-are-the-options/
		// for an explanation of this syntax.
		// eslint-disable-next-line no-eval
		( 1, eval )( code );
	}

	/**
	 * Add one or more modules to the module load queue.
	 *
	 * See also #work().
	 *
	 * @private
	 * @param {string[]} dependencies Array of module names in the registry
	 * @param {Function} [ready] Callback to execute when all dependencies are ready
	 * @param {Function} [error] Callback to execute when any dependency fails
	 */
	function enqueue( dependencies, ready, error ) {
		if ( allReady( dependencies ) ) {
			// Run ready immediately
			if ( ready ) {
				ready();
			}
			return;
		}

		var failed = anyFailed( dependencies );
		if ( failed !== false ) {
			if ( error ) {
				// Execute error immediately if any dependencies have errors
				error(
					new Error( 'Dependency ' + failed + ' failed to load' ),
					dependencies
				);
			}
			return;
		}

		// Not all dependencies are ready, add to the load queue...

		// Add ready and error callbacks if they were given
		if ( ready || error ) {
			jobs.push( {
				// Narrow down the list to modules that are worth waiting for
				dependencies: dependencies.filter( function ( module ) {
					var state = registry[ module ].state;
					return state === 'registered' || state === 'loaded' || state === 'loading' || state === 'executing';
				} ),
				ready: ready,
				error: error
			} );
		}

		dependencies.forEach( function ( module ) {
			// Only queue modules that are still in the initial 'registered' state
			// (e.g. not ones already loading or loaded etc.).
			if ( registry[ module ].state === 'registered' && queue.indexOf( module ) === -1 ) {
				queue.push( module );
			}
		} );

		mw.loader.work();
	}

	/**
	 * Executes a loaded module, making it ready to use
	 *
	 * @private
	 * @param {string} module Module name to execute
	 */
	function execute( module ) {
		if ( registry[ module ].state !== 'loaded' ) {
			throw new Error( 'Module in state "' + registry[ module ].state + '" may not execute: ' + module );
		}

		registry[ module ].state = 'executing';
		

		var runScript = function () {
			
			var script = registry[ module ].script;
			var markModuleReady = function () {
				
				setAndPropagate( module, 'ready' );
			};
			var nestedAddScript = function ( arr, offset ) {
				// Recursively call queueModuleScript() in its own callback
				// for each element of arr.
				if ( offset >= arr.length ) {
					// We're at the end of the array
					markModuleReady();
					return;
				}

				queueModuleScript( arr[ offset ], module, function () {
					nestedAddScript( arr, offset + 1 );
				} );
			};

			try {
				if ( Array.isArray( script ) ) {
					nestedAddScript( script, 0 );
				} else if ( typeof script === 'function' ) {
					// Keep in sync with queueModuleScript() for debug mode
					if ( module === 'jquery' ) {
						// This is a special case for when 'jquery' itself is being loaded.
						// - The standard jquery.js distribution does not set `window.jQuery`
						//   in CommonJS-compatible environments (Node.js, AMD, RequireJS, etc.).
						// - MediaWiki's 'jquery' module also bundles jquery.migrate.js, which
						//   in a CommonJS-compatible environment, will use require('jquery'),
						//   but that can't work when we're still inside that module.
						script();
					} else {
						// Pass jQuery twice so that the signature of the closure which wraps
						// the script can bind both '$' and 'jQuery'.
						script( window.$, window.$, mw.loader.require, registry[ module ].module );
					}
					markModuleReady();
				} else if ( typeof script === 'object' && script !== null ) {
					var mainScript = script.files[ script.main ];
					if ( typeof mainScript !== 'function' ) {
						throw new Error( 'Main file in module ' + module + ' must be a function' );
					}
					// jQuery parameters are not passed for multi-file modules
					mainScript(
						makeRequireFunction( registry[ module ], script.main ),
						registry[ module ].module,
						registry[ module ].module.exports
					);
					markModuleReady();
				} else if ( typeof script === 'string' ) {
					// Site and user modules are legacy scripts that run in the global scope.
					// This is transported as a string instead of a function to avoid needing
					// to use string manipulation to undo the function wrapper.
					globalEval( script );
					markModuleReady();

				} else {
					// Module without script
					markModuleReady();
				}
			} catch ( e ) {
				// Use mw.trackError instead of mw.log because these errors are common in production mode
				// (e.g. undefined variable), and mw.log is only enabled in debug mode.
				setAndPropagate( module, 'error' );
				
				mw.trackError( {
					exception: e,
					module: module,
					source: 'module-execute'
				} );
			}
		};

		// Emit deprecation warnings
		if ( registry[ module ].deprecationWarning ) {
			mw.log.warn( registry[ module ].deprecationWarning );
		}

		// Add localizations to message system
		if ( registry[ module ].messages ) {
			mw.messages.set( registry[ module ].messages );
		}

		// Initialise templates
		if ( registry[ module ].templates ) {
			mw.templates.set( module, registry[ module ].templates );
		}

		// Adding of stylesheets is asynchronous via addEmbeddedCSS().
		// The below function uses a counting semaphore to make sure we don't call
		// runScript() until after this module's stylesheets have been inserted
		// into the DOM.
		var cssPending = 0;
		var cssHandle = function () {
			// Increase semaphore, when creating a callback for addEmbeddedCSS.
			cssPending++;
			return function () {
				// Decrease semaphore, when said callback is invoked.
				cssPending--;
				if ( cssPending === 0 ) {
					// Paranoia:
					// This callback is exposed to addEmbeddedCSS, which is outside the execute()
					// function and is not concerned with state-machine integrity. In turn,
					// addEmbeddedCSS() actually exposes stuff further via requestAnimationFrame.
					// If increment and decrement callbacks happen in the wrong order, or start
					// again afterwards, then this branch could be reached multiple times.
					// To protect the integrity of the state-machine, prevent that from happening
					// by making runScript() cannot be called more than once.  We store a private
					// reference when we first reach this branch, then deference the original, and
					// call our reference to it.
					var runScriptCopy = runScript;
					runScript = undefined;
					runScriptCopy();
				}
			};
		};

		// Process styles (see also mw.loader.impl)
		// * { "css": [css, ..] }
		// * { "url": { <media>: [url, ..] } }
		var style = registry[ module ].style;
		if ( style ) {
			// Array of CSS strings under key 'css'
			// { "css": [css, ..] }
			if ( 'css' in style ) {
				for ( var i = 0; i < style.css.length; i++ ) {
					addEmbeddedCSS( style.css[ i ], cssHandle() );
				}
			}

			// Plain object with array of urls under a media-type key
			// { "url": { <media>: [url, ..] } }
			if ( 'url' in style ) {
				for ( var media in style.url ) {
					var urls = style.url[ media ];
					for ( var j = 0; j < urls.length; j++ ) {
						addLink( urls[ j ], media, marker );
					}
				}
			}
		}

		// End profiling of execute()-self before we call runScript(),
		// which we want to measure separately without overlap.
		

		if ( module === 'user' ) {
			// Implicit dependency on the site module. Not a real dependency because it should
			// run after 'site' regardless of whether it succeeds or fails.
			// Note: This is a simplified version of mw.loader.using(), inlined here because
			// mw.loader.using() is part of mediawiki.base (depends on jQuery; T192623).
			var siteDeps;
			var siteDepErr;
			try {
				siteDeps = resolve( [ 'site' ] );
			} catch ( e ) {
				siteDepErr = e;
				runScript();
			}
			if ( !siteDepErr ) {
				enqueue( siteDeps, runScript, runScript );
			}
		} else if ( cssPending === 0 ) {
			// Regular module without styles
			runScript();
		}
		// else: runScript will get called via cssHandle()
	}

	function sortQuery( o ) {
		var sorted = {};
		var list = [];

		for ( var key in o ) {
			list.push( key );
		}
		list.sort();
		for ( var i = 0; i < list.length; i++ ) {
			sorted[ list[ i ] ] = o[ list[ i ] ];
		}
		return sorted;
	}

	/**
	 * Converts a module map of the form `{ foo: [ 'bar', 'baz' ], bar: [ 'baz, 'quux' ] }`
	 * to a query string of the form `foo.bar,baz|bar.baz,quux`.
	 *
	 * See `ResourceLoader::makePackedModulesString()` in PHP, of which this is a port.
	 * On the server, unpacking is done by `ResourceLoader::expandModuleNames()`.
	 *
	 * Note: This is only half of the logic, the other half has to be in #batchRequest(),
	 * because its implementation needs to keep track of potential string size in order
	 * to decide when to split the requests due to url size.
	 *
	 * @typedef {Object} ModuleString
	 * @property {string} str Module query string
	 * @property {Array} list List of module names in matching order
	 *
	 * @private
	 * @param {Object} moduleMap Module map
	 * @return {ModuleString}
	 */
	function buildModulesString( moduleMap ) {
		var str = [];
		var list = [];
		var p;

		function restore( suffix ) {
			return p + suffix;
		}

		for ( var prefix in moduleMap ) {
			p = prefix === '' ? '' : prefix + '.';
			str.push( p + moduleMap[ prefix ].join( ',' ) );
			list.push.apply( list, moduleMap[ prefix ].map( restore ) );
		}
		return {
			str: str.join( '|' ),
			list: list
		};
	}

	/**
	 * @private
	 * @param {Object} params Map of parameter names to values
	 * @return {string}
	 */
	function makeQueryString( params ) {
		// Optimisation: This is a fairly hot code path with batchRequest() loops.
		// Avoid overhead from Object.keys and Array.forEach.
		// String concatenation is faster than array pushing and joining, see
		// https://phabricator.wikimedia.org/P19931
		var str = '';
		for ( var key in params ) {
			// Parameters are separated by &, added before all parameters other than
			// the first
			str += ( str ? '&' : '' ) + encodeURIComponent( key ) + '=' +
				encodeURIComponent( params[ key ] );
		}
		return str;
	}

	/**
	 * Create network requests for a batch of modules.
	 *
	 * This is an internal method for #work(). This must not be called directly
	 * unless the modules are already registered, and no request is in progress,
	 * and the module state has already been set to `loading`.
	 *
	 * @private
	 * @param {string[]} batch
	 */
	function batchRequest( batch ) {
		if ( !batch.length ) {
			return;
		}

		var sourceLoadScript, currReqBase, moduleMap;

		/**
		 * Start the currently drafted request to the server.
		 *
		 * @ignore
		 */
		function doRequest() {
			// Optimisation: Inherit (Object.create), not copy ($.extend)
			var query = Object.create( currReqBase ),
				packed = buildModulesString( moduleMap );
			query.modules = packed.str;
			// The packing logic can change the effective order, even if the input was
			// sorted. As such, the call to getCombinedVersion() must use this
			// effective order to ensure that the combined version will match the hash
			// expected by the server based on combining versions from the module
			// query string in-order. (T188076)
			query.version = getCombinedVersion( packed.list );
			query = sortQuery( query );
			addScript( sourceLoadScript + '?' + makeQueryString( query ), null, packed.list );
		}

		// Always order modules alphabetically to help reduce cache
		// misses for otherwise identical content.
		batch.sort();

		// Query parameters common to all requests
		var reqBase = {
    "lang": "en-gb",
    "skin": "vector",
    "debug": "1"
};

		// Split module list by source and by group.
		var splits = Object.create( null );
		for ( var b = 0; b < batch.length; b++ ) {
			var bSource = registry[ batch[ b ] ].source;
			var bGroup = registry[ batch[ b ] ].group;
			if ( !splits[ bSource ] ) {
				splits[ bSource ] = Object.create( null );
			}
			if ( !splits[ bSource ][ bGroup ] ) {
				splits[ bSource ][ bGroup ] = [];
			}
			splits[ bSource ][ bGroup ].push( batch[ b ] );
		}

		for ( var source in splits ) {
			sourceLoadScript = sources[ source ];

			for ( var group in splits[ source ] ) {

				// Cache access to currently selected list of
				// modules for this group from this source.
				var modules = splits[ source ][ group ];

				// Query parameters common to requests for this module group
				// Optimisation: Inherit (Object.create), not copy ($.extend)
				currReqBase = Object.create( reqBase );
				// User modules require a user name in the query string.
				if ( group === 0 && mw.config.get( 'wgUserName' ) !== null ) {
					currReqBase.user = mw.config.get( 'wgUserName' );
				}

				// In addition to currReqBase, doRequest() will also add 'modules' and 'version'.
				// > '&modules='.length === 9
				// > '&version=12345'.length === 14
				// > 9 + 14 = 23
				var currReqBaseLength = makeQueryString( currReqBase ).length + 23;

				// We may need to split up the request to honor the query string length limit,
				// so build it piece by piece. `length` does not include the characters from
				// the request base, see below
				var length = 0;
				moduleMap = Object.create( null ); // { prefix: [ suffixes ] }

				for ( var i = 0; i < modules.length; i++ ) {
					// Determine how many bytes this module would add to the query string
					var lastDotIndex = modules[ i ].lastIndexOf( '.' ),
						prefix = modules[ i ].slice( 0, Math.max( 0, lastDotIndex ) ),
						suffix = modules[ i ].slice( lastDotIndex + 1 ),
						bytesAdded = moduleMap[ prefix ] ?
							suffix.length + 3 : // '%2C'.length == 3
							modules[ i ].length + 3; // '%7C'.length == 3

					// If the url would become too long, create a new one, but don't create empty requests.
					// The value of `length` only reflects the request-specific bytes relating to the
					// accumulated entries in moduleMap so far. It does not include the base length,
					// which we account for separately with `currReqBaseLength` so that length is 0
					// when moduleMap is empty.
					if ( length && length + currReqBaseLength + bytesAdded > mw.loader.maxQueryLength ) {
						// Dispatch what we've got...
						doRequest();
						// .. and start preparing a new request.
						length = 0;
						moduleMap = Object.create( null );
					}
					if ( !moduleMap[ prefix ] ) {
						moduleMap[ prefix ] = [];
					}
					length += bytesAdded;
					moduleMap[ prefix ].push( suffix );
				}
				// Optimization: Skip `length` check.
				// moduleMap will contain at least one module here. The loop above leaves the last module
				// undispatched (and maybe some before it), so for moduleMap to be empty here, there must
				// have been no modules to iterate in the current group to start with, but we only create
				// a group in `splits` when the first module in the group is seen, so there are always
				// modules in the group when this code is reached.
				doRequest();
			}
		}
	}

	/**
	 * @private
	 * @param {string[]} implementations Array containing pieces of JavaScript code in the
	 *  form of calls to mw.loader#impl().
	 * @param {Function} cb Callback in case of failure
	 * @param {Error} cb.err
	 * @param {number} [offset] Integer offset into implementations to start at
	 */
	function asyncEval( implementations, cb, offset ) {
		if ( !implementations.length ) {
			return;
		}
		offset = offset || 0;
		mw.requestIdleCallback( function ( deadline ) {
			asyncEvalTask( deadline, implementations, cb, offset );
		} );
	}

	/**
	 * Idle callback for asyncEval
	 *
	 * @private
	 * @param {IdleDeadline} deadline
	 * @param {string[]} implementations
	 * @param {Function} cb
	 * @param {Error} cb.err
	 * @param {number} offset
	 */
	function asyncEvalTask( deadline, implementations, cb, offset ) {
		for ( var i = offset; i < implementations.length; i++ ) {
			if ( deadline.timeRemaining() <= 0 ) {
				asyncEval( implementations, cb, i );
				return;
			}
			try {
				indirectEval( implementations[ i ] );
			} catch ( err ) {
				cb( err );
			}
		}
	}

	/**
	 * Make a versioned key for a specific module.
	 *
	 * @private
	 * @param {string} module Module name
	 * @return {string|null} Module key in format '`[name]@[version]`',
	 *  or null if the module does not exist
	 */
	function getModuleKey( module ) {
		return module in registry ? ( module + '@' + registry[ module ].version ) : null;
	}

	/**
	 * @private
	 * @param {string} key Module name or '`[name]@[version]`'
	 * @return {Object}
	 */
	function splitModuleKey( key ) {
		// Module names may contain '@' but version strings may not, so the last '@' is the delimiter
		var index = key.lastIndexOf( '@' );
		// If the key doesn't contain '@' or starts with it, the whole thing is the module name
		if ( index === -1 || index === 0 ) {
			return {
				name: key,
				version: ''
			};
		}
		return {
			name: key.slice( 0, index ),
			version: key.slice( index + 1 )
		};
	}

	/**
	 * @private
	 * @param {string} module
	 * @param {string} [version]
	 * @param {string[]} [dependencies]
	 * @param {string} [group]
	 * @param {string} [source]
	 * @param {string} [skip]
	 */
	function registerOne( module, version, dependencies, group, source, skip ) {
		if ( module in registry ) {
			throw new Error( 'module already registered: ' + module );
		}

		registry[ module ] = {
			// Exposed to execute() for mw.loader.impl() closures.
			// Import happens via require().
			module: {
				exports: {}
			},
			// module.export objects for each package file inside this module
			packageExports: {},
			version: version || '',
			dependencies: dependencies || [],
			group: typeof group === 'undefined' ? null : group,
			source: typeof source === 'string' ? source : 'local',
			state: 'registered',
			skip: typeof skip === 'string' ? skip : null
		};
	}

	/* Public Members */

	mw.loader = {
		/**
		 * The module registry is exposed as an aid for debugging and inspecting page
		 * state; it is not a public interface for modifying the registry.
		 *
		 * @see #registry
		 * @property {Object}
		 * @private
		 */
		moduleRegistry: registry,

		/**
		 * Exposed for testing and debugging only.
		 *
		 * @see #batchRequest
		 * @property {number}
		 * @private
		 */
		maxQueryLength: 2000,

		addStyleTag: newStyleTag,

		// Exposed for internal use only. Documented as @private.
		addScriptTag: addScript,
		// Exposed for internal use only. Documented as @private.
		addLinkTag: addLink,

		// Exposed for internal use only. Documented as @private.
		enqueue: enqueue,

		// Exposed for internal use only. Documented as @private.
		resolve: resolve,

		/**
		 * Start loading of all queued module dependencies.
		 *
		 * @private
		 */
		work: function () {
			store.init();

			var q = queue.length,
				storedImplementations = [],
				storedNames = [],
				requestNames = [],
				batch = new Set();

			// Iterate the list of requested modules, and do one of three things:
			// - 1) Nothing (if already loaded or being loaded).
			// - 2) Eval the cached implementation from the module store.
			// - 3) Request from network.
			while ( q-- ) {
				var module = queue[ q ];
				// Only consider modules which are the initial 'registered' state,
				// and ignore duplicates
				if ( mw.loader.getState( module ) === 'registered' &&
					!batch.has( module )
				) {
					// Progress the state machine
					registry[ module ].state = 'loading';
					batch.add( module );

					var implementation = store.get( module );
					if ( implementation ) {
						// Module store enabled and contains this module/version
						storedImplementations.push( implementation );
						storedNames.push( module );
					} else {
						// Module store disabled or doesn't have this module/version
						requestNames.push( module );
					}
				}
			}

			// Now that the queue has been processed into a batch, clear the queue.
			// This MUST happen before we initiate any eval or network request. Otherwise,
			// it is possible for a cached script to instantly trigger the same work queue
			// again; all before we've cleared it causing each request to include modules
			// which are already loaded.
			queue = [];

			asyncEval( storedImplementations, function ( err ) {
				// Not good, the cached mw.loader.impl calls failed! This should
				// never happen, barring ResourceLoader bugs, browser bugs and PEBKACs.
				// Depending on how corrupt the string is, it is likely that some
				// modules' impl() succeeded while the ones after the error will
				// never run and leave their modules in the 'loading' state forever.
				store.stats.failed++;

				// Since this is an error not caused by an individual module but by
				// something that infected the implement call itself, don't take any
				// risks and clear everything in this cache.
				store.clear();

				mw.trackError( {
					exception: err,
					source: 'store-eval'
				} );
				// For any failed ones, fallback to requesting from network
				var failed = storedNames.filter( function ( name ) {
					return registry[ name ].state === 'loading';
				} );
				batchRequest( failed );
			} );

			batchRequest( requestNames );
		},

		/**
		 * Register a source.
		 *
		 * The #work() method will use this information to split up requests by source.
		 *
		 * @example
		 * mw.loader.addSource( { mediawikiwiki: 'https://www.mediawiki.org/w/load.php' } );
		 *
		 * @private
		 * @param {Object} ids An object mapping ids to load.php end point urls
		 * @throws {Error} If source id is already registered
		 */
		addSource: function ( ids ) {
			for ( var id in ids ) {
				if ( id in sources ) {
					throw new Error( 'source already registered: ' + id );
				}
				sources[ id ] = ids[ id ];
			}
		},

		/**
		 * Register a module, letting the system know about it and its properties.
		 *
		 * The startup module calls this method.
		 *
		 * When using multiple module registration by passing an array, dependencies that
		 * are specified as references to modules within the array will be resolved before
		 * the modules are registered.
		 *
		 * @param {string|Array} modules Module name or array of arrays, each containing
		 *  a list of arguments compatible with this method
		 * @param {string} [version] Module version hash (falls backs to empty string)
		 * @param {string[]} [dependencies] Array of module names on which this module depends.
		 * @param {string} [group=null] Group which the module is in
		 * @param {string} [source='local'] Name of the source
		 * @param {string} [skip=null] Script body of the skip function
		 * @private
		 */
		register: function ( modules ) {
			if ( typeof modules !== 'object' ) {
				registerOne.apply( null, arguments );
				return;
			}
			// Need to resolve indexed dependencies:
			// ResourceLoader uses an optimisation to save space which replaces module
			// names in dependency lists with the index of that module within the
			// array of module registration data if it exists. The benefit is a significant
			// reduction in the data size of the startup module. This loop changes
			// those dependency lists back to arrays of strings.
			function resolveIndex( dep ) {
				return typeof dep === 'number' ? modules[ dep ][ 0 ] : dep;
			}

			for ( var i = 0; i < modules.length; i++ ) {
				var deps = modules[ i ][ 2 ];
				if ( deps ) {
					for ( var j = 0; j < deps.length; j++ ) {
						deps[ j ] = resolveIndex( deps[ j ] );
					}
				}
				// Optimisation: Up to 55% faster.
				// Typically register() is called exactly once on a page, and with a batch.
				// See <https://gist.github.com/Krinkle/f06fdb3de62824c6c16f02a0e6ce0e66>
				// Benchmarks taught us that the code for adding an object to `registry`
				// should be in a function that has only one signature and does no arguments
				// manipulation.
				// JS semantics make it hard to optimise recursion to a different
				// signature of itself, hence we moved this out.
				registerOne.apply( null, modules[ i ] );
			}
		},

		/**
		 * Implement a module given the components of the module.
		 *
		 * See #impl for a full description of the parameters.
		 *
		 * Prior to MW 1.41, this was used internally, but now it is only kept
		 * for backwards compatibility.
		 *
		 * Does not support mw.loader.store caching.
		 *
		 * @param {string} module
		 * @param {Function|Array|string|Object} [script]
		 * @param {Object} [style]
		 * @param {Object} [messages] List of key/value pairs to be added to mw#messages.
		 * @param {Object} [templates] List of key/value pairs to be added to mw#templates.
		 * @param {string|null} [deprecationWarning] Deprecation warning if any
		 * @private
		 */
		implement: function ( module, script, style, messages, templates, deprecationWarning ) {
			var split = splitModuleKey( module ),
				name = split.name,
				version = split.version;

			// Automatically register module
			if ( !( name in registry ) ) {
				mw.loader.register( name );
			}
			// Check for duplicate implementation
			if ( registry[ name ].script !== undefined ) {
				throw new Error( 'module already implemented: ' + name );
			}
			registry[ name ].version = version;
			registry[ name ].declarator = null; // not supported
			registry[ name ].script = script;
			registry[ name ].style = style;
			registry[ name ].messages = messages;
			registry[ name ].templates = templates;
			registry[ name ].deprecationWarning = deprecationWarning;
			// The module may already have been marked as erroneous
			if ( registry[ name ].state !== 'error' && registry[ name ].state !== 'missing' ) {
				setAndPropagate( name, 'loaded' );
			}
		},

		/**
		 * Implement a module given a function which returns the components of the module
		 *
		 * @param {Function} declarator
		 *
		 * The declarator should return an array with the following keys:
		 *
		 *  - 0. {string} module Name of module and current module version. Formatted
		 *    as '`[name]@[version]`". This version should match the requested version
		 *    (from #batchRequest and #registry). This avoids race conditions (T117587).
		 *
		 *  - 1. {Function|Array|string|Object} [script] Module code. This can be a function,
		 *    a list of URLs to load via `<script src>`, a string for `globalEval()`, or an
		 *    object like {"files": {"foo.js":function, "bar.js": function, ...}, "main": "foo.js"}.
		 *    If an object is provided, the main file will be executed immediately, and the other
		 *    files will only be executed if loaded via require(). If a function or string is
		 *    provided, it will be executed/evaluated immediately. If an array is provided, all
		 *    URLs in the array will be loaded immediately, and executed as soon as they arrive.
		 *
		 *  - 2. {Object} [style] Should follow one of the following patterns:
		 *
		 *     { "css": [css, ..] }
		 *     { "url": { (media): [url, ..] } }
		 *
		 *    The reason css strings are not concatenated anymore is T33676. We now check
		 *    whether it's safe to extend the stylesheet.
		 *
		 *  - 3. {Object} [messages] List of key/value pairs to be added to mw#messages.
		 *  - 4. {Object} [templates] List of key/value pairs to be added to mw#templates.
		 *  - 5. {String|null} [deprecationWarning] Deprecation warning if any
		 *
		 * The declarator must not use any scope variables, since it will be serialized with
		 * Function.prototype.toString() and later restored and executed in the global scope.
		 *
		 * The elements are all optional except the name.
		 * @private
		 */
		impl: function ( declarator ) {
			var data = declarator(),
				module = data[ 0 ],
				script = data[ 1 ] || null,
				style = data[ 2 ] || null,
				messages = data[ 3 ] || null,
				templates = data[ 4 ] || null,
				deprecationWarning = data[ 5 ] || null,
				split = splitModuleKey( module ),
				name = split.name,
				version = split.version;

			// Automatically register module
			if ( !( name in registry ) ) {
				mw.loader.register( name );
			}
			// Check for duplicate implementation
			if ( registry[ name ].script !== undefined ) {
				throw new Error( 'module already implemented: ' + name );
			}
			// Without this reset, if there is a version mismatch between the
			// requested and received module version, then mw.loader.store would
			// cache the response under the requested key. Thus poisoning the cache
			// indefinitely with a stale value. (T117587)
			registry[ name ].version = version;
			// Attach components
			registry[ name ].declarator = declarator;
			registry[ name ].script = script;
			registry[ name ].style = style;
			registry[ name ].messages = messages;
			registry[ name ].templates = templates;
			registry[ name ].deprecationWarning = deprecationWarning;
			// The module may already have been marked as erroneous
			if ( registry[ name ].state !== 'error' && registry[ name ].state !== 'missing' ) {
				setAndPropagate( name, 'loaded' );
			}
		},

		/**
		 * Load an external script or one or more modules.
		 *
		 * This method takes a list of unrelated modules. Use cases:
		 *
		 * - A web page will be composed of many different widgets. These widgets independently
		 *   queue their ResourceLoader modules (`OutputPage::addModules()`). If any of them
		 *   have problems, or are no longer known (e.g. cached HTML), the other modules
		 *   should still be loaded.
		 * - This method is used for preloading, which must not throw. Later code that
		 *   calls #using() will handle the error.
		 *
		 * @param {string|Array} modules Either the name of a module, array of modules,
		 *  or a URL of an external script or style
		 * @param {string} [type='text/javascript'] MIME type to use if calling with a URL of an
		 *  external script or style; acceptable values are "text/css" and
		 *  "text/javascript"; if no type is provided, text/javascript is assumed.
		 * @throws {Error} If type is invalid
		 */
		load: function ( modules, type ) {

			if ( typeof modules === 'string' && /^(https?:)?\/?\//.test( modules ) ) {
				// Called with a url like so:
				// - "https://example.org/x.js"
				// - "http://example.org/x.js"
				// - "//example.org/x.js"
				// - "/x.js"
				if ( type === 'text/css' ) {
					addLink( modules );
				} else if ( type === 'text/javascript' || type === undefined ) {
					addScript( modules );
				} else {
					// Unknown type
					throw new Error( 'Invalid type ' + type );
				}
			} else {
				// One or more modules
				modules = typeof modules === 'string' ? [ modules ] : modules;
				// Resolve modules into a flat list for internal queuing.
				// This also filters out unknown modules and modules with
				// unknown dependencies, allowing the rest to continue. (T36853)
				// Omit ready and error parameters, we don't have callbacks
				enqueue( resolveStubbornly( modules ) );
			}
		},

		/**
		 * Change the state of one or more modules.
		 *
		 * @param {Object} states Object of module name/state pairs
		 * @private
		 */
		state: function ( states ) {
			for ( var module in states ) {
				if ( !( module in registry ) ) {
					mw.loader.register( module );
				}
				setAndPropagate( module, states[ module ] );
			}
		},

		/**
		 * Get the state of a module.
		 *
		 * Possible states for the public API:
		 *
		 * - `registered`: The module is available for loading but not yet requested.
		 * - `loading`, `loaded`, or `executing`: The module is currently being loaded.
		 * - `ready`: The module was successfully and fully loaded.
		 * - `error`: The module or one its dependencies has failed to load, e.g. due to
		 *    uncaught error from the module's script files.
		 * - `missing`: The module was requested but is not defined according to the server.
		 *
		 * Internal mw.loader state machine:
		 *
		 * - `registered`:
		 *    The module is known to the system but not yet required.
		 *    Meta data is stored by `register()`.
		 *    Calls to that method are generated server-side by StartupModule.
		 * - `loading`:
		 *    The module was required through mw.loader (either directly or as dependency of
		 *    another module). The client will fetch module contents from mw.loader.store
		 *    or from the server. The contents should later be received by `implement()`.
		 * - `loaded`:
		 *    The module has been received by `implement()`.
		 *    Once the module has no more dependencies in-flight, the module will be executed,
		 *    controlled via `setAndPropagate()` and `doPropagation()`.
		 * - `executing`:
		 *    The module is being executed (apply messages and stylesheets, execute scripts)
		 *    by `execute()`.
		 * - `ready`:
		 *    The module has been successfully executed.
		 * - `error`:
		 *    The module (or one of its dependencies) produced an uncaught error during execution.
		 * - `missing`:
		 *    The module was registered client-side and requested, but the server denied knowledge
		 *    of the module's existence.
		 *
		 * @param {string} module Name of module
		 * @return {string|null} The state, or null if the module (or its state) is not
		 *  in the registry.
		 */
		getState: function ( module ) {
			return module in registry ? registry[ module ].state : null;
		},

		/**
		 * Get the exported value of a module.
		 *
		 * This static method is publicly exposed for debugging purposes
		 * only and must not be used in production code. In production code,
		 * please use the dynamically provided `require()` function instead.
		 *
		 * In case of lazy-loaded modules via mw.loader#using(), the returned
		 * Promise provides the function, see #using() for examples.
		 *
		 * @private
		 * @since 1.27
		 * @param {string} moduleName Module name
		 * @return {any} Exported value
		 */
		require: function ( moduleName ) {
			var path;
			if ( window.QUnit ) {
				// Comply with Node specification
				// https://nodejs.org/docs/v20.1.0/api/modules.html#all-together
				//
				// > Interpret X as a combination of NAME and SUBPATH, where the NAME
				// > may have a "@scope/" prefix and the subpath begins with a slash (`/`).
				//
				// Regex inspired by Node [1], but simplified to suite our purposes
				// and split in two in order to keep the Regex Star Height under 2,
				// as per ESLint security/detect-unsafe-regex.
				//
				// These patterns match "@scope/module/dir/file.js" and "module/dir/file.js"
				// respectively. They must not match "module.name" or "@scope/module.name".
				//
				// [1] https://github.com/nodejs/node/blob/v20.1.0/lib/internal/modules/cjs/loader.js#L554-L560
				var paths = moduleName.startsWith( '@' ) ?
					/^(@[^/]+\/[^/]+)\/(.*)$/.exec( moduleName ) :
					// eslint-disable-next-line no-mixed-spaces-and-tabs
					        /^([^/]+)\/(.*)$/.exec( moduleName );
				if ( paths ) {
					moduleName = paths[ 1 ];
					path = paths[ 2 ];
				}
			}

			// Only ready modules can be required
			if ( mw.loader.getState( moduleName ) !== 'ready' ) {
				// Module may've forgotten to declare a dependency
				throw new Error( 'Module "' + moduleName + '" is not loaded' );
			}

			return path ?
				makeRequireFunction( registry[ moduleName ], '' )( './' + path ) :
				registry[ moduleName ].module.exports;
		}
	};

	var hasPendingFlush = false,
		hasPendingWrites = false;

	/**
	 * Actually update the store
	 *
	 * @see #requestUpdate
	 * @private
	 */
	function flushWrites() {
		// Process queued module names, serialise their contents to the in-memory store.
		while ( store.queue.length ) {
			store.set( store.queue.shift() );
		}

		// Optimization: Don't reserialize the entire store and rewrite localStorage,
		// if no module was added or changed.
		if ( hasPendingWrites ) {
			// Remove anything from the in-memory store that came from previous page
			// loads that no longer corresponds with current module names and versions.
			store.prune();

			try {
				// Replacing the content of the module store might fail if the new
				// contents would exceed the browser's localStorage size limit. To
				// avoid clogging the browser with stale data, always remove the old
				// value before attempting to store a new one.
				localStorage.removeItem( store.key );
				localStorage.setItem( store.key, JSON.stringify( {
					items: store.items,
					vary: store.vary,
					// Store with 1e7 ms accuracy (1e4 seconds, or ~ 2.7 hours),
					// which is enough for the purpose of expiring after ~ 30 days.
					asOf: Math.ceil( Date.now() / 1e7 )
				} ) );
			} catch ( e ) {
				mw.trackError( {
					exception: e,
					source: 'store-localstorage-update'
				} );
			}
		}

		// Let the next call to requestUpdate() create a new timer.
		hasPendingFlush = hasPendingWrites = false;
	}

	// We use a local variable `store` so that its easier to access, but also need to set
	// this in mw.loader so its exported - combine the two

	/**
	 * On browsers that implement the localStorage API, the module store serves as a
	 * smart complement to the browser cache. Unlike the browser cache, the module store
	 * can slice a concatenated response from ResourceLoader into its constituent
	 * modules and cache each of them separately, using each module's versioning scheme
	 * to determine when the cache should be invalidated.
	 *
	 * @private
	 * @singleton
	 * @class mw.loader.store
	 * @ignore
	 */
	mw.loader.store = store = {
		// Whether the store is in use on this page.
		enabled: null,

		// The contents of the store, mapping '[name]@[version]' keys
		// to module implementations.
		items: {},

		// Names of modules to be stored during the next update.
		// See add() and update().
		queue: [],

		// Cache hit stats
		stats: { hits: 0, misses: 0, expired: 0, failed: 0 },

		/**
		 * The localStorage key for the entire module store. The key references
		 * $wgDBname to prevent clashes between wikis which share a common host.
		 *
		 * @property {string}
		 */
		key: "MediaWikiModuleStore:en_osrswiki",

		/**
		 * A string containing various factors by which the module cache should vary.
		 *
		 * Defined by ResourceLoader\StartupModule::getStoreVary() in PHP.
		 *
		 * @property {string}
		 */
		vary: "vector:3:1:en-gb",

		/**
		 * Initialize the store.
		 *
		 * Retrieves store from localStorage and (if successfully retrieved) decoding
		 * the stored JSON value to a plain object.
		 */
		init: function () {
			// Init only once per page
			if ( this.enabled === null ) {
				this.enabled = false;
				if ( false ) {
					this.load();
				} else {
					// Clear any previous store to free up space. (T66721)
					this.clear();
				}

			}
		},

		/**
		 * Internal helper for init(). Separated for ease of testing.
		 */
		load: function () {
			// These are the scenarios to think about:
			//
			// 1. localStorage is disallowed by the browser.
			//    This means `localStorage.getItem` throws.
			//    The store stays disabled.
			//
			// 2. localStorage did not contain our store key.
			//    This usually means the browser has a cold cache for this site,
			//    and thus localStorage.getItem returns null.
			//    The store will be enabled, and `items` starts fresh.
			//
			// 3. localStorage contains parseable data, but it's not usable.
			//    This means the data is too old, or is not valid for mw.loader.store.vary
			//    (e.g. user switched skin or language).
			//    The store will be enabled, and `items` starts fresh.
			//
			// 4. localStorage contains invalid JSON data.
			//    This means the data was corrupted, and `JSON.parse` throws.
			//    The store will be enabled, and `items` starts fresh.
			//
			// 5. localStorage contains valid and usable JSON.
			//    This means we have a warm cache from a previous visit.
			//    The store will be enabled, and `items` starts with the stored data.

			try {
				var raw = localStorage.getItem( this.key );

				// If we make it here, localStorage is enabled and available.
				// The rest of the function may fail, but that only affects what we load from
				// the cache. We'll still enable the store to allow storing new modules.
				this.enabled = true;

				// If getItem returns null, JSON.parse() will cast to string and re-parse, still null.
				var data = JSON.parse( raw );
				if ( data &&
					data.vary === this.vary &&
					data.items &&
					// Only use if it's been less than 30 days since the data was written
					// 30 days = 2,592,000 s = 2,592,000,000 ms = ± 259e7 ms
					Date.now() < ( data.asOf * 1e7 ) + 259e7
				) {
					// The data is not corrupt, matches our vary context, and has not expired.
					this.items = data.items;
				}
			} catch ( e ) {
				// Ignore error from localStorage or JSON.parse.
				// Don't print any warning (T195647).
			}
		},

		/**
		 * Retrieve a module from the store and update cache hit stats.
		 *
		 * @param {string} module Module name
		 * @return {string|boolean} Module implementation or false if unavailable
		 */
		get: function ( module ) {
			if ( this.enabled ) {
				var key = getModuleKey( module );
				if ( key in this.items ) {
					this.stats.hits++;
					return this.items[ key ];
				}

				this.stats.misses++;
			}

			return false;
		},

		/**
		 * Queue the name of a module that the next update should consider storing.
		 *
		 * @since 1.32
		 * @param {string} module Module name
		 */
		add: function ( module ) {
			if ( this.enabled ) {
				this.queue.push( module );
				this.requestUpdate();
			}
		},

		/**
		 * Add the contents of the named module to the in-memory store.
		 *
		 * This method does not guarantee that the module will be stored.
		 * Inspection of the module's meta data and size will ultimately decide that.
		 *
		 * This method is considered internal to mw.loader.store and must only
		 * be called if the store is enabled.
		 *
		 * @private
		 * @param {string} module Module name
		 */
		set: function ( module ) {
			var descriptor = registry[ module ],
				key = getModuleKey( module );

			if (
				// Already stored a copy of this exact version
				key in this.items ||
				// Module failed to load
				!descriptor ||
				descriptor.state !== 'ready' ||
				// Unversioned, private, or site-/user-specific
				!descriptor.version ||
				descriptor.group === 1 ||
				descriptor.group === 0 ||
				// Legacy descriptor, registered with mw.loader.implement
				!descriptor.declarator
			) {
				// Decline to store
				return;
			}

			var script = String( descriptor.declarator );
			// Modules whose serialised form exceeds 100 kB won't be stored (T66721).
			if ( script.length > 1e5 ) {
				return;
			}

			var srcParts = [
				'mw.loader.impl(',
				script,
				');\n'
			];
			if ( true ) {
				srcParts.push( '// Saved in localStorage at ', ( new Date() ).toISOString(), '\n' );
				var sourceLoadScript = sources[ descriptor.source ];
				var query = Object.create( {
    "lang": "en-gb",
    "skin": "vector",
    "debug": "1"
} );
				query.modules = module;
				query.version = getCombinedVersion( [ module ] );
				query = sortQuery( query );
				srcParts.push(
					'//# sourceURL=',
					// Use absolute URL so that Firefox console stack trace links will work
					( new URL( sourceLoadScript, location ) ).href,
					'?',
					makeQueryString( query ),
					'\n'
				);

				query.sourcemap = '1';
				query = sortQuery( query );
				srcParts.push(
					'//# sourceMappingURL=',
					sourceLoadScript,
					'?',
					makeQueryString( query )
				);
			}
			this.items[ key ] = srcParts.join( '' );
			hasPendingWrites = true;
		},

		/**
		 * Iterate through the module store, removing any item that does not correspond
		 * (in name and version) to an item in the module registry.
		 */
		prune: function () {
			for ( var key in this.items ) {
				// key is in the form [name]@[version], slice to get just the name
				// to provide to getModuleKey, which will return a key in the same
				// form but with the latest version
				if ( getModuleKey( splitModuleKey( key ).name ) !== key ) {
					this.stats.expired++;
					delete this.items[ key ];
				}
			}
		},

		/**
		 * Clear the entire module store right now.
		 */
		clear: function () {
			this.items = {};
			try {
				localStorage.removeItem( this.key );
			} catch ( e ) {}
		},

		/**
		 * Request a sync of the in-memory store back to persisted localStorage.
		 *
		 * This function debounces updates. The debouncing logic should account
		 * for the following factors:
		 *
		 * - Writing to localStorage is an expensive operation that must not happen
		 *   during the critical path of initialising and executing module code.
		 *   Instead, it should happen at a later time after modules have been given
		 *   time and priority to do their thing first.
		 *
		 * - This method is called from mw.loader.store.add(), which will be called
		 *   hundreds of times on a typical page, including within the same call-stack
		 *   and eventloop-tick. This is because responses from load.php happen in
		 *   batches. As such, we want to allow all modules from the same load.php
		 *   response to be written to disk with a single flush, not many.
		 *
		 * - Repeatedly deleting and creating timers is non-trivial.
		 *
		 * - localStorage is shared by all pages from the same origin, if multiple
		 *   pages are loaded with different module sets, the possibility exists that
		 *   modules saved by one page will be clobbered by another. The impact of
		 *   this is minor, it merely causes a less efficient cache use, and the
		 *   problem would be corrected by subsequent page views.
		 *
		 * This method is considered internal to mw.loader.store and must only
		 * be called if the store is enabled.
		 *
		 * @private
		 * @method
		 */
		requestUpdate: function () {
			// On the first call to requestUpdate(), create a timer that
			// waits at least two seconds, then calls onTimeout.
			// The main purpose is to allow the current batch of load.php
			// responses to complete before we do anything. This batch can
			// trigger many hundreds of calls to requestUpdate().
			if ( !hasPendingFlush ) {
				hasPendingFlush = setTimeout(
					// Defer the actual write via requestIdleCallback
					function () {
						mw.requestIdleCallback( flushWrites );
					},
					2000
				);
			}
		}
	};
}() );
/* global mw */
mw.requestIdleCallbackInternal = function ( callback ) {
	setTimeout( function () {
		var start = mw.now();
		callback( {
			didTimeout: false,
			timeRemaining: function () {
				// Hard code a target maximum busy time of 50 milliseconds
				return Math.max( 0, 50 - ( mw.now() - start ) );
			}
		} );
	}, 1 );
};

/**
 * Schedule a deferred task to run in the background.
 *
 * This allows code to perform tasks in the main thread without impacting
 * time-critical operations such as animations and response to input events.
 *
 * Basic logic is as follows:
 *
 * - User input event should be acknowledged within 100ms per [RAIL][].
 * - Idle work should be grouped in blocks of upto 50ms so that enough time
 *   remains for the event handler to execute and any rendering to take place.
 * - Whenever a native event happens (e.g. user input), the deadline for any
 *   running idle callback drops to 0.
 * - As long as the deadline is non-zero, other callbacks pending may be
 *   executed in the same idle period.
 *
 * See also:
 *
 * - <https://developer.mozilla.org/en-US/docs/Web/API/Window/requestIdleCallback>
 * - <https://w3c.github.io/requestidlecallback/>
 * - <https://developers.google.com/web/updates/2015/08/using-requestidlecallback>
 *
 * [RAIL]: https://developers.google.com/web/fundamentals/performance/rail
 *
 * @memberof mw
 * @method
 * @param {Function} callback
 * @param {Object} [options]
 * @param {number} [options.timeout] If set, the callback will be scheduled for
 *  immediate execution after this amount of time (in milliseconds) if it didn't run
 *  by that time.
 */
mw.requestIdleCallback = window.requestIdleCallback ?
	// Bind because it throws TypeError if context is not window
	window.requestIdleCallback.bind( window ) :
	mw.requestIdleCallbackInternal;
// Note: Polyfill was previously disabled due to
// https://bugs.chromium.org/p/chromium/issues/detail?id=647870
// See also <http://codepen.io/Krinkle/full/XNGEvv>


	/**
	 * The $CODE placeholder is substituted in ResourceLoaderStartUpModule.php.
	 */
	( function () {
		/* global mw */
		var queue;

		mw.loader.addSource({
    "local": "/load.php"
});
mw.loader.register([
    [
        "site",
        "",
        [
            1
        ]
    ],
    [
        "site.styles",
        "",
        [],
        2
    ],
    [
        "filepage",
        ""
    ],
    [
        "user",
        "",
        [],
        0
    ],
    [
        "user.styles",
        "",
        [],
        0
    ],
    [
        "user.options",
        "",
        [],
        1
    ],
    [
        "mediawiki.skinning.interface",
        ""
    ],
    [
        "jquery.makeCollapsible.styles",
        ""
    ],
    [
        "mediawiki.skinning.content.parsoid",
        ""
    ],
    [
        "web2017-polyfills",
        "",
        [],
        null,
        null,
        "return 'IntersectionObserver' in window \u0026\u0026\n    typeof fetch === 'function' \u0026\u0026\n    // Ensure:\n    // - standards compliant URL\n    // - standards compliant URLSearchParams\n    // - URL#toJSON method (came later)\n    //\n    // Facts:\n    // - All browsers with URL also have URLSearchParams, don't need to check.\n    // - Safari \u003C= 7 and Chrome \u003C= 31 had a buggy URL implementations.\n    // - Firefox 29-43 had an incomplete URLSearchParams implementation. https://caniuse.com/urlsearchparams\n    // - URL#toJSON was released in Firefox 54, Safari 11, and Chrome 71. https://caniuse.com/mdn-api_url_tojson\n    //   Thus we don't need to check for buggy URL or incomplete URLSearchParams.\n    typeof URL === 'function' \u0026\u0026 'toJSON' in URL.prototype;\n"
    ],
    [
        "jquery",
        ""
    ],
    [
        "mediawiki.base",
        "",
        [
            10
        ]
    ],
    [
        "jquery.chosen",
        ""
    ],
    [
        "jquery.client",
        ""
    ],
    [
        "jquery.confirmable",
        "",
        [
            101
        ]
    ],
    [
        "jquery.highlightText",
        "",
        [
            75
        ]
    ],
    [
        "jquery.i18n",
        "",
        [
            100
        ]
    ],
    [
        "jquery.lengthLimit",
        "",
        [
            60
        ]
    ],
    [
        "jquery.makeCollapsible",
        "",
        [
            7,
            75
        ]
    ],
    [
        "jquery.spinner",
        "",
        [
            20
        ]
    ],
    [
        "jquery.spinner.styles",
        ""
    ],
    [
        "jquery.suggestions",
        "",
        [
            15
        ]
    ],
    [
        "jquery.tablesorter",
        "",
        [
            23,
            102,
            75
        ]
    ],
    [
        "jquery.tablesorter.styles",
        ""
    ],
    [
        "jquery.textSelection",
        "",
        [
            13
        ]
    ],
    [
        "jquery.ui",
        ""
    ],
    [
        "moment",
        "",
        [
            98,
            75
        ]
    ],
    [
        "vue",
        "",
        [
            109
        ]
    ],
    [
        "vuex",
        "",
        [
            27
        ]
    ],
    [
        "pinia",
        "",
        [
            27
        ]
    ],
    [
        "@wikimedia/codex",
        "",
        [
            31,
            27
        ]
    ],
    [
        "codex-styles",
        ""
    ],
    [
        "mediawiki.codex.messagebox.styles",
        ""
    ],
    [
        "@wikimedia/codex-search",
        "",
        [
            34,
            27
        ]
    ],
    [
        "codex-search-styles",
        ""
    ],
    [
        "mediawiki.template",
        ""
    ],
    [
        "mediawiki.template.mustache",
        "",
        [
            35
        ]
    ],
    [
        "mediawiki.apipretty",
        ""
    ],
    [
        "mediawiki.api",
        "",
        [
            101
        ]
    ],
    [
        "mediawiki.content.json",
        ""
    ],
    [
        "mediawiki.confirmCloseWindow",
        ""
    ],
    [
        "mediawiki.debug",
        "",
        [
            194
        ]
    ],
    [
        "mediawiki.diff",
        "",
        [
            38
        ]
    ],
    [
        "mediawiki.diff.styles",
        ""
    ],
    [
        "mediawiki.feedback",
        "",
        [
            650,
            202
        ]
    ],
    [
        "mediawiki.feedlink",
        ""
    ],
    [
        "mediawiki.filewarning",
        "",
        [
            194,
            206
        ]
    ],
    [
        "mediawiki.ForeignApi",
        "",
        [
            48
        ]
    ],
    [
        "mediawiki.ForeignApi.core",
        "",
        [
            38,
            191
        ]
    ],
    [
        "mediawiki.helplink",
        ""
    ],
    [
        "mediawiki.hlist",
        ""
    ],
    [
        "mediawiki.htmlform",
        "",
        [
            169
        ]
    ],
    [
        "mediawiki.htmlform.ooui",
        "",
        [
            194
        ]
    ],
    [
        "mediawiki.htmlform.styles",
        ""
    ],
    [
        "mediawiki.htmlform.codex.styles",
        ""
    ],
    [
        "mediawiki.htmlform.ooui.styles",
        ""
    ],
    [
        "mediawiki.inspect",
        "",
        [
            60,
            75
        ]
    ],
    [
        "mediawiki.notification",
        "",
        [
            75,
            81
        ]
    ],
    [
        "mediawiki.notification.convertmessagebox",
        "",
        [
            57
        ]
    ],
    [
        "mediawiki.notification.convertmessagebox.styles",
        ""
    ],
    [
        "mediawiki.String",
        ""
    ],
    [
        "mediawiki.pager.styles",
        ""
    ],
    [
        "mediawiki.pulsatingdot",
        ""
    ],
    [
        "mediawiki.searchSuggest",
        "",
        [
            21,
            38
        ]
    ],
    [
        "mediawiki.storage",
        "",
        [
            75
        ]
    ],
    [
        "mediawiki.Title",
        "",
        [
            60,
            75
        ]
    ],
    [
        "mediawiki.Upload",
        "",
        [
            38
        ]
    ],
    [
        "mediawiki.ForeignUpload",
        "",
        [
            47,
            66
        ]
    ],
    [
        "mediawiki.Upload.Dialog",
        "",
        [
            69
        ]
    ],
    [
        "mediawiki.Upload.BookletLayout",
        "",
        [
            66,
            26,
            197,
            202,
            207,
            208
        ]
    ],
    [
        "mediawiki.ForeignStructuredUpload.BookletLayout",
        "",
        [
            67,
            69,
            105,
            173,
            167
        ]
    ],
    [
        "mediawiki.toc",
        "",
        [
            78
        ]
    ],
    [
        "mediawiki.Uri",
        "",
        [
            75
        ]
    ],
    [
        "mediawiki.user",
        "",
        [
            38,
            78
        ]
    ],
    [
        "mediawiki.userSuggest",
        "",
        [
            21,
            38
        ]
    ],
    [
        "mediawiki.util",
        "",
        [
            13,
            9
        ]
    ],
    [
        "mediawiki.checkboxtoggle",
        ""
    ],
    [
        "mediawiki.checkboxtoggle.styles",
        ""
    ],
    [
        "mediawiki.cookie",
        ""
    ],
    [
        "mediawiki.experiments",
        ""
    ],
    [
        "mediawiki.editfont.styles",
        ""
    ],
    [
        "mediawiki.visibleTimeout",
        ""
    ],
    [
        "mediawiki.action.edit",
        "",
        [
            24,
            83,
            80,
            169
        ]
    ],
    [
        "mediawiki.action.edit.styles",
        ""
    ],
    [
        "mediawiki.action.edit.collapsibleFooter",
        "",
        [
            18,
            64
        ]
    ],
    [
        "mediawiki.action.edit.preview",
        "",
        [
            19,
            111
        ]
    ],
    [
        "mediawiki.action.history",
        "",
        [
            18
        ]
    ],
    [
        "mediawiki.action.history.styles",
        ""
    ],
    [
        "mediawiki.action.protect",
        "",
        [
            169
        ]
    ],
    [
        "mediawiki.action.view.metadata",
        "",
        [
            96
        ]
    ],
    [
        "mediawiki.editRecovery.postEdit",
        ""
    ],
    [
        "mediawiki.editRecovery.edit",
        "",
        [
            57,
            166,
            210
        ]
    ],
    [
        "mediawiki.action.view.postEdit",
        "",
        [
            57,
            64,
            156,
            194,
            214
        ]
    ],
    [
        "mediawiki.action.view.redirect",
        ""
    ],
    [
        "mediawiki.action.view.redirectPage",
        ""
    ],
    [
        "mediawiki.action.edit.editWarning",
        "",
        [
            24,
            40,
            101
        ]
    ],
    [
        "mediawiki.action.view.filepage",
        ""
    ],
    [
        "mediawiki.action.styles",
        ""
    ],
    [
        "mediawiki.language",
        "",
        [
            99
        ]
    ],
    [
        "mediawiki.cldr",
        "",
        [
            100
        ]
    ],
    [
        "mediawiki.libs.pluralruleparser",
        ""
    ],
    [
        "mediawiki.jqueryMsg",
        "",
        [
            65,
            98,
            5
        ]
    ],
    [
        "mediawiki.language.months",
        "",
        [
            98
        ]
    ],
    [
        "mediawiki.language.names",
        "",
        [
            98
        ]
    ],
    [
        "mediawiki.language.specialCharacters",
        "",
        [
            98
        ]
    ],
    [
        "mediawiki.libs.jpegmeta",
        ""
    ],
    [
        "mediawiki.page.gallery",
        "",
        [
            107,
            75
        ]
    ],
    [
        "mediawiki.page.gallery.styles",
        ""
    ],
    [
        "mediawiki.page.gallery.slideshow",
        "",
        [
            197,
            217,
            219
        ]
    ],
    [
        "mediawiki.page.ready",
        "",
        [
            73
        ]
    ],
    [
        "mediawiki.page.watch.ajax",
        "",
        [
            73
        ]
    ],
    [
        "mediawiki.page.preview",
        "",
        [
            18,
            24,
            42,
            43,
            194
        ]
    ],
    [
        "mediawiki.page.image.pagination",
        "",
        [
            19,
            75
        ]
    ],
    [
        "mediawiki.page.media",
        ""
    ],
    [
        "mediawiki.rcfilters.filters.base.styles",
        ""
    ],
    [
        "mediawiki.rcfilters.highlightCircles.seenunseen.styles",
        ""
    ],
    [
        "mediawiki.rcfilters.filters.ui",
        "",
        [
            18,
            72,
            164,
            203,
            210,
            213,
            214,
            215,
            217,
            218
        ]
    ],
    [
        "mediawiki.interface.helpers.styles",
        ""
    ],
    [
        "mediawiki.special",
        ""
    ],
    [
        "mediawiki.special.apisandbox",
        "",
        [
            18,
            184,
            170,
            193
        ]
    ],
    [
        "mediawiki.special.block",
        "",
        [
            51,
            167,
            183,
            174,
            184,
            181,
            210
        ]
    ],
    [
        "mediawiki.misc-authed-ooui",
        "",
        [
            19,
            52,
            164,
            169
        ]
    ],
    [
        "mediawiki.misc-authed-pref",
        "",
        [
            5
        ]
    ],
    [
        "mediawiki.misc-authed-curate",
        "",
        [
            12,
            14,
            17,
            19,
            38
        ]
    ],
    [
        "mediawiki.special.block.codex",
        "",
        [
            30,
            29
        ]
    ],
    [
        "mediawiki.protectionIndicators.styles",
        ""
    ],
    [
        "mediawiki.special.changeslist",
        ""
    ],
    [
        "mediawiki.special.changeslist.watchlistexpiry",
        "",
        [
            118,
            214
        ]
    ],
    [
        "mediawiki.special.changeslist.enhanced",
        ""
    ],
    [
        "mediawiki.special.changeslist.legend",
        ""
    ],
    [
        "mediawiki.special.changeslist.legend.js",
        "",
        [
            78
        ]
    ],
    [
        "mediawiki.special.contributions",
        "",
        [
            18,
            167,
            193
        ]
    ],
    [
        "mediawiki.special.import.styles.ooui",
        ""
    ],
    [
        "mediawiki.special.changecredentials",
        ""
    ],
    [
        "mediawiki.special.changeemail",
        ""
    ],
    [
        "mediawiki.special.preferences.ooui",
        "",
        [
            40,
            80,
            58,
            64,
            174,
            169,
            202
        ]
    ],
    [
        "mediawiki.special.preferences.styles.ooui",
        ""
    ],
    [
        "mediawiki.special.editrecovery.styles",
        ""
    ],
    [
        "mediawiki.special.editrecovery",
        "",
        [
            27
        ]
    ],
    [
        "mediawiki.special.search",
        "",
        [
            186
        ]
    ],
    [
        "mediawiki.special.search.commonsInterwikiWidget",
        "",
        [
            38
        ]
    ],
    [
        "mediawiki.special.search.interwikiwidget.styles",
        ""
    ],
    [
        "mediawiki.special.search.styles",
        ""
    ],
    [
        "mediawiki.special.unwatchedPages",
        "",
        [
            38
        ]
    ],
    [
        "mediawiki.special.upload",
        "",
        [
            19,
            38,
            40,
            105,
            118,
            35
        ]
    ],
    [
        "mediawiki.authenticationPopup",
        "",
        [
            19,
            202
        ]
    ],
    [
        "mediawiki.authenticationPopup.success",
        ""
    ],
    [
        "mediawiki.special.userlogin.common.styles",
        ""
    ],
    [
        "mediawiki.special.userlogin.login.styles",
        ""
    ],
    [
        "mediawiki.special.userlogin.authentication-popup",
        ""
    ],
    [
        "mediawiki.special.createaccount",
        "",
        [
            38
        ]
    ],
    [
        "mediawiki.special.userlogin.signup.styles",
        ""
    ],
    [
        "mediawiki.special.userrights",
        "",
        [
            17,
            58
        ]
    ],
    [
        "mediawiki.special.watchlist",
        "",
        [
            194,
            214
        ]
    ],
    [
        "mediawiki.tempUserBanner.styles",
        ""
    ],
    [
        "mediawiki.tempUserBanner",
        "",
        [
            101
        ]
    ],
    [
        "mediawiki.tempUserCreated",
        "",
        [
            75
        ]
    ],
    [
        "mediawiki.ui",
        ""
    ],
    [
        "mediawiki.ui.checkbox",
        ""
    ],
    [
        "mediawiki.ui.radio",
        ""
    ],
    [
        "mediawiki.legacy.messageBox",
        ""
    ],
    [
        "mediawiki.ui.button",
        ""
    ],
    [
        "mediawiki.ui.input",
        ""
    ],
    [
        "mediawiki.ui.icon",
        ""
    ],
    [
        "mediawiki.widgets",
        "",
        [
            165,
            197,
            207,
            208
        ]
    ],
    [
        "mediawiki.widgets.styles",
        ""
    ],
    [
        "mediawiki.widgets.AbandonEditDialog",
        "",
        [
            202
        ]
    ],
    [
        "mediawiki.widgets.DateInputWidget",
        "",
        [
            168,
            26,
            197,
            219
        ]
    ],
    [
        "mediawiki.widgets.DateInputWidget.styles",
        ""
    ],
    [
        "mediawiki.widgets.visibleLengthLimit",
        "",
        [
            17,
            194
        ]
    ],
    [
        "mediawiki.widgets.datetime",
        "",
        [
            194,
            214,
            218,
            219
        ]
    ],
    [
        "mediawiki.widgets.expiry",
        "",
        [
            170,
            26,
            197
        ]
    ],
    [
        "mediawiki.widgets.CheckMatrixWidget",
        "",
        [
            194
        ]
    ],
    [
        "mediawiki.widgets.CategoryMultiselectWidget",
        "",
        [
            47,
            197
        ]
    ],
    [
        "mediawiki.widgets.SelectWithInputWidget",
        "",
        [
            175,
            197
        ]
    ],
    [
        "mediawiki.widgets.SelectWithInputWidget.styles",
        ""
    ],
    [
        "mediawiki.widgets.SizeFilterWidget",
        "",
        [
            177,
            197
        ]
    ],
    [
        "mediawiki.widgets.SizeFilterWidget.styles",
        ""
    ],
    [
        "mediawiki.widgets.MediaSearch",
        "",
        [
            47,
            197
        ]
    ],
    [
        "mediawiki.widgets.Table",
        "",
        [
            197
        ]
    ],
    [
        "mediawiki.widgets.TagMultiselectWidget",
        "",
        [
            197
        ]
    ],
    [
        "mediawiki.widgets.UserInputWidget",
        "",
        [
            197
        ]
    ],
    [
        "mediawiki.widgets.UsersMultiselectWidget",
        "",
        [
            197
        ]
    ],
    [
        "mediawiki.widgets.NamespacesMultiselectWidget",
        "",
        [
            164
        ]
    ],
    [
        "mediawiki.widgets.TitlesMultiselectWidget",
        "",
        [
            164
        ]
    ],
    [
        "mediawiki.widgets.TagMultiselectWidget.styles",
        ""
    ],
    [
        "mediawiki.widgets.SearchInputWidget",
        "",
        [
            63,
            164,
            214
        ]
    ],
    [
        "mediawiki.widgets.SearchInputWidget.styles",
        ""
    ],
    [
        "mediawiki.widgets.ToggleSwitchWidget",
        "",
        [
            197
        ]
    ],
    [
        "mediawiki.watchstar.widgets",
        "",
        [
            193
        ]
    ],
    [
        "mediawiki.deflate",
        ""
    ],
    [
        "oojs",
        ""
    ],
    [
        "mediawiki.router",
        "",
        [
            191
        ]
    ],
    [
        "oojs-ui",
        "",
        [
            200,
            197,
            202
        ]
    ],
    [
        "oojs-ui-core",
        "",
        [
            109,
            191,
            196,
            195,
            204
        ]
    ],
    [
        "oojs-ui-core.styles",
        ""
    ],
    [
        "oojs-ui-core.icons",
        ""
    ],
    [
        "oojs-ui-widgets",
        "",
        [
            194,
            199
        ]
    ],
    [
        "oojs-ui-widgets.styles",
        ""
    ],
    [
        "oojs-ui-widgets.icons",
        ""
    ],
    [
        "oojs-ui-toolbars",
        "",
        [
            194,
            201
        ]
    ],
    [
        "oojs-ui-toolbars.icons",
        ""
    ],
    [
        "oojs-ui-windows",
        "",
        [
            194,
            203
        ]
    ],
    [
        "oojs-ui-windows.icons",
        ""
    ],
    [
        "oojs-ui.styles.indicators",
        ""
    ],
    [
        "oojs-ui.styles.icons-accessibility",
        ""
    ],
    [
        "oojs-ui.styles.icons-alerts",
        ""
    ],
    [
        "oojs-ui.styles.icons-content",
        ""
    ],
    [
        "oojs-ui.styles.icons-editing-advanced",
        ""
    ],
    [
        "oojs-ui.styles.icons-editing-citation",
        ""
    ],
    [
        "oojs-ui.styles.icons-editing-core",
        ""
    ],
    [
        "oojs-ui.styles.icons-editing-functions",
        ""
    ],
    [
        "oojs-ui.styles.icons-editing-list",
        ""
    ],
    [
        "oojs-ui.styles.icons-editing-styling",
        ""
    ],
    [
        "oojs-ui.styles.icons-interactions",
        ""
    ],
    [
        "oojs-ui.styles.icons-layout",
        ""
    ],
    [
        "oojs-ui.styles.icons-location",
        ""
    ],
    [
        "oojs-ui.styles.icons-media",
        ""
    ],
    [
        "oojs-ui.styles.icons-moderation",
        ""
    ],
    [
        "oojs-ui.styles.icons-movement",
        ""
    ],
    [
        "oojs-ui.styles.icons-user",
        ""
    ],
    [
        "oojs-ui.styles.icons-wikimedia",
        ""
    ],
    [
        "skins.vector.search.codex.styles",
        ""
    ],
    [
        "skins.vector.search.codex.scripts",
        "",
        [
            222,
            27
        ]
    ],
    [
        "skins.vector.search",
        "",
        [
            223
        ]
    ],
    [
        "skins.vector.styles.legacy",
        ""
    ],
    [
        "skins.vector.styles",
        ""
    ],
    [
        "skins.vector.icons.js",
        ""
    ],
    [
        "skins.vector.icons",
        ""
    ],
    [
        "skins.vector.clientPreferences",
        "",
        [
            73
        ]
    ],
    [
        "skins.vector.js",
        "",
        [
            79,
            110,
            64,
            229,
            227
        ]
    ],
    [
        "skins.vector.legacy.js",
        "",
        [
            109
        ]
    ],
    [
        "mmv",
        "",
        [
            236
        ]
    ],
    [
        "mmv.codex",
        ""
    ],
    [
        "mmv.ui.reuse",
        "",
        [
            164,
            233
        ]
    ],
    [
        "mmv.ui.restriction",
        ""
    ],
    [
        "mmv.bootstrap",
        "",
        [
            192,
            64,
            73,
            233
        ]
    ],
    [
        "mmv.bootstrap.autostart",
        "",
        [
            236
        ]
    ],
    [
        "mmv.head",
        "",
        [
            236
        ]
    ],
    [
        "ext.wikiEditor",
        "",
        [
            24,
            25,
            104,
            164,
            209,
            210,
            212,
            213,
            217,
            35
        ],
        3
    ],
    [
        "ext.wikiEditor.styles",
        "",
        [],
        3
    ],
    [
        "ext.wikiEditor.images",
        ""
    ],
    [
        "ext.wikiEditor.realtimepreview",
        "",
        [
            239,
            241,
            111,
            62,
            64,
            214
        ]
    ],
    [
        "ext.scribunto.errors",
        "",
        [
            197
        ]
    ],
    [
        "ext.scribunto.logs",
        ""
    ],
    [
        "ext.scribunto.edit",
        "",
        [
            19,
            38
        ]
    ],
    [
        "ext.cite.styles",
        ""
    ],
    [
        "ext.cite.parsoid.styles",
        ""
    ],
    [
        "ext.cite.visualEditor.core",
        "",
        [
            335
        ]
    ],
    [
        "ext.cite.visualEditor",
        "",
        [
            247,
            246,
            248,
            206,
            209,
            214
        ]
    ],
    [
        "ext.cite.wikiEditor",
        "",
        [
            239
        ]
    ],
    [
        "ext.cite.ux-enhancements",
        ""
    ],
    [
        "ext.SimpleBatchUpload.jquery-file-upload",
        "",
        [
            25
        ]
    ],
    [
        "ext.SimpleBatchUpload",
        "",
        [
            252,
            38
        ]
    ],
    [
        "ext.dismissableSiteNotice",
        "",
        [
            78,
            75
        ]
    ],
    [
        "ext.dismissableSiteNotice.styles",
        ""
    ],
    [
        "ext.LinkSuggest",
        "",
        [
            25,
            38
        ]
    ],
    [
        "ext.codeEditor",
        "",
        [
            259
        ],
        3
    ],
    [
        "ext.codeEditor.styles",
        ""
    ],
    [
        "jquery.codeEditor",
        "",
        [
            261,
            260,
            239,
            202
        ],
        3
    ],
    [
        "ext.codeEditor.icons",
        ""
    ],
    [
        "ext.codeEditor.ace",
        "",
        [],
        4
    ],
    [
        "ext.codeEditor.ace.modes",
        "",
        [
            261
        ],
        4
    ],
    [
        "ext.pygments",
        ""
    ],
    [
        "ext.geshi.visualEditor",
        "",
        [
            327
        ]
    ],
    [
        "ext.RevisionSlider.lazyCss",
        ""
    ],
    [
        "ext.RevisionSlider.lazyJs",
        "",
        [
            268,
            219
        ]
    ],
    [
        "ext.RevisionSlider.init",
        "",
        [
            268,
            269,
            218
        ]
    ],
    [
        "ext.RevisionSlider.Settings",
        "",
        [
            64,
            73
        ]
    ],
    [
        "ext.RevisionSlider.Slider",
        "",
        [
            270,
            25,
            72,
            26,
            193,
            214,
            219
        ]
    ],
    [
        "ext.RevisionSlider.dialogImages",
        ""
    ],
    [
        "ext.oath.styles",
        ""
    ],
    [
        "ext.oath",
        ""
    ],
    [
        "ext.inputBox.styles",
        ""
    ],
    [
        "ext.ajaxpoll",
        "",
        [
            38
        ],
        5
    ],
    [
        "ext.Tabber",
        "",
        [
            72
        ]
    ],
    [
        "ext.imagemap",
        "",
        [
            277
        ]
    ],
    [
        "ext.imagemap.styles",
        ""
    ],
    [
        "ext.cirrus.serp",
        "",
        [
            192,
            75
        ]
    ],
    [
        "ext.math.mathjax",
        "",
        [],
        6
    ],
    [
        "ext.math.styles",
        ""
    ],
    [
        "ext.math.popup",
        "",
        [
            47,
            73
        ]
    ],
    [
        "mw.widgets.MathWbEntitySelector",
        "",
        [
            47,
            164,
            "mw.config.values.wbRepo",
            202
        ]
    ],
    [
        "ext.math.visualEditor",
        "",
        [
            280,
            327
        ]
    ],
    [
        "ext.math.visualEditor.mathSymbols",
        ""
    ],
    [
        "ext.math.visualEditor.chemSymbols",
        ""
    ],
    [
        "socket.io",
        ""
    ],
    [
        "peerjs",
        ""
    ],
    [
        "dompurify",
        ""
    ],
    [
        "color-picker",
        ""
    ],
    [
        "unicodejs",
        ""
    ],
    [
        "papaparse",
        ""
    ],
    [
        "rangefix",
        ""
    ],
    [
        "spark-md5",
        ""
    ],
    [
        "ext.visualEditor.supportCheck",
        "",
        [],
        7
    ],
    [
        "ext.visualEditor.sanitize",
        "",
        [
            288,
            315
        ],
        7
    ],
    [
        "ext.visualEditor.progressBarWidget",
        "",
        [],
        7
    ],
    [
        "ext.visualEditor.tempWikitextEditorWidget",
        "",
        [
            80,
            73
        ],
        7
    ],
    [
        "ext.visualEditor.desktopArticleTarget.init",
        "",
        [
            296,
            294,
            297,
            311,
            24,
            109,
            64
        ],
        7
    ],
    [
        "ext.visualEditor.desktopArticleTarget.noscript",
        ""
    ],
    [
        "ext.visualEditor.targetLoader",
        "",
        [
            314,
            311,
            24,
            64,
            73
        ],
        7
    ],
    [
        "ext.visualEditor.desktopTarget",
        "",
        [],
        7
    ],
    [
        "ext.visualEditor.desktopArticleTarget",
        "",
        [
            318,
            323,
            301,
            329
        ],
        7
    ],
    [
        "ext.visualEditor.mobileArticleTarget",
        "",
        [
            318,
            324
        ],
        7
    ],
    [
        "ext.visualEditor.collabTarget",
        "",
        [
            316,
            322,
            80,
            164,
            214,
            215
        ],
        7
    ],
    [
        "ext.visualEditor.collabTarget.desktop",
        "",
        [
            304,
            323,
            301,
            329
        ],
        7
    ],
    [
        "ext.visualEditor.collabTarget.mobile",
        "",
        [
            304,
            324,
            328
        ],
        7
    ],
    [
        "ext.visualEditor.collabTarget.init",
        "",
        [
            294,
            164,
            193
        ],
        7
    ],
    [
        "ext.visualEditor.collabTarget.init.styles",
        ""
    ],
    [
        "ext.visualEditor.collab",
        "",
        [
            289,
            320,
            287
        ]
    ],
    [
        "ext.visualEditor.ve",
        "",
        [],
        7
    ],
    [
        "ext.visualEditor.track",
        "",
        [
            310
        ],
        7
    ],
    [
        "ext.visualEditor.editCheck",
        "",
        [
            317
        ],
        7
    ],
    [
        "ext.visualEditor.core.utils",
        "",
        [
            311,
            193
        ],
        7
    ],
    [
        "ext.visualEditor.core.utils.parsing",
        "",
        [
            310
        ],
        7
    ],
    [
        "ext.visualEditor.base",
        "",
        [
            313,
            314,
            290
        ],
        7
    ],
    [
        "ext.visualEditor.mediawiki",
        "",
        [
            315,
            300,
            22,
            647
        ],
        7
    ],
    [
        "ext.visualEditor.mwsave",
        "",
        [
            327,
            17,
            19,
            42,
            43,
            214
        ],
        7
    ],
    [
        "ext.visualEditor.articleTarget",
        "",
        [
            328,
            317,
            92,
            166
        ],
        7
    ],
    [
        "ext.visualEditor.data",
        "",
        [
            316
        ]
    ],
    [
        "ext.visualEditor.core",
        "",
        [
            295,
            294,
            291,
            292,
            293
        ],
        7
    ],
    [
        "ext.visualEditor.commentAnnotation",
        "",
        [
            320
        ],
        7
    ],
    [
        "ext.visualEditor.rebase",
        "",
        [
            289,
            338,
            321,
            220,
            286
        ],
        7
    ],
    [
        "ext.visualEditor.core.desktop",
        "",
        [
            320
        ],
        7
    ],
    [
        "ext.visualEditor.core.mobile",
        "",
        [
            320
        ],
        7
    ],
    [
        "ext.visualEditor.welcome",
        "",
        [
            193
        ],
        7
    ],
    [
        "ext.visualEditor.switching",
        "",
        [
            193,
            205,
            208,
            210
        ],
        7
    ],
    [
        "ext.visualEditor.mwcore",
        "",
        [
            339,
            316,
            326,
            325,
            117,
            62,
            8,
            164
        ],
        7
    ],
    [
        "ext.visualEditor.mwextensions",
        "",
        [
            319,
            349,
            343,
            345,
            330,
            347,
            332,
            344,
            333,
            335
        ],
        7
    ],
    [
        "ext.visualEditor.mwextensions.desktop",
        "",
        [
            328,
            334,
            70
        ],
        7
    ],
    [
        "ext.visualEditor.mwformatting",
        "",
        [
            327
        ],
        7
    ],
    [
        "ext.visualEditor.mwimage.core",
        "",
        [
            327
        ],
        7
    ],
    [
        "ext.visualEditor.mwimage",
        "",
        [
            350,
            331,
            178,
            26,
            217
        ],
        7
    ],
    [
        "ext.visualEditor.mwlink",
        "",
        [
            327
        ],
        7
    ],
    [
        "ext.visualEditor.mwmeta",
        "",
        [
            333,
            94
        ],
        7
    ],
    [
        "ext.visualEditor.mwtransclusion",
        "",
        [
            327,
            181
        ],
        7
    ],
    [
        "treeDiffer",
        ""
    ],
    [
        "diffMatchPatch",
        ""
    ],
    [
        "ext.visualEditor.checkList",
        "",
        [
            320
        ],
        7
    ],
    [
        "ext.visualEditor.diffing",
        "",
        [
            337,
            320,
            336
        ],
        7
    ],
    [
        "ext.visualEditor.diffPage.init.styles",
        ""
    ],
    [
        "ext.visualEditor.diffLoader",
        "",
        [
            300
        ],
        7
    ],
    [
        "ext.visualEditor.diffPage.init",
        "",
        [
            341,
            340,
            193,
            205,
            208
        ],
        7
    ],
    [
        "ext.visualEditor.language",
        "",
        [
            320,
            647,
            103
        ],
        7
    ],
    [
        "ext.visualEditor.mwlanguage",
        "",
        [
            320
        ],
        7
    ],
    [
        "ext.visualEditor.mwalienextension",
        "",
        [
            327
        ],
        7
    ],
    [
        "ext.visualEditor.mwwikitext",
        "",
        [
            333,
            80
        ],
        7
    ],
    [
        "ext.visualEditor.mwgallery",
        "",
        [
            327,
            107,
            178,
            217
        ],
        7
    ],
    [
        "ext.visualEditor.mwsignature",
        "",
        [
            335
        ],
        7
    ],
    [
        "ext.visualEditor.icons",
        "",
        [
            351,
            352,
            206,
            207,
            208,
            210,
            212,
            213,
            214,
            215,
            218,
            219,
            220,
            204
        ],
        7
    ],
    [
        "ext.visualEditor.icons-licenses",
        ""
    ],
    [
        "ext.visualEditor.moduleIcons",
        ""
    ],
    [
        "ext.visualEditor.moduleIndicators",
        ""
    ],
    [
        "wg.fixedwidth",
        "",
        [],
        0
    ],
    [
        "ext.echo.ui.desktop",
        "",
        [
            361,
            355
        ]
    ],
    [
        "ext.echo.ui",
        "",
        [
            356,
            649,
            197,
            206,
            207,
            210,
            214,
            218,
            219,
            220
        ]
    ],
    [
        "ext.echo.dm",
        "",
        [
            359,
            26
        ]
    ],
    [
        "ext.echo.api",
        "",
        [
            47
        ]
    ],
    [
        "ext.echo.mobile",
        "",
        [
            355,
            192
        ]
    ],
    [
        "ext.echo.init",
        "",
        [
            357
        ]
    ],
    [
        "ext.echo.centralauth",
        ""
    ],
    [
        "ext.echo.styles.badge",
        ""
    ],
    [
        "ext.echo.styles.notifications",
        ""
    ],
    [
        "ext.echo.styles.alert",
        ""
    ],
    [
        "ext.echo.special",
        "",
        [
            365,
            355,
            72
        ]
    ],
    [
        "ext.echo.styles.special",
        ""
    ],
    [
        "ext.thanks",
        "",
        [
            38,
            78
        ]
    ],
    [
        "ext.thanks.corethank",
        "",
        [
            366,
            14,
            202
        ]
    ],
    [
        "ext.thanks.flowthank",
        "",
        [
            366,
            202
        ]
    ],
    [
        "ext.tmh.transcodetable",
        "",
        [
            193
        ]
    ],
    [
        "ext.embedVideo.messages",
        ""
    ],
    [
        "ext.embedVideo.videolink",
        ""
    ],
    [
        "ext.embedVideo.consent",
        ""
    ],
    [
        "ext.embedVideo.overlay",
        ""
    ],
    [
        "ext.embedVideo.styles",
        ""
    ],
    [
        "ext.templateData",
        ""
    ],
    [
        "ext.templateDataGenerator.editPage",
        ""
    ],
    [
        "ext.templateDataGenerator.data",
        "",
        [
            191
        ]
    ],
    [
        "ext.templateDataGenerator.editTemplatePage.loading",
        ""
    ],
    [
        "ext.templateDataGenerator.editTemplatePage",
        "",
        [
            375,
            380,
            377,
            24,
            647,
            197,
            202,
            214,
            215,
            218
        ]
    ],
    [
        "ext.templateData.images",
        ""
    ],
    [
        "mobile.pagelist.styles",
        ""
    ],
    [
        "mobile.pagesummary.styles",
        ""
    ],
    [
        "mobile.userpage.styles",
        ""
    ],
    [
        "mobile.init.styles",
        ""
    ],
    [
        "mobile.init",
        "",
        [
            387
        ]
    ],
    [
        "mobile.codex.styles",
        ""
    ],
    [
        "mobile.startup",
        "",
        [
            110,
            192,
            64,
            36,
            386,
            384,
            381,
            382
        ]
    ],
    [
        "mobile.editor.overlay",
        "",
        [
            92,
            40,
            80,
            166,
            387,
            193,
            210
        ]
    ],
    [
        "mobile.mediaViewer",
        "",
        [
            387
        ]
    ],
    [
        "mobile.languages.structured",
        "",
        [
            387
        ]
    ],
    [
        "mobile.special.styles",
        ""
    ],
    [
        "mobile.special.watchlist.scripts",
        "",
        [
            387
        ]
    ],
    [
        "mobile.special.codex.styles",
        ""
    ],
    [
        "mobile.special.mobileoptions.styles",
        ""
    ],
    [
        "mobile.special.mobileoptions.scripts",
        "",
        [
            387
        ]
    ],
    [
        "mobile.special.userlogin.scripts",
        ""
    ],
    [
        "ext.abuseFilter",
        ""
    ],
    [
        "ext.abuseFilter.edit",
        "",
        [
            19,
            24,
            40,
            197
        ]
    ],
    [
        "ext.abuseFilter.tools",
        "",
        [
            19,
            38
        ]
    ],
    [
        "ext.abuseFilter.examine",
        "",
        [
            19,
            38
        ]
    ],
    [
        "ext.abuseFilter.ace",
        "",
        [
            261
        ]
    ],
    [
        "ext.abuseFilter.visualEditor",
        ""
    ],
    [
        "ext.checkUser.clientHints",
        "",
        [
            38,
            11
        ]
    ],
    [
        "ext.checkUser",
        "",
        [
            22,
            61,
            64,
            164,
            181,
            210,
            214,
            216,
            218,
            220
        ]
    ],
    [
        "ext.checkUser.styles",
        ""
    ],
    [
        "ext.timeline.styles",
        ""
    ],
    [
        "mediawiki.api.titleblacklist",
        "",
        [
            38
        ]
    ],
    [
        "ext.titleblacklist.visualEditor",
        ""
    ],
    [
        "ext.spamBlacklist.visualEditor",
        ""
    ],
    [
        "ext.globalBlocking",
        "",
        [
            51,
            164,
            181
        ]
    ],
    [
        "ext.globalBlocking.styles",
        ""
    ],
    [
        "ext.CodeMirror",
        "",
        [
            73
        ]
    ],
    [
        "ext.CodeMirror.WikiEditor",
        "",
        [
            412,
            24,
            213
        ]
    ],
    [
        "ext.CodeMirror.lib",
        ""
    ],
    [
        "ext.CodeMirror.addons",
        "",
        [
            414
        ]
    ],
    [
        "ext.CodeMirror.mode.mediawiki",
        "",
        [
            414
        ]
    ],
    [
        "ext.CodeMirror.lib.mode.css",
        "",
        [
            414
        ]
    ],
    [
        "ext.CodeMirror.lib.mode.javascript",
        "",
        [
            414
        ]
    ],
    [
        "ext.CodeMirror.lib.mode.xml",
        "",
        [
            414
        ]
    ],
    [
        "ext.CodeMirror.lib.mode.htmlmixed",
        "",
        [
            417,
            418,
            419
        ]
    ],
    [
        "ext.CodeMirror.lib.mode.clike",
        "",
        [
            414
        ]
    ],
    [
        "ext.CodeMirror.lib.mode.php",
        "",
        [
            421,
            420
        ]
    ],
    [
        "ext.CodeMirror.visualEditor",
        "",
        [
            412,
            334
        ]
    ],
    [
        "ext.CodeMirror.v6",
        "",
        [
            426,
            73
        ]
    ],
    [
        "ext.CodeMirror.v6.init",
        "",
        [
            5
        ]
    ],
    [
        "ext.CodeMirror.v6.lib",
        ""
    ],
    [
        "ext.CodeMirror.v6.mode.mediawiki",
        "",
        [
            424
        ]
    ],
    [
        "ext.CodeMirror.v6.mode.javascript",
        "",
        [
            426
        ]
    ],
    [
        "ext.CodeMirror.v6.mode.json",
        "",
        [
            426
        ]
    ],
    [
        "ext.CodeMirror.v6.mode.css",
        "",
        [
            426
        ]
    ],
    [
        "ext.CodeMirror.v6.WikiEditor",
        "",
        [
            424,
            239
        ]
    ],
    [
        "ext.CodeMirror.v6.visualEditor",
        "",
        [
            424,
            334
        ]
    ],
    [
        "ext.CodeMirror.visualEditor.init",
        ""
    ],
    [
        "ext.searchdigest.styles",
        ""
    ],
    [
        "ext.searchdigest.redirect",
        "",
        [
            202
        ]
    ],
    [
        "ext.TemplateSandbox.top",
        ""
    ],
    [
        "ext.TemplateSandbox",
        "",
        [
            436
        ]
    ],
    [
        "ext.TemplateSandbox.preview",
        "",
        [
            19,
            111
        ]
    ],
    [
        "ext.TemplateSandbox.visualeditor",
        "",
        [
            164,
            193
        ]
    ],
    [
        "ext.MWOAuth.styles",
        ""
    ],
    [
        "ext.MWOAuth.AuthorizeDialog",
        "",
        [
            202
        ]
    ],
    [
        "ext.interwiki.specialpage",
        ""
    ],
    [
        "ext.categoryTree",
        "",
        [
            38
        ]
    ],
    [
        "ext.categoryTree.styles",
        ""
    ],
    [
        "ext.gloopcontrol.styles",
        ""
    ],
    [
        "ext.GloopAnalytics",
        "",
        [
            448,
            164,
            26
        ]
    ],
    [
        "ext.GloopAnalytics.styles",
        ""
    ],
    [
        "ext.GloopAnalytics.lib",
        ""
    ],
    [
        "ext.migrateuseraccount.styles",
        ""
    ],
    [
        "special.migrateuseraccount",
        "",
        [
            52
        ]
    ],
    [
        "ext.less.messages",
        ""
    ],
    [
        "ext.kartographer",
        ""
    ],
    [
        "ext.kartographer.style",
        ""
    ],
    [
        "ext.kartographer.site",
        ""
    ],
    [
        "mapbox",
        ""
    ],
    [
        "leaflet.draw",
        "",
        [
            455
        ]
    ],
    [
        "ext.kartographer.link",
        "",
        [
            460,
            192
        ]
    ],
    [
        "ext.kartographer.box",
        "",
        [
            459,
            463
        ]
    ],
    [
        "ext.kartographer.controls",
        "",
        [
            452,
            461,
            454,
            453,
            455,
            72,
            38,
            217
        ]
    ],
    [
        "ext.kartographer.linkbox",
        "",
        [
            463
        ]
    ],
    [
        "ext.kartographer.data",
        ""
    ],
    [
        "ext.kartographer.dialog",
        "",
        [
            455,
            192,
            197,
            202,
            214
        ]
    ],
    [
        "ext.kartographer.util",
        "",
        [
            452
        ]
    ],
    [
        "ext.kartographer.frame",
        "",
        [
            458,
            192
        ]
    ],
    [
        "ext.kartographer.preview",
        ""
    ],
    [
        "ext.kartographer.editing",
        "",
        [
            38
        ]
    ],
    [
        "ext.kartographer.editor",
        "",
        [
            458,
            456
        ]
    ],
    [
        "ext.kartographer.visualEditor",
        "",
        [
            463,
            327,
            216
        ]
    ],
    [
        "ext.kartographer.specialMap",
        ""
    ],
    [
        "ext.popups.icons",
        ""
    ],
    [
        "ext.popups",
        ""
    ],
    [
        "ext.popups.main",
        "",
        [
            72,
            79,
            64,
            73
        ]
    ],
    [
        "ext.smw",
        "",
        [
            479
        ]
    ],
    [
        "ext.smw.styles",
        ""
    ],
    [
        "smw.ui",
        "",
        [
            473,
            476
        ]
    ],
    [
        "smw.ui.styles",
        ""
    ],
    [
        "smw.summarytable",
        ""
    ],
    [
        "ext.smw.special.styles",
        ""
    ],
    [
        "ext.jquery.async",
        ""
    ],
    [
        "ext.smw.query",
        "",
        [
            473,
            75
        ]
    ],
    [
        "ext.smw.api",
        "",
        [
            480,
            65,
            64
        ]
    ],
    [
        "ext.jquery.autocomplete",
        ""
    ],
    [
        "ext.smw.tooltip.styles",
        ""
    ],
    [
        "ext.smw.tooltip",
        "",
        [
            473,
            483,
            38
        ]
    ],
    [
        "ext.smw.autocomplete",
        "",
        [
            "jquery.ui.autocomplete"
        ]
    ],
    [
        "ext.smw.purge",
        "",
        [
            38
        ]
    ],
    [
        "ext.smw.vtabs.styles",
        ""
    ],
    [
        "ext.smw.vtabs",
        ""
    ],
    [
        "ext.smw.modal.styles",
        ""
    ],
    [
        "ext.smw.modal",
        ""
    ],
    [
        "smw.special.search.styles",
        ""
    ],
    [
        "smw.special.search",
        "",
        [
            474,
            475
        ]
    ],
    [
        "ext.smw.postproc",
        "",
        [
            38
        ]
    ],
    [
        "ext.smw.suggester",
        "",
        [
            473
        ]
    ],
    [
        "ext.smw.suggester.textInput",
        "",
        [
            494
        ]
    ],
    [
        "ext.smw.autocomplete.page",
        "",
        [
            482,
            75
        ]
    ],
    [
        "ext.smw.autocomplete.property",
        "",
        [
            482,
            75
        ]
    ],
    [
        "ext.smw.ask.styles",
        ""
    ],
    [
        "ext.smw.ask",
        "",
        [
            498,
            474,
            494,
            484
        ]
    ],
    [
        "ext.smw.table.styles",
        ""
    ],
    [
        "ext.smw.factbox.styles",
        ""
    ],
    [
        "ext.smw.factbox",
        ""
    ],
    [
        "ext.smw.browse.styles",
        ""
    ],
    [
        "ext.smw.browse",
        "",
        [
            474,
            38
        ]
    ],
    [
        "ext.smw.browse.autocomplete",
        "",
        [
            496,
            504
        ]
    ],
    [
        "ext.smw.admin",
        "",
        [
            38,
            519
        ]
    ],
    [
        "smw.special.facetedsearch.styles",
        ""
    ],
    [
        "smw.special.facetedsearch",
        "",
        [
            521,
            507
        ]
    ],
    [
        "ext.smw.personal",
        "",
        [
            484
        ]
    ],
    [
        "smw.tableprinter.datatable",
        "",
        [
            480,
            524
        ]
    ],
    [
        "smw.tableprinter.datatable.styles",
        ""
    ],
    [
        "ext.smw.deferred.styles",
        ""
    ],
    [
        "ext.smw.deferred",
        "",
        [
            38,
            521
        ]
    ],
    [
        "ext.smw.page.styles",
        ""
    ],
    [
        "smw.property.page",
        "",
        [
            484,
            519
        ]
    ],
    [
        "smw.content.schema",
        ""
    ],
    [
        "smw.content.schemaview",
        "",
        [
            519
        ]
    ],
    [
        "smw.jsonview.styles",
        ""
    ],
    [
        "smw.jsonview",
        "",
        [
            473
        ]
    ],
    [
        "smw.entityexaminer",
        "",
        [
            473,
            38
        ]
    ],
    [
        "onoi.rangeslider",
        ""
    ],
    [
        "onoi.blobstore",
        ""
    ],
    [
        "onoi.clipboard",
        ""
    ],
    [
        "onoi.dataTables",
        ""
    ],
    [
        "wgl.theme.dark",
        "",
        [],
        0
    ],
    [
        "wg.darkmode",
        "",
        [],
        0
    ],
    [
        "wgl.theme.light",
        "",
        [],
        0
    ],
    [
        "wgl.theme.browntown",
        "",
        [],
        0
    ],
    [
        "ext.cite.referencePreviews",
        "",
        [
            472
        ]
    ],
    [
        "ext.gadget.rsw-util",
        "",
        [
            75
        ],
        2
    ],
    [
        "ext.gadget.Less",
        "",
        [
            38
        ],
        2
    ],
    [
        "ext.gadget.switch-infobox",
        "",
        [
            530
        ],
        2
    ],
    [
        "ext.gadget.switch-infobox-styles",
        "",
        [],
        2
    ],
    [
        "ext.gadget.exchangePages",
        "",
        [],
        2
    ],
    [
        "ext.gadget.exchangePages-core",
        "",
        [
            530,
            194
        ],
        2
    ],
    [
        "ext.gadget.GECharts",
        "",
        [],
        2
    ],
    [
        "ext.gadget.GECharts-core",
        "",
        [
            530,
            197,
            202
        ],
        2
    ],
    [
        "ext.gadget.compare",
        "",
        [],
        2
    ],
    [
        "ext.gadget.compare-core",
        "",
        [
            530,
            202
        ],
        2
    ],
    [
        "ext.gadget.autosort",
        "",
        [
            530
        ],
        2
    ],
    [
        "ext.gadget.uncheckfileredirects",
        "",
        [],
        2
    ],
    [
        "ext.gadget.highlightTable",
        "",
        [],
        2
    ],
    [
        "ext.gadget.highlightTable-core",
        "",
        [
            530,
            194
        ],
        2
    ],
    [
        "ext.gadget.titleparenthesis",
        "",
        [],
        2
    ],
    [
        "ext.gadget.tooltips",
        "",
        [],
        2
    ],
    [
        "ext.gadget.topIcons",
        "",
        [
            530
        ],
        2
    ],
    [
        "ext.gadget.Username",
        "",
        [],
        2
    ],
    [
        "ext.gadget.countdown",
        "",
        [],
        2
    ],
    [
        "ext.gadget.autocollapse",
        "",
        [],
        2
    ],
    [
        "ext.gadget.checkboxList",
        "",
        [],
        2
    ],
    [
        "ext.gadget.checkboxList-core",
        "",
        [
            530
        ],
        2
    ],
    [
        "ext.gadget.Charts",
        "",
        [],
        2
    ],
    [
        "ext.gadget.Charts-core",
        "",
        [
            530
        ],
        2
    ],
    [
        "ext.gadget.navbox-tracking",
        "",
        [],
        2
    ],
    [
        "ext.gadget.sidebar-tracking",
        "",
        [],
        2
    ],
    [
        "ext.gadget.wikisync",
        "",
        [],
        2
    ],
    [
        "ext.gadget.wikisync-core",
        "",
        [
            530,
            197,
            202
        ],
        2
    ],
    [
        "ext.gadget.smwlistsfull",
        "",
        [],
        2
    ],
    [
        "ext.gadget.smwlistsfull-core",
        "",
        [
            164,
            22
        ],
        2
    ],
    [
        "ext.gadget.tooltipPopup",
        "",
        [],
        2
    ],
    [
        "ext.gadget.tooltipPopup-core",
        "",
        [],
        2
    ],
    [
        "ext.gadget.jsonDoc",
        "",
        [
            75
        ],
        2
    ],
    [
        "ext.gadget.articlefeedback",
        "",
        [],
        2
    ],
    [
        "ext.gadget.articlefeedback-core",
        "",
        [
            530,
            197,
            214
        ],
        2
    ],
    [
        "ext.gadget.articlefeedback-tools",
        "",
        [
            202
        ],
        2
    ],
    [
        "ext.gadget.sitenotice",
        "",
        [
            73
        ],
        2
    ],
    [
        "ext.gadget.calc",
        "",
        [],
        2
    ],
    [
        "ext.gadget.calc-core",
        "",
        [
            530,
            164
        ],
        2
    ],
    [
        "ext.gadget.infoboxQty",
        "",
        [
            530
        ],
        2
    ],
    [
        "ext.gadget.calculatorNS",
        "",
        [
            75
        ],
        2
    ],
    [
        "ext.gadget.dropDisplay",
        "",
        [],
        2
    ],
    [
        "ext.gadget.dropDisplay-core",
        "",
        [
            530,
            197,
            202
        ],
        2
    ],
    [
        "ext.gadget.mmgkc",
        "",
        [],
        2
    ],
    [
        "ext.gadget.mmgkc-core",
        "",
        [
            197,
            214
        ],
        2
    ],
    [
        "ext.gadget.fightcaverotations",
        "",
        [],
        2
    ],
    [
        "ext.gadget.fightcaverotations-core",
        "",
        [],
        2
    ],
    [
        "ext.gadget.livePricesMMG",
        "",
        [],
        2
    ],
    [
        "ext.gadget.livePricesMMG-core",
        "",
        [
            197,
            214
        ],
        2
    ],
    [
        "ext.gadget.autowelcome",
        "",
        [
            530
        ],
        2
    ],
    [
        "ext.gadget.contributions",
        "",
        [
            530
        ],
        2
    ],
    [
        "ext.gadget.editCount",
        "",
        [
            530
        ],
        2
    ],
    [
        "ext.gadget.code-snippets",
        "",
        [
            75
        ],
        2
    ],
    [
        "ext.gadget.skinTogglesNew",
        "",
        [
            530
        ],
        2
    ],
    [
        "ext.gadget.skinTogglesNew-prompt",
        "",
        [],
        2
    ],
    [
        "ext.gadget.utcclock",
        "",
        [
            583
        ],
        2
    ],
    [
        "ext.gadget.relativetime",
        "",
        [
            75
        ],
        2
    ],
    [
        "ext.gadget.toplinksDropdown",
        "",
        [],
        2
    ],
    [
        "ext.gadget.toplinksDropdown-styles",
        "",
        [],
        2
    ],
    [
        "ext.gadget.sectionAnchors",
        "",
        [],
        2
    ],
    [
        "ext.gadget.audioplayer",
        "",
        [],
        2
    ],
    [
        "ext.gadget.audioplayer-core",
        "",
        [],
        2
    ],
    [
        "ext.gadget.musicmap",
        "",
        [],
        2
    ],
    [
        "ext.gadget.musicmap-core",
        "",
        [
            591,
            194
        ],
        2
    ],
    [
        "ext.gadget.equipment",
        "",
        [],
        2
    ],
    [
        "ext.gadget.stickyTableHeaders",
        "",
        [],
        2
    ],
    [
        "ext.gadget.falseSubpage",
        "",
        [],
        2
    ],
    [
        "ext.gadget.colorRC",
        "",
        [],
        2
    ],
    [
        "ext.gadget.readableRC",
        "",
        [],
        2
    ],
    [
        "ext.gadget.readableRC-core",
        "",
        [
            194
        ],
        2
    ],
    [
        "ext.gadget.ringbell",
        "",
        [],
        2
    ],
    [
        "ext.gadget.hideRCsidebar",
        "",
        [],
        2
    ],
    [
        "ext.gadget.headerTargetHighlight",
        "",
        [],
        2
    ],
    [
        "ext.gadget.stickyheader",
        "",
        [
            75
        ],
        2
    ],
    [
        "ext.gadget.abuseLogRC",
        "",
        [],
        2
    ],
    [
        "ext.gadget.abuseLogRC-core",
        "",
        [
            194
        ],
        2
    ],
    [
        "ext.gadget.dropdown",
        "",
        [
            38
        ],
        2
    ],
    [
        "ext.gadget.newPage",
        "",
        [
            530
        ],
        2
    ],
    [
        "ext.gadget.purge",
        "",
        [
            530,
            38
        ],
        2
    ],
    [
        "ext.gadget.hotcat",
        "",
        [],
        2
    ],
    [
        "ext.gadget.ReferenceTooltips",
        "",
        [
            78,
            13
        ],
        2
    ],
    [
        "ext.gadget.fileDownload",
        "",
        [],
        2
    ],
    [
        "ext.gadget.batchupload",
        "",
        [
            75
        ],
        2
    ],
    [
        "ext.gadget.LazyAdminTools",
        "",
        [],
        2
    ],
    [
        "ext.gadget.LazyAdminTools-core",
        "",
        [
            194
        ],
        2
    ],
    [
        "ext.gadget.QuickDiff",
        "",
        [
            75
        ],
        2
    ],
    [
        "ext.gadget.Message-names",
        "",
        [
            75
        ],
        2
    ],
    [
        "ext.gadget.oswf",
        "",
        [],
        2
    ],
    [
        "ext.gadget.oswf-core",
        "",
        [
            194,
            219
        ],
        2
    ],
    [
        "ext.gadget.ezcopy",
        "",
        [],
        2
    ],
    [
        "ext.gadget.table-csv",
        "",
        [],
        2
    ],
    [
        "ext.gadget.scribunto-console",
        "",
        [],
        2
    ],
    [
        "ext.gadget.scribunto-console-core",
        "",
        [],
        2
    ],
    [
        "ext.gadget.searchfocus",
        "",
        [],
        2
    ],
    [
        "ext.gadget.sigreminder",
        "",
        [],
        2
    ],
    [
        "ext.gadget.sigreminder-core",
        "",
        [
            530
        ],
        2
    ],
    [
        "ext.gadget.defaultsummaries",
        "",
        [
            194
        ],
        2
    ],
    [
        "ext.gadget.showAdvancedData",
        "",
        [],
        2
    ],
    [
        "ext.gadget.gadgetLinks",
        "",
        [],
        2
    ],
    [
        "ext.gadget.crob",
        "",
        [
            530
        ],
        2
    ],
    [
        "ext.gadget.clippy",
        "",
        [],
        2
    ],
    [
        "ext.gadget.switch-infobox-sandbox",
        "",
        [
            530
        ],
        2
    ],
    [
        "ext.gadget.GECharts-sandbox-loader",
        "",
        [],
        2
    ],
    [
        "ext.gadget.GECharts-sandbox",
        "",
        [
            530,
            197,
            202
        ],
        2
    ],
    [
        "ext.gadget.wikisync-dev",
        "",
        [],
        2
    ],
    [
        "ext.gadget.wikisync-dev-core",
        "",
        [
            530,
            197,
            202
        ],
        2
    ],
    [
        "ext.gadget.trailblazer-modal",
        "",
        [
            194
        ],
        2
    ],
    [
        "ext.gadget.trailblazer",
        "",
        [
            530
        ],
        2
    ],
    [
        "ext.gadget.tilemarkers",
        "",
        [],
        2
    ],
    [
        "ext.gadget.tilemarkers-core",
        "",
        [
            194
        ],
        2
    ],
    [
        "ext.gadget.loadout",
        "",
        [],
        2
    ],
    [
        "ext.gadget.loadout-core",
        "",
        [
            194
        ],
        2
    ],
    [
        "ext.gadget.dps",
        "",
        [],
        2
    ],
    [
        "ext.gadget.dps-core",
        "",
        [
            210,
            164
        ],
        2
    ],
    [
        "ext.gadget.leaguefilter",
        "",
        [],
        2
    ],
    [
        "ext.gadget.leaguefilter-core",
        "",
        [
            194
        ],
        2
    ],
    [
        "ext.pygments.view",
        "",
        [
            65
        ]
    ],
    [
        "jquery.uls.data",
        ""
    ],
    [
        "ext.echo.emailicons",
        ""
    ],
    [
        "ext.echo.secondaryicons",
        ""
    ],
    [
        "mediawiki.messagePoster",
        "",
        [
            47
        ]
    ]
]);

		// First set page-specific config needed by mw.loader (wgUserName)
		mw.config.set( window.RLCONF || {} );
		mw.loader.state( window.RLSTATE || {} );
		mw.loader.load( window.RLPAGEMODULES || [] );

		// Process RLQ callbacks
		//
		// The code in these callbacks could've been exposed from load.php and
		// requested client-side. Instead, they are pushed by the server directly
		// (from ResourceLoaderClientHtml and other parts of MediaWiki). This
		// saves the need for additional round trips. It also allows load.php
		// to remain stateless and sending personal data in the HTML instead.
		//
		// The HTML inline script lazy-defines the 'RLQ' array. Now that we are
		// processing it, replace it with an implementation where 'push' actually
		// considers executing the code directly. This is to ensure any late
		// arrivals will also be processed. Late arrival can happen because
		// startup.js is executed asynchronously, concurrently with the streaming
		// response of the HTML.
		queue = window.RLQ || [];
		// Replace RLQ with an empty array, then process the things that were
		// in RLQ previously. We have to do this to avoid an infinite loop:
		// non-function items are added back to RLQ by the processing step.
		RLQ = [];
		RLQ.push = function ( fn ) {
			if ( typeof fn === 'function' ) {
				fn();
			} else {
				// If the first parameter is not a function, then it is an array
				// containing a list of required module names and a function.
				// Do an actual push for now, as this signature is handled
				// later by mediawiki.base.js.
				RLQ[ RLQ.length ] = fn;
			}
		};
		while ( queue[ 0 ] ) {
			// Process all values gathered so far
			RLQ.push( queue.shift() );
		}

		// Clear and disable the basic (Grade C) queue.
		NORLQ = {
			push: function () {}
		};
	}() );
}
mw.loader.state({
    "startup": "ready"
});