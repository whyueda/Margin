// Loaded before everything else on each page: any error is written to Margin's log (for Copy Diagnostics)
// and shown briefly at the bottom of the window, instead of a button silently doing nothing.
(() => {
  const send = msg => { try { window.webkit.messageHandlers.api.postMessage({ cmd: 'log', msg: String(msg).slice(0, 500) }); } catch (_) {} };
  let box = null, timer = 0;
  const show = msg => {
    if (!document.body) return;
    if (!box) {
      box = document.createElement('div');
      box.setAttribute('role', 'alert');
      box.style.cssText = 'position:fixed;left:12px;right:12px;bottom:12px;z-index:99999;padding:9px 12px;border-radius:10px;' +
        'background:rgba(190,40,40,.94);color:#fff;font:12.5px/1.35 -apple-system,system-ui,sans-serif;' +
        'box-shadow:0 6px 20px rgba(0,0,0,.25);pointer-events:none;transition:opacity .25s;opacity:0';
      document.body.appendChild(box);
    }
    box.textContent = msg;
    box.style.opacity = '1';
    clearTimeout(timer);
    timer = setTimeout(() => { box.style.opacity = '0'; }, 6000);
  };
  window.showError = show;
  const where = e => (e.filename ? ' (' + e.filename.split('/').pop() + ':' + e.lineno + ')' : '');
  window.addEventListener('error', e => {
    if (!e.message) return; // a failed image or file inside a note, not a problem with Margin
    send('page error: ' + e.message + where(e));
    show('Something went wrong: ' + e.message);
  });
  window.addEventListener('unhandledrejection', e => {
    const m = (e.reason && e.reason.message) || String(e.reason);
    send('failed: ' + m);
    show(m);
  });
})();
