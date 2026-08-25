/**
 * In-article TimedMediaHandler audio: prefer the saved MPEG transcode, paint a
 * full-width play/time/seek chrome, and leave loading with an explicit error
 * instead of spinning.
 */
(function (global) {
  'use strict';

  var osrsArticleAudioLoadingTimeoutMs = 8000;
  global.osrsArticleAudioLoadingTimeoutMs = osrsArticleAudioLoadingTimeoutMs;

  function preferredMpegSource(audio) {
    if (!audio || !audio.querySelectorAll) return null;
    var sources = audio.querySelectorAll('source');
    for (var i = 0; i < sources.length; i++) {
      var type = (sources[i].getAttribute('type') || '').toLowerCase();
      var src = sources[i].getAttribute('src') || '';
      if (type.indexOf('audio/mpeg') === 0 || /\.mp3(\?|#|$)/i.test(src)) {
        return sources[i];
      }
    }
    return null;
  }

  function hasClass(el, name) {
    if (!el) return false;
    if (el.classList && el.classList.contains) return el.classList.contains(name);
    return (' ' + (el.className || '') + ' ').indexOf(' ' + name + ' ') !== -1;
  }

  function mediaHost(audio) {
    var node = audio && audio.parentNode;
    while (node && node.nodeType === 1) {
      if (hasClass(node, 'infobox-media-player')) return node;
      if (hasClass(node, 'musicplayer')) {
        if (String(node.tagName || '').toUpperCase() === 'TABLE') {
          return node.querySelector('td') || node;
        }
        return node;
      }
      node = node.parentNode;
    }
    return audio ? audio.parentNode : null;
  }

  function formatTime(seconds) {
    if (!isFinite(seconds) || seconds < 0) seconds = 0;
    seconds = Math.floor(seconds + 0.5);
    var m = Math.floor(seconds / 60);
    var s = seconds % 60;
    return m + ':' + (s < 10 ? '0' : '') + s;
  }

  function durationSeconds(audio) {
    var d = audio && audio.duration;
    if (isFinite(d) && d > 0) return d;
    var hint = parseFloat((audio && audio.getAttribute('data-durationhint')) || '');
    return isFinite(hint) && hint > 0 ? hint : 0;
  }

  function showError(wrap, audio, errorEl) {
    if (!wrap) return;
    wrap.classList.add('is-error');
    if (errorEl) {
      errorEl.hidden = false;
      errorEl.style.display = 'block';
    }
    if (audio) {
      try { audio.pause(); } catch (e) {}
    }
  }

  function hideEmptyFileSpans(host, wrap) {
    if (!host || !host.querySelectorAll) return;
    var spans = host.querySelectorAll('span.mw-default-size');
    for (var i = 0; i < spans.length; i++) {
      if (wrap.contains(spans[i])) continue;
      if (spans[i].querySelector('audio')) continue;
      spans[i].style.display = 'none';
    }
  }

  var PLAY_PATH = 'M8 5.14v13.72L19.5 12 8 5.14z';
  var PAUSE_PATH = 'M6 5h4v14H6V5zm8 0h4v14h-4V5z';

  function mediaIcon(pathD) {
    var ns = 'http://www.w3.org/2000/svg';
    var svg = document.createElementNS(ns, 'svg');
    svg.setAttribute('viewBox', '0 0 24 24');
    svg.setAttribute('width', '22');
    svg.setAttribute('height', '22');
    svg.setAttribute('aria-hidden', 'true');
    svg.style.display = 'block';
    var path = document.createElementNS(ns, 'path');
    path.setAttribute('d', pathD);
    path.setAttribute('fill', 'currentColor');
    svg.appendChild(path);
    return svg;
  }

  function enhanceAudio(audio) {
    if (!audio || audio.dataset.osrsArticleAudio === '1') return;
    audio.dataset.osrsArticleAudio = '1';

    var mpeg = preferredMpegSource(audio);
    if (mpeg && mpeg.parentNode === audio) {
      audio.insertBefore(mpeg, audio.firstChild);
    }

    var host = mediaHost(audio);
    if (!host) return;
    var wrap = document.createElement('div');
    wrap.className = 'osrs-article-audio';
    wrap.style.cssText = [
      'display:block',
      'box-sizing:border-box',
      'width:100%',
      'max-width:100%',
      'min-width:0',
      'position:relative'
    ].join(';');
    if (audio.parentNode === host) {
      host.insertBefore(wrap, audio);
    } else {
      host.insertBefore(wrap, host.firstChild);
    }
    wrap.appendChild(audio);
    var hostTag = String(host.tagName || '').toUpperCase();
    if (hostTag === 'TD' || hostTag === 'TH') {
      host.style.display = 'table-cell';
      host.style.width = '100%';
      host.style.maxWidth = '100%';
      host.style.minWidth = '0';
    }
    hideEmptyFileSpans(host, wrap);

    var chrome = document.createElement('div');
    chrome.className = 'osrs-article-audio-chrome';
    chrome.style.cssText = [
      'display:flex',
      'align-items:center',
      'gap:6px',
      'box-sizing:border-box',
      'width:100%',
      'max-width:100%',
      'min-width:0',
      'min-height:44px',
      'padding:2px 8px 2px 2px',
      'border:1px solid var(--body-border, #94866d)',
      'border-radius:10px',
      'background:var(--body-main, #e2dbc8)',
      'color:var(--text-color, #000)'
    ].join(';');

    var playBtn = document.createElement('button');
    playBtn.type = 'button';
    playBtn.className = 'osrs-article-audio-play';
    playBtn.setAttribute('aria-label', 'Play audio');
    playBtn.setAttribute('aria-pressed', 'false');
    playBtn.style.cssText = [
      'flex:0 0 auto',
      'display:flex',
      'align-items:center',
      'justify-content:center',
      'margin:0',
      'padding:0',
      'width:44px',
      'height:44px',
      'min-height:44px',
      'min-width:44px',
      'border:0',
      'border-radius:22px',
      'background:transparent',
      'color:inherit',
      'cursor:pointer'
    ].join(';');
    playBtn.appendChild(mediaIcon(PLAY_PATH));

    var timeEl = document.createElement('span');
    timeEl.className = 'osrs-article-audio-time';
    timeEl.setAttribute('aria-label', 'Elapsed time');
    timeEl.style.cssText = [
      'flex:0 0 auto',
      'font:inherit',
      'font-size:12px',
      'font-variant-numeric:tabular-nums',
      'white-space:nowrap',
      'min-width:2.6em',
      'opacity:0.85'
    ].join(';');

    var seek = document.createElement('input');
    seek.type = 'range';
    seek.className = 'osrs-article-audio-seek';
    seek.min = '0';
    seek.step = 'any';
    seek.value = '0';
    seek.setAttribute('aria-label', 'Seek');
    seek.style.cssText = [
      'flex:1 1 auto',
      'min-width:72px',
      'width:100%',
      'height:24px',
      'margin:0'
    ].join(';');

    var durationEl = document.createElement('span');
    durationEl.className = 'osrs-article-audio-duration';
    durationEl.setAttribute('aria-label', 'Duration');
    durationEl.style.cssText = [
      'flex:0 0 auto',
      'font:inherit',
      'font-size:12px',
      'font-variant-numeric:tabular-nums',
      'white-space:nowrap',
      'min-width:2.6em',
      'opacity:0.85'
    ].join(';');

    chrome.appendChild(playBtn);
    chrome.appendChild(timeEl);
    chrome.appendChild(seek);
    chrome.appendChild(durationEl);
    wrap.insertBefore(chrome, audio);

    if (audio.hasAttribute('controls')) {
      audio.removeAttribute('controls');
    }
    audio.setAttribute('controlslist', 'nodownload nofullscreen noremoteplayback');
    audio.classList.add('osrs-article-audio-native');
    audio.style.cssText = [
      'position:absolute',
      'width:1px',
      'height:1px',
      'padding:0',
      'margin:0',
      'overflow:hidden',
      'clip:rect(0 0 0 0)',
      'clip-path:inset(50%)',
      'border:0',
      'opacity:0',
      'pointer-events:none'
    ].join(';');

    var errorEl = document.createElement('div');
    errorEl.className = 'osrs-article-audio-error';
    errorEl.setAttribute('role', 'status');
    errorEl.textContent = 'Audio unavailable';
    errorEl.hidden = true;
    errorEl.style.display = 'none';
    errorEl.style.margin = '0.35em 0';
    errorEl.style.fontSize = '0.9em';
    wrap.appendChild(errorEl);

    function syncTime() {
      var dur = durationSeconds(audio);
      seek.max = String(dur || 0);
      timeEl.textContent = formatTime(audio.currentTime || 0);
      durationEl.textContent = formatTime(dur);
    }
    syncTime();

    function setPlayingUi(playing) {
      while (playBtn.firstChild) playBtn.removeChild(playBtn.firstChild);
      playBtn.appendChild(mediaIcon(playing ? PAUSE_PATH : PLAY_PATH));
      playBtn.setAttribute('aria-label', playing ? 'Pause audio' : 'Play audio');
      playBtn.setAttribute('aria-pressed', playing ? 'true' : 'false');
    }

    function applyMpegAndPlay() {
      audio.dataset.osrsPlayAttempted = '1';
      var mpegNow = preferredMpegSource(audio);
      if (mpegNow) {
        var mpegSrc = mpegNow.getAttribute('src');
        if (mpegSrc && audio.getAttribute('src') !== mpegSrc) {
          var pos = audio.currentTime || 0;
          audio.src = mpegSrc;
          if (pos > 0) {
            try { audio.currentTime = pos; } catch (e) {}
          }
        }
      }
      var start = audio.play();
      if (start && typeof start.catch === 'function') {
        start.catch(function () {
          showError(wrap, audio, errorEl);
          setPlayingUi(false);
        });
      }
    }

    playBtn.addEventListener('click', function () {
      if (!audio.paused && !audio.ended) {
        try { audio.pause(); } catch (e) {}
        setPlayingUi(false);
        return;
      }
      applyMpegAndPlay();
    });

    var seeking = false;
    seek.addEventListener('input', function () {
      seeking = true;
      var next = parseFloat(seek.value);
      if (isFinite(next)) {
        try { audio.currentTime = next; } catch (e) {}
        syncTime();
      }
    });
    seek.addEventListener('change', function () {
      seeking = false;
      var next = parseFloat(seek.value);
      if (isFinite(next)) {
        try { audio.currentTime = next; } catch (e) {}
      }
      syncTime();
    });

    var timer = null;
    function clearLoadingTimer() {
      if (timer) {
        clearTimeout(timer);
        timer = null;
      }
    }
    function markPlayAttempt() {
      audio.dataset.osrsPlayAttempted = '1';
    }
    function armLoadingTimeout() {
      if (audio.dataset.osrsPlayAttempted !== '1') return;
      clearLoadingTimer();
      timer = setTimeout(function () {
        if (audio.readyState < 2 && !audio.ended) {
          showError(wrap, audio, errorEl);
        }
      }, osrsArticleAudioLoadingTimeoutMs);
    }

    audio.addEventListener('play', function () {
      markPlayAttempt();
      armLoadingTimeout();
      setPlayingUi(true);
    });
    audio.addEventListener('pause', function () {
      setPlayingUi(false);
    });
    audio.addEventListener('ended', function () {
      setPlayingUi(false);
      syncTime();
    });
    audio.addEventListener('timeupdate', function () {
      if (!seeking) syncTime();
    });
    audio.addEventListener('loadedmetadata', syncTime);
    audio.addEventListener('durationchange', syncTime);
    audio.addEventListener('error', function () {
      if (audio.dataset.osrsPlayAttempted !== '1') return;
      clearLoadingTimer();
      showError(wrap, audio, errorEl);
      setPlayingUi(false);
    });
    audio.addEventListener('waiting', armLoadingTimeout);
    audio.addEventListener('stalled', armLoadingTimeout);
    audio.addEventListener('playing', clearLoadingTimer);
    audio.addEventListener('canplay', clearLoadingTimer);
    audio.addEventListener('loadeddata', clearLoadingTimer);
  }

  function enhance(root) {
    var scope = root || (typeof document !== 'undefined' ? document : null);
    if (!scope || !scope.querySelectorAll) return;
    var nodes = scope.querySelectorAll(
      '.infobox-media-player audio, audio.mw-file-element, .musicplayer audio, audio[controls]'
    );
    for (var i = 0; i < nodes.length; i++) {
      enhanceAudio(nodes[i]);
    }
  }

  global.OSRSArticleAudio = {
    preferredMpegSource: preferredMpegSource,
    enhance: enhance
  };

  if (typeof document !== 'undefined') {
    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', function () { enhance(document); });
    } else {
      enhance(document);
    }
  }
})(typeof window !== 'undefined' ? window : globalThis);
