const $ = s => document.querySelector(s);
const api = (cmd, a = {}) => window.webkit.messageHandlers.api.postMessage({ cmd, ...a });
const el = (tag, cls, text) => { const e = document.createElement(tag); if (cls) e.className = cls; if (text != null) e.textContent = text; return e; };

const I = {
  plus: '<path d="M12 5v14M5 12h14"/>',
  imp: '<path d="M12 4v11M7.5 10.8L12 15.3l4.5-4.5M5 19.5h14"/>',
  x: '<path d="M6.5 6.5l11 11M17.5 6.5l-11 11"/>',
  chev: '<path d="M6 9.5l6 6 6-6"/>',
  back: '<path d="M14.5 5.5L8 12l6.5 6.5"/>',
  more: '<circle cx="5.5" cy="12" r="1.2" fill="currentColor"/><circle cx="12" cy="12" r="1.2" fill="currentColor"/><circle cx="18.5" cy="12" r="1.2" fill="currentColor"/>',
  search: '<circle cx="11" cy="11" r="6.5"/><path d="M20 20l-4.2-4.2"/>',
  folder: '<path d="M3.5 8a2.5 2.5 0 012.5-2.5h3.2l2 2.2H18A2.5 2.5 0 0120.5 10v6.5A2.5 2.5 0 0118 19H6a2.5 2.5 0 01-2.5-2.5z"/>',
  check: '<path d="M5 12.5l4.5 4.5L19 7.5"/>',
  link: '<path d="M10 14a4 4 0 005.7 0l3-3a4 4 0 00-5.7-5.7l-1 1"/><path d="M14 10a4 4 0 00-5.7 0l-3 3a4 4 0 005.7 5.7l1-1"/>',
  table: '<rect x="3.500" y="5" width="17" height="14" rx="3"/><path d="M3.500 10h17M3.500 14.500h17M10 5v14"/>',
  clip: '<path d="M20 11.5l-8 8a5 5 0 01-7-7l8.5-8.5a3.300 3.300 0 014.700 4.700L9.800 17a1.700 1.700 0 01-2.400-2.400l7.600-7.600"/>',
  todo: '<rect x="4" y="4" width="16" height="16" rx="5"/><path d="M8.500 12.300l2.500 2.500 4.500-5"/>',
  copy: '<rect x="9" y="9" width="11" height="11" rx="2.5"/><path d="M5.500 15H5a2 2 0 01-2-2V5a2 2 0 012-2h8a2 2 0 012 2v.5"/>',
  doc: '<path d="M14 3H7a2 2 0 00-2 2v14a2 2 0 002 2h10a2 2 0 002-2V8zM14 3v5h5M9 13h6M9 17h4"/>',
  trash: '<path d="M5 7h14M10 7V5h4v2M7 7l.8 12h8.400L17 7"/>',
  gear: '<path d="M4 7.500h9M18.500 7.500H20M4 16.500h1.500M11 16.500h9"/><circle cx="15.700" cy="7.500" r="2.300"/><circle cx="8.300" cy="16.500" r="2.300"/>',
  win: '<rect x="3.5" y="7.5" width="13" height="12.5" rx="3"/><path d="M8 4h9.5a3 3 0 013 3v9"/>',
  eye: '<path d="M4 6.500h6l2 2h8v9.500H4z"/><path d="M12 15.500v-4M10 13l2-2 2 2"/>',
};
const icon = (n, s = 18) => `<svg width="${s}" height="${s}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">${I[n]}</svg>`;
document.querySelectorAll('[data-icon]').forEach(e => e.insertAdjacentHTML('afterbegin', icon(e.dataset.icon, +e.dataset.size || 18)));
// The whole top strip of a window moves it, not only the gaps between buttons.
document.querySelectorAll('.bar').forEach(b => b.prepend(el('i', 'dragzone')));

const state = { root: null, rootDisplay: '', envs: [], env: '', cats: [], notes: [], filter: null, query: '', note: null, dirty: false, view: '', envStyles: {} };
const editor = $('#editor');
const ctx = () => ({ env: state.env, cat: state.note ? state.note.category : '' });
document.execCommand('defaultParagraphSeparator', false, 'p');
document.execCommand('styleWithCSS', false, false);

// ---------- Views ----------

function showView(id) {
  state.view = id;
  if (typeof selectImg === 'function' && selImg) selectImg(null);
  for (const v of document.querySelectorAll('.view')) {
    v.classList.toggle('active', v.id === id);
    v.classList.toggle('past', v.id === 'listView' && (id === 'editorView' || id === 'settingsView'));
  }
  closePop();
  setTimeout(() => { if (typeof reportTyping === 'function') reportTyping(); }, 0);
}

function apply(s) {
  Object.assign(state, { root: s.root || null, rootDisplay: s.rootDisplay || '', envs: s.envs, env: s.env, envStyles: s.envStyles || {} });
  if (s.glow) globalGlow = s.glow;
  $('#envName').textContent = state.env;
  paintEnv();
}

async function refresh() {
  const s = await api('state');
  // Each window keeps the environment it is looking at, even if another window switched.
  if (state.env && s.envs.includes(state.env)) s.env = state.env;
  apply(s);
  if (!state.root) return showView('welcome');
  await loadNotes();
  if (state.view !== 'editorView' && state.view !== 'settingsView') showView('listView');
}

async function loadNotes(animate = true) {
  const r = await api('list', { env: state.env });
  state.cats = r.categories;
  state.notes = r.notes;
  if (state.filter && !state.cats.includes(state.filter)) state.filter = null;
  renderList(animate);
}

// ---------- List ----------

function ago(ms) {
  const s = (Date.now() - ms) / 1000;
  if (s < 60) return 'just now';
  if (s < 3600) return Math.floor(s / 60) + ' min ago';
  if (s < 86400) return Math.floor(s / 3600) + ' h ago';
  if (s < 86400 * 7) { const d = Math.floor(s / 86400); return d + (d === 1 ? ' day ago' : ' days ago'); }
  return new Date(ms).toLocaleDateString(undefined, { month: 'short', day: 'numeric', year: 'numeric' });
}

const plain = t => (t || '')
  .replace(/!\[[^\]]*\]\([^)]*\)/g, ' Image ')
  .replace(/\[([^\]]*)\]\([^)]*\)/g, '$1')
  .replace(/^\s*([#>]+|[-*+]|\d+\.)\s+(\[[ xX]\]\s*)?/gm, '')
  .replace(/^\|?[\s:|-]+\|?$/gm, '')
  .replace(/<\/?u>|[*_`~\\|]/g, '')
  .replace(/\s+/g, ' ').trim();

function renderChips() {
  const chips = $('#chips');
  chips.innerHTML = '';
  const add = (label, value) => {
    const c = el('button', 'chip' + (state.filter === value ? ' on' : ''), label);
    c.onclick = () => { state.filter = value; renderList(); };
    chips.append(c);
  };
  add('All', null);
  state.cats.forEach(c => add(c, c));
  const plus = el('button', 'chip add');
  plus.title = 'New category';
  plus.innerHTML = icon('plus', 14);
  plus.onclick = () => {
    if (plus.querySelector('input')) return;
    plus.innerHTML = '';
    const inp = el('input');
    inp.placeholder = 'New category';
    plus.append(inp);
    inp.focus();
    inp.onkeydown = async e => {
      e.stopPropagation();
      if (e.key === 'Escape') return renderChips();
      if (e.key === 'Enter' && inp.value.trim()) {
        state.filter = await api('createCategory', { env: state.env, name: inp.value });
        await loadNotes();
      }
    };
    inp.onblur = () => setTimeout(renderChips, 120);
  };
  chips.append(plus);
}

function renderList(animate = true) {
  renderChips();
  const q = state.query.toLowerCase();
  const items = state.notes.filter(n =>
    (!state.filter || n.category === state.filter) &&
    (!q || n.title.toLowerCase().includes(q) || (n.preview || '').toLowerCase().includes(q)));
  $('#count').textContent = state.notes.length === 1 ? '1 note' : state.notes.length + ' notes';
  const list = $('#notes');
  list.innerHTML = '';
  if (!items.length) {
    const e = el('div', 'empty');
    e.innerHTML = q ? '<b>Nothing found</b>Try a different search.' : '<b>No notes yet</b><span class="hintkeys">Press <span class="key">⌘</span><span class="plus">+</span><span class="key">N</span> to write your first one</span>';
    list.append(e);
    return;
  }
  items.forEach((n, i) => {
    const b = el('button', 'note');
    if (animate) b.style.animationDelay = Math.min(i, 12) * 32 + 'ms'; else b.style.animation = 'none';
    const h = el('h3', '', n.title);
    if (n.icon && lucideHas(n.icon)) h.insertAdjacentHTML('afterbegin', `<span class="nico" style="color:${iconColor(n.iconColor)}">${lucide(n.icon, 16)}</span>`);
    b.append(h);
    const p = plain(n.preview);
    if (p) b.append(el('p', '', p));
    const meta = el('small');
    meta.append(el('span', '', 'Edited ' + ago(n.modified)));
    if (n.category && !state.filter) meta.append(el('span', 'tag', n.category));
    b.append(meta);
    const dots = el('span', 'dots');
    dots.title = 'More';
    dots.innerHTML = icon('more', 18);
    const menu = (anchor, align) => openPop(anchor, p => {
      p.append(item('Open in new window', { icon: 'win', onClick: () => { closePop(); openWindow(n.path); } }));
      p.append(item('Show in Finder', { icon: 'eye', onClick: () => { closePop(); api('reveal', { path: n.path }); } }));
      const d = item('Delete note', { icon: 'trash', danger: true });
      confirmDelete(d, async () => {
        closePop();
        await api('delete', { path: n.path });
        b.style.height = b.offsetHeight + 'px';
        void b.offsetHeight;
        b.classList.add('leaving');
        setTimeout(() => loadNotes(false), 340);
      });
      p.append(d);
    }, align);
    dots.onclick = e => { e.stopPropagation(); menu(dots, 'right'); };
    // Right-click anywhere on the note opens the same menu, at the pointer.
    b.oncontextmenu = e => {
      e.preventDefault();
      const r = new DOMRect(e.clientX, e.clientY - 6, 0, 0);
      menu({ getBoundingClientRect: () => r, contains: () => false }, 'left');
    };
    b.onmousedown = e => { if (e.button === 0 && !e.ctrlKey && !e.target.closest('.dots')) dragFrom = { x: e.clientX, y: e.clientY, path: n.path }; };
    b.append(dots);
    b.onclick = e => { if (justDragged) { justDragged = false; return; } e.metaKey ? openWindow(n.path) : openNote(n); };
    list.append(b);
  });
}

// Drag a note out of the window to hand its file to another app.
let dragFrom = null, justDragged = false;
document.addEventListener('mousedown', () => { justDragged = false; }, true);
document.addEventListener('mouseup', () => { dragFrom = null; });
document.addEventListener('mousemove', e => {
  if (!dragFrom) return;
  if (!(e.buttons & 1)) { dragFrom = null; return; }
  if (Math.hypot(e.clientX - dragFrom.x, e.clientY - dragFrom.y) < 7) return;
  const path = dragFrom.path;
  dragFrom = null;
  justDragged = true;
  closePop();
  api('dragNote', { path }).catch(() => {});
});

// Bring files in as notes: drop them on the list, or use the import button.
const importCat = () => state.filter || '';
async function importFiles(files) {
  let n = 0;
  for (const f of files) {
    const data = await new Promise(res => {
      const fr = new FileReader();
      fr.onload = () => res(String(fr.result).split(',')[1] || '');
      fr.onerror = () => res(null);
      fr.readAsDataURL(f);
    });
    if (data == null) continue;
    try { await api('importData', { env: state.env, category: importCat(), name: f.name, data }); n++; } catch (err) { api('log', { msg: 'import ' + f.name + ': ' + err }); }
  }
  if (n) await loadNotes();
  return n;
}
{
  const lv = $('#listView');
  let depth = 0;
  const has = e => e.dataTransfer && [...e.dataTransfer.types].includes('Files');
  lv.addEventListener('dragenter', e => { if (has(e)) { e.preventDefault(); depth++; lv.classList.add('dropping'); } });
  lv.addEventListener('dragover', e => { if (has(e)) { e.preventDefault(); e.dataTransfer.dropEffect = 'copy'; } });
  lv.addEventListener('dragleave', e => { if (has(e) && --depth <= 0) { depth = 0; lv.classList.remove('dropping'); } });
  lv.addEventListener('drop', e => {
    depth = 0;
    lv.classList.remove('dropping');
    if (!has(e)) return;
    e.preventDefault();
    importFiles([...e.dataTransfer.files]);
  });
  $('#impBtn').onclick = async () => {
    const added = await api('importPick', { env: state.env, category: importCat() });
    if (added && added.length) loadNotes();
  };
}

$('#search').oninput = e => { state.query = e.target.value; renderList(false); };

// ---------- Popover ----------

const pop = $('#pop');
let popAnchor = null;

function openPop(anchor, build, align = 'left') {
  if (popAnchor === anchor) return closePop();
  pop.innerHTML = '';
  pop.classList.remove('picker');
  build(pop);
  popAnchor = anchor;
  const r = anchor.getBoundingClientRect();
  const pw = pop.offsetWidth, ph = pop.offsetHeight;
  let left = align === 'right' ? r.right - pw : align === 'center' ? r.left + r.width / 2 - pw / 2 : r.left;
  left = Math.max(10, Math.min(left, innerWidth - pw - 10));
  let top = r.bottom + 8, oy = 'top';
  if (top + ph > innerHeight - 10) { top = Math.max(10, r.top - ph - 8); oy = 'bottom'; }
  pop.style.left = left + 'px';
  pop.style.top = top + 'px';
  pop.style.transformOrigin = `${Math.round(r.left + r.width / 2 - left)}px ${oy}`;
  requestAnimationFrame(() => { if (popAnchor === anchor) pop.classList.add('open'); });
}
function closePop() { pop.classList.remove('open'); popAnchor = null; setTimeout(() => { if (!popAnchor) pop.classList.remove('picker'); }, 180); }
document.addEventListener('mousedown', e => {
  if (popAnchor && !pop.contains(e.target) && !popAnchor.contains(e.target)) closePop();
});

function item(label, o = {}) {
  const b = el('button', 'item' + (o.danger ? ' danger' : ''));
  if (o.icon) b.insertAdjacentHTML('beforeend', icon(o.icon, 16));
  if (o.html) b.insertAdjacentHTML('beforeend', o.html);
  b.append(el('span', 'lbl', label));
  if (o.checked) b.insertAdjacentHTML('beforeend', `<span class="tick">${icon('check', 15)}</span>`);
  b.onmousedown = e => e.preventDefault();
  b.onclick = o.onClick;
  return b;
}
function field(placeholder, onSubmit, ic = 'plus') {
  const w = el('label', 'field');
  w.innerHTML = icon(ic, 15);
  const inp = el('input');
  inp.placeholder = placeholder;
  inp.spellcheck = false;
  inp.onkeydown = e => {
    e.stopPropagation();
    if (e.key === 'Escape') closePop();
    if (e.key === 'Enter' && inp.value.trim()) onSubmit(inp.value.trim());
  };
  w.append(inp);
  return w;
}
const sep = () => el('div', 'sep');

function confirmDelete(btn, run) {
  btn.onclick = e => {
    e.stopPropagation();
    if (btn.classList.contains('arm')) return run();
    btn.classList.add('arm');
    (btn.querySelector('.lbl') || btn).textContent = 'Move to Trash?';
  };
}

// ---------- Environments ----------

// Double-click the environment name to rename it (renames its folder too).
let renaming = false;
$('#envBtn').ondblclick = () => {
  if (renaming || !state.env) return;
  closePop();
  renaming = true;
  const btn = $('#envBtn'), name = $('#envName'), from = state.env;
  btn.classList.add('renaming');
  name.contentEditable = 'plaintext-only';
  name.spellcheck = false;
  name.focus();
  const r = document.createRange();
  r.selectNodeContents(name);
  getSelection().removeAllRanges();
  getSelection().addRange(r);
  let finished = false;
  const finish = async commit => {
    if (finished) return;
    finished = true;
    const to = name.textContent.replace(/\s+/g, ' ').trim();
    name.contentEditable = 'false';
    btn.classList.remove('renaming');
    name.onkeydown = name.onblur = null;
    getSelection().removeAllRanges();
    name.textContent = from;
    setTimeout(() => (renaming = false), 250);
    if (!commit || !to || to === from) return;
    try {
      apply(await api('renameEnv', { from, to }));
      await loadNotes();
    } catch (err) {
      btn.title = String(err.message || err);
      if (window.showError) showError('Couldn\'t rename: ' + btn.title);
      btn.classList.add('shake');
      setTimeout(() => { btn.classList.remove('shake'); btn.title = ''; }, 2500);
    }
  };
  name.onkeydown = e => {
    e.stopPropagation();
    if (e.key === 'Enter') { e.preventDefault(); finish(true); }
    else if (e.key === 'Escape') { e.preventDefault(); finish(false); }
    else if (e.key === ' ') { e.preventDefault(); document.execCommand('insertText', false, ' '); }
  };
  name.onblur = () => finish(true);
};
$('#envBtn').addEventListener('keyup', e => { if (renaming) e.preventDefault(); });

// The actions for one environment, shown in place of the list.
function envActions(p, name) {
  p.innerHTML = '';
  const box = el('div', 'sub');
  box.append(item(name, { icon: 'back', onClick: () => { p.innerHTML = ''; envMenu(p); } }), sep());
  box.append(item('Icon…', { html: envIconHTML(name, 16) || lucide('face-slightly-smiling-plus', 16, 1.7), onClick: () => {
    const st = envStyle(name);
    iconPicker(p, { icon: st.icon, color: st.iconColor }, async v => { await goToEnv(name); setEnvStyle(name, { icon: v.icon, iconColor: v.color }); }, () => envActions(p, name));
  } }));
  box.append(el('div', 'label', 'Background'));
  const row = swatchRow(envStyle(name).glow || '', async (v, final) => {
    await goToEnv(name);
    glowPreview = final ? null : v || globalGlow;
    if (final) setEnvStyle(name, { glow: v }); else paintGlow();
  }, true);
  row.classList.add('inpop');
  box.append(row, sep());
  box.append(item('Rename', { icon: 'doc', onClick: async () => {
    closePop();
    if (name !== state.env) await switchEnv(name);
    setTimeout(() => $('#envBtn').ondblclick(), 380);
  } }));
  if (state.envs.length > 1) {
    const d = item('Delete environment', { icon: 'trash', danger: true });
    confirmDelete(d, async () => { apply(await api('deleteEnv', { name })); closePop(); state.filter = null; await loadNotes(); });
    box.append(d);
  }
  p.append(box);
}

$('#envBtn').onclick = e => !renaming && openPop(e.currentTarget, envMenu);
function envMenu(p) {
  p.append(el('div', 'label', 'Environments'));
  state.envs.forEach(name => {
    const it = item(name, { html: envIconHTML(name, 16), checked: name === state.env, onClick: () => switchEnv(name) });
    const d = el('span', 'edots');
    d.innerHTML = icon('more', 16);
    d.title = 'More';
    d.onclick = ev => { ev.stopPropagation(); envActions(p, name); };
    it.append(d);
    p.append(it);
  });
  p.append(field('New environment', async name => {
    apply(await api('createEnv', { name }));
    state.filter = null;
    closePop();
    await loadNotes();
  }));
  p.append(sep());
  const foot = el('div', 'foot');
  const path = el('span', '', '‎' + state.rootDisplay);
  path.title = state.rootDisplay;
  const change = el('button', '', 'Change…');
  change.onclick = async () => { closePop(); await api('chooseRoot'); };
  foot.append(path, change);
  p.append(foot);
}

// Changing an environment's look shows that environment, without closing the menu you are in.
async function goToEnv(name) {
  if (name === state.env || !state.envs.includes(name)) return;
  apply(await api('setEnv', { name }));
  state.filter = null;
  await loadNotes();
}

async function switchEnv(name) {
  closePop();
  if (name === state.env) return;
  apply(await api('setEnv', { name }));
  state.filter = null;
  await loadNotes();
}

$('#chooseBtn').onclick = () => api('chooseRoot');
window.onRootChanged = async () => {
  state.note = null;
  state.filter = null;
  if (state.view === 'settingsView') { await refresh(); renderSettings(await api('settings')); return; }
  state.view = '';
  await refresh();
};

// ---------- Note open / save ----------

let queue = Promise.resolve();
const enqueue = fn => (queue = queue.then(fn).catch(e => api('log', { msg: String(e) })));
let saveTimer, saveFade;

function setSave(t) {
  const s = $('#saveState');
  s.textContent = t;
  s.style.opacity = 1;
  clearTimeout(saveFade);
  if (t !== 'Editing…') saveFade = setTimeout(() => (s.style.opacity = 0), 1400);
}

function markDirty() {
  if (!state.note) return;
  state.dirty = true;
  checkBlank();
  setSave('Editing…');
  clearTimeout(saveTimer);
  saveTimer = setTimeout(flush, 900);
}

function flush() {
  clearTimeout(saveTimer);
  return enqueue(async () => {
    const n = state.note;
    if (!n) return;
    const t = $('#title').value.trim() || 'Untitled';
    if (t !== n.title) {
      const r = await api('rename', { path: n.path, title: t });
      const old = n.path;
      n.path = r.path;
      n.title = r.title;
      pushRecent(n, old);
    }
    if (state.dirty) {
      state.dirty = false;
      crumbify();
      tidyImages();
      renderPreviews();
      await api('write', { path: n.path, content: joinFM(n.fm, MD.serialize(editor, ctx())) });
      n.modified = Date.now();
      $('#noteMeta').textContent = 'Edited just now';
    }
    setSave('Saved');
  });
}

function checkBlank() {
  editor.classList.toggle('blank', !editor.textContent.trim() && !editor.querySelector('img,table,hr,li,pre,a.file,h1,h2,h3,blockquote'));
}

function ensureTail() {
  editor.querySelectorAll('a.file:not([contenteditable])').forEach(a => (a.contentEditable = 'false'));
  if (!editor.firstElementChild) editor.innerHTML = '<p><br></p>';
  const last = editor.lastElementChild;
  if (last && ['PRE', 'TABLE', 'HR', 'BLOCKQUOTE'].includes(last.tagName)) editor.append(Object.assign(el('p'), { innerHTML: '<br>' }));
}

// Another window for this note (or brings forward the one that already has it).
const openWindow = path => api('openWindow', { path, env: state.env });

async function openNote(n, focusTitle) {
  // A note lives in one window at a time; if another window has it, that window comes forward instead.
  if (!(await api('claim', { path: n.path }))) return false;
  await flush();
  const fm = splitFM(await api('read', { path: n.path }));
  const text = fm.body;
  state.note = { ...n, fm: fm.lines };
  paintNoteIcon();
  state.dirty = false;
  $('#title').value = n.title;
  $('#catName').textContent = n.category || 'No category';
  $('#noteMeta').textContent = 'Edited ' + ago(n.modified);
  $('#saveState').textContent = '';
  editor.innerHTML = MD.parse(text, ctx());
  ensureTail();
  checkBlank();
  crumbify();
  tidyImages();
  renderPreviews(true);
  lastInsert = null;
  pushRecent(state.note);
  $('#docScroll').scrollTop = 0;
  showView('editorView');
  setTimeout(() => {
    if (focusTitle) { $('#title').focus(); $('#title').select(); }
    else caretEnd();
  }, 60);
}

function caretEnd() {
  editor.focus();
  const r = document.createRange();
  r.selectNodeContents(editor);
  r.collapse(false);
  const s = getSelection();
  s.removeAllRanges();
  s.addRange(r);
}

let creating = false;
async function newNote() {
  if (!state.root || creating) return;
  creating = true;
  setTimeout(() => (creating = false), 400);
  if (renaming) document.activeElement.blur();
  const n = await api('create', { env: state.env, category: state.filter || '', title: 'Untitled' });
  await openNote(n, true);
}

async function backToList() {
  await flush();
  state.note = null;
  api('claim', { path: '' });
  await loadNotes();
  showView('listView');
}

$('#newBtn').onclick = newNote;
// Back: a click returns to the list; holding it (or right-click) shows recent notes from any environment.
let recents = [], holdTimer = null, heldBack = false;
function pushRecent(n, oldPath) {
  recents = recents.filter(r => r.path !== n.path && r.path !== oldPath);
  recents.unshift({ env: state.env, path: n.path, title: n.title });
  recents = recents.slice(0, 9);
  api('setRecents', { items: recents });
}
function dropRecent(path) {
  recents = recents.filter(r => r.path !== path);
  api('setRecents', { items: recents });
}
async function openRecent(r) {
  closePop();
  await flush();
  if (r.env !== state.env) {
    if (!state.envs.includes(r.env)) return dropRecent(r.path);
    apply(await api('setEnv', { name: r.env }));
    state.filter = null;
  }
  await loadNotes(false);
  const n = state.notes.find(x => x.path === r.path);
  if (!n) { dropRecent(r.path); state.note = null; api('claim', { path: '' }); return showView('listView'); }
  // A quick dip so switching notes reads as a change, not a jump.
  const doc = $('.doc');
  doc.style.transition = 'opacity .16s, transform .22s var(--ease)';
  doc.style.opacity = 0;
  doc.style.transform = 'translateY(8px)';
  await new Promise(res => setTimeout(res, 160));
  await openNote(n);
  doc.style.opacity = 1;
  doc.style.transform = 'none';
}
function recentMenu() {
  const btn = $('#backBtn');
  openPop(btn, p => {
    p.append(el('div', 'label', 'Recent notes'));
    const list = recents.filter(r => !state.note || r.path !== state.note.path);
    if (!list.length) p.append(el('div', 'foot', 'Notes you open will show up here.'));
    list.forEach(r => {
      const it = item(r.title, { icon: 'doc', onClick: () => openRecent(r) });
      if (r.env !== state.env) it.append(el('span', 'envtag', r.env));
      p.append(it);
    });
    p.append(sep(), item('All notes', { icon: 'back', onClick: () => { closePop(); backToList(); } }));
  });
}
{
  const btn = $('#backBtn');
  const cancel = () => { clearTimeout(holdTimer); btn.classList.remove('held'); };
  btn.addEventListener('mousedown', e => {
    if (e.button !== 0) return;
    heldBack = false;
    btn.classList.add('held');
    holdTimer = setTimeout(() => { heldBack = true; btn.classList.remove('held'); recentMenu(); }, 360);
  });
  btn.addEventListener('mouseup', cancel);
  btn.addEventListener('mouseleave', cancel);
  btn.addEventListener('contextmenu', e => { e.preventDefault(); cancel(); heldBack = true; recentMenu(); });
  btn.onclick = () => { if (heldBack) { heldBack = false; return; } if (popAnchor === btn) return closePop(); backToList(); };
}
document.querySelectorAll('[data-close]').forEach(b => (b.onclick = () => flush().then(() => api('hide'))));

$('#title').oninput = () => { clearTimeout(saveTimer); setSave('Editing…'); saveTimer = setTimeout(flush, 700); };
$('#title').onkeydown = e => { if (e.key === 'Enter' || e.key === 'ArrowDown') { e.preventDefault(); caretEnd(); } };
$('#title').onblur = flush;

// Category picker
$('#catBtn').onclick = e => openPop(e.currentTarget, p => {
  p.append(el('div', 'label', 'Category'));
  const move = async category => {
    closePop();
    await flush();
    await enqueue(async () => {
      const r = await api('move', { path: state.note.path, category });
      state.note.path = r.path;
      state.note.category = r.category;
      $('#catName').textContent = r.category || 'No category';
      state.dirty = true; // attachment links are relative to the note, so rewrite them
    });
    await flush();
    const l = await api('list', { env: state.env });
    state.cats = l.categories;
  };
  p.append(item('No category', { checked: !state.note.category, onClick: () => move('') }));
  state.cats.forEach(c => p.append(item(c, { checked: state.note.category === c, onClick: () => move(c) })));
  p.append(field('New category', move));
});

// More menu
$('#moreBtn').onclick = e => openPop(e.currentTarget, p => {
  p.append(item('Open in new window', { icon: 'win', onClick: async () => {
    closePop();
    const path = state.note.path;
    await backToList();
    openWindow(path);
  } }));
  p.append(item('Show in Finder', { icon: 'eye', onClick: async () => { closePop(); await flush(); api('reveal', { path: state.note.path }); } }));
  // For Claude, ChatGPT and the like. As text, attachments become full paths an assistant with file access can open;
  // as files, the note and everything attached to it go on the clipboard together.
  p.append(item('Copy as Markdown', { icon: 'copy', onClick: async () => {
    closePop(); await flush();
    await api('copyMarkdown', { path: state.note.path });
    setSave('Copied');
  } }));
  p.append(item('Copy note + attachments', { icon: 'doc', onClick: async () => {
    closePop(); await flush();
    const n = await api('copyFile', { path: state.note.path });
    setSave(n > 1 ? `Copied ${n} files` : 'Copied');
  } }));
  const d = item('Delete note', { icon: 'trash', danger: true });
  confirmDelete(d, async () => {
    clearTimeout(saveTimer);
    await queue;
    const path = state.note.path;
    state.note = null;
    state.dirty = false;
    api('claim', { path: '' });
    await api('delete', { path });
    await loadNotes();
    showView('listView');
  });
  p.append(d);
}, 'right');

// ---------- Editor helpers ----------

let savedRange = null;
const selEl = () => { const n = getSelection().anchorNode; return n ? (n.nodeType === 3 ? n.parentElement : n) : null; };
const up = sel => { const n = selEl(); const e = n && n.closest(sel); return e && editor.contains(e) && e !== editor ? e : null; };

function restoreSel() {
  editor.focus();
  if (savedRange) { const s = getSelection(); s.removeAllRanges(); s.addRange(savedRange); }
}
function exec(cmd, val) {
  document.execCommand(cmd, false, val);
  markDirty();
  updateToolbar();
}
function setCaret(node, atEnd) {
  const r = document.createRange();
  r.selectNodeContents(node);
  r.collapse(!atEnd);
  const s = getSelection();
  s.removeAllRanges();
  s.addRange(r);
}

const BLOCKS = [
  ['p', 'Text'], ['h1', 'Heading 1'], ['h2', 'Heading 2'], ['h3', 'Heading 3'], ['ul', 'Bulleted list'],
  ['ol', 'Numbered list'], ['task', 'Checklist'], ['blockquote', 'Quote'], ['pre', 'Code block'], ['hr', 'Divider'],
];

function currentBlock() {
  if (up('pre')) return 'pre';
  const li = up('li');
  if (li) return li.parentElement.tagName === 'OL' ? 'ol' : li.parentElement.classList.contains('tasks') ? 'task' : 'ul';
  const h = up('h1,h2,h3');
  if (h) return h.tagName.toLowerCase();
  if (up('blockquote')) return 'blockquote';
  return 'p';
}

function setBlock(t) {
  restoreSel();
  const cur = currentBlock();
  const inList = ['ul', 'ol', 'task'].includes(cur);
  if (t === 'hr') { exec('insertHTML', '<hr><p><br></p>'); return; }
  if (['ul', 'ol', 'task'].includes(t)) {
    if (!inList) {
      if (cur !== 'p') exec('formatBlock', '<p>');
      exec(t === 'ol' ? 'insertOrderedList' : 'insertUnorderedList');
    } else if (t === 'ol' && cur !== 'ol') exec('insertOrderedList');
    else if (t !== 'ol' && cur === 'ol') exec('insertUnorderedList');
    const li = up('li');
    if (li && li.parentElement.tagName === 'UL') {
      li.parentElement.classList.toggle('tasks', t === 'task');
      if (t !== 'task') li.parentElement.querySelectorAll(':scope > li').forEach(x => x.removeAttribute('data-checked'));
    }
  } else {
    if (inList) exec(cur === 'ol' ? 'insertOrderedList' : 'insertUnorderedList');
    exec('formatBlock', `<${t}>`);
  }
  ensureTail();
  markDirty();
  updateToolbar();
}

function updateToolbar() {
  const inEditor = editor.contains(getSelection().anchorNode);
  const cur = inEditor ? currentBlock() : 'p';
  $('#blockName').textContent = (BLOCKS.find(b => b[0] === cur) || BLOCKS[0])[1];
  document.querySelectorAll('.tb[data-cmd]').forEach(b =>
    b.classList.toggle('on', inEditor && document.queryCommandState(b.dataset.cmd)));
  $('#taskBtn').classList.toggle('on', cur === 'task');
  $('#linkBtn').classList.toggle('on', inEditor && !!up('a'));
  const t = inEditor && up('table');
  const bar = $('#tbar');
  bar.classList.toggle('on', !!t);
  if (t) bar.style.top = Math.max(0, t.offsetTop + editor.offsetTop - 36) + 'px';
}

let tbPending = false;
document.addEventListener('selectionchange', () => {
  const s = getSelection();
  if (s.rangeCount && editor.contains(s.anchorNode)) savedRange = s.getRangeAt(0).cloneRange();
  if (!tbPending) { tbPending = true; requestAnimationFrame(() => { tbPending = false; updateToolbar(); }); }
});

// Toolbar
$('#toolbar').addEventListener('mousedown', e => e.preventDefault());
$('#tbar').addEventListener('mousedown', e => e.preventDefault());
document.querySelectorAll('.tb[data-cmd]').forEach(b => (b.onclick = () => { restoreSel(); exec(b.dataset.cmd); }));
$('#blockBtn').onclick = e => openPop(e.currentTarget, p => {
  const cur = currentBlock();
  BLOCKS.forEach(([t, label]) => p.append(item(label, { checked: t === cur, onClick: () => { closePop(); setBlock(t); } })));
});
$('#taskBtn').onclick = () => setBlock(currentBlock() === 'task' ? 'p' : 'task');
$('#tableBtn').onclick = () => {
  restoreSel();
  const row = tag => '<tr>' + `<${tag}><br></${tag}>`.repeat(3) + '</tr>';
  exec('insertHTML', `<table><thead>${row('th')}</thead><tbody>${row('td')}${row('td')}</tbody></table><p><br></p>`);
  ensureTail();
};
$('#attachBtn').onclick = async () => {
  const items = await api('attach', { env: state.env });
  if (items.length) { restoreSel(); insertFiles(items); }
};

function linkAction() {
  const a = up('a');
  if (a && !a.classList.contains('file')) { restoreSel(); exec('unlink'); return; }
  openPop($('#linkBtn'), p => {
    const f = field('Paste or type a link', url => {
      closePop();
      restoreSel();
      if (!/^[a-z]+:/i.test(url)) url = 'https://' + url;
      if (getSelection().isCollapsed) exec('insertHTML', `<a href="${MD.esc(url)}">${MD.esc(url)}</a>&nbsp;`);
      else exec('createLink', url);
    }, 'link');
    p.append(f);
    setTimeout(() => f.querySelector('input').focus(), 40);
  }, 'center');
}
$('#linkBtn').onclick = linkAction;

// Table tools
function cellOf() { return up('td,th'); }
function addRow(table, after) {
  const cols = table.rows[0].cells.length;
  const tr = el('tr');
  for (let i = 0; i < cols; i++) tr.append(Object.assign(el('td'), { innerHTML: '<br>' }));
  const body = table.tBodies[0] || table.appendChild(el('tbody'));
  if (after && after.parentElement === body) after.after(tr); else body.prepend(tr);
  return tr;
}
$('#tbar').onclick = e => {
  const t = e.target.dataset.t, cell = cellOf();
  if (!t || !cell) return;
  const table = cell.closest('table');
  if (t === 'row') setCaret(addRow(table, cell.parentElement).cells[cell.cellIndex]);
  if (t === 'col') {
    const idx = cell.cellIndex;
    for (const r of table.rows) r.cells[idx].after(Object.assign(el(r.cells[idx].tagName.toLowerCase()), { innerHTML: '<br>' }));
  }
  if (t === 'del') { table.remove(); ensureTail(); setCaret(editor.lastElementChild); }
  markDirty();
  updateToolbar();
};

function insertFiles(items) {
  const html = items.map(f => (f.image ? MD.imgHTML(f.rel, f.name, ctx(), Math.min(lastImgWidth, editor.clientWidth) || 0) : MD.chipHTML(f.rel, f.name) + '&nbsp;')).join('');
  const before = new Set(editor.querySelectorAll('[data-rel]'));
  exec('insertHTML', html);
  ensureTail();
  // Remember what just went in, so ⌘Z can take it straight back out.
  lastInsert = [...editor.querySelectorAll('[data-rel]')].filter(x => !before.has(x));
  tidyImages();
  // Keep what was just added in view. An image has no height until it loads, so look again then.
  const added = lastInsert[lastInsert.length - 1];
  if (added) {
    revealEl(added);
    if (added.tagName === 'IMG' && !added.complete) added.addEventListener('load', () => revealEl(added), { once: true });
  }
}
function revealEl(x) {
  if (!x.isConnected) return;
  const sc = $('#docScroll'), box = sc.getBoundingClientRect(), r = x.getBoundingClientRect();
  if (r.bottom > box.bottom - 78) sc.scrollTop += Math.min(r.bottom - (box.bottom - 78), r.top - (box.top + 70));
  else if (r.top < box.top + 62) sc.scrollTop += r.top - (box.top + 70);
}

// Pictures that follow each other share a paragraph, so small ones sit side by side when they fit.
const imgOnly = p => p && p.tagName === 'P' && p.querySelector('img') && !p.textContent.trim()
  && [...p.children].every(c => c.tagName === 'IMG' || c.tagName === 'BR');
function tidyImages() {
  for (const p of [...editor.children]) {
    if (!p.isConnected || !imgOnly(p)) { if (p.classList) p.classList.remove('imgrow'); continue; }
    while (imgOnly(p.nextElementSibling)) {
      const nx = p.nextElementSibling;
      p.append(' ', ...nx.querySelectorAll('img'));
      nx.remove();
    }
    p.querySelectorAll('br').forEach(b => b.remove());
    for (const im of p.querySelectorAll('img')) {
      if (im.nextSibling && im.nextSibling.nodeType === 1) im.after(' ');
    }
    p.classList.add('imgrow');
  }
}
let lastInsert = null;
function undoInsert() {
  const els = lastInsert;
  lastInsert = null;
  els.forEach(x => {
    if (!x.isConnected) return;
    const rel = x.dataset.rel;
    const gone = () => { x.remove(); ensureTail(); checkBlank(); markDirty(); if (![...editor.querySelectorAll('[data-rel]')].some(y => y.dataset.rel === rel)) api('trashAsset', { env: state.env, rel }); };
    x.style.transition = 'opacity .18s, transform .22s var(--ease)';
    x.style.opacity = 0;
    x.style.transform = 'scale(.94)';
    setTimeout(gone, 190);
  });
  if (selImg) selectImg(null);
}

// Keeps the line being typed above the floating toolbar.
function keepCaretVisible() {
  const sel = getSelection();
  if (!sel.rangeCount || !editor.contains(sel.anchorNode)) return;
  let r = sel.getRangeAt(0).getBoundingClientRect();
  if (!r.height) {
    // An empty caret rect: measure the thing next to the caret, never the whole note (that used to jump to the bottom).
    let n = sel.anchorNode;
    if (n.nodeType === 1) n = n.childNodes[Math.max(0, sel.anchorOffset - 1)] || n;
    if (n.nodeType === 3 || n.tagName === 'BR') n = n.parentElement;
    if (!n || n === editor) return;
    r = n.getBoundingClientRect();
  }
  const sc = $('#docScroll'), limit = sc.getBoundingClientRect().bottom - 92;
  if (r.bottom > limit) sc.scrollTop += r.bottom - limit;
}

// "Coach Studio > Knowledge base" becomes a breadcrumb. It is display only: the file keeps the plain text.
const CRUMB = /((?:[A-Z0-9][\w&'’\-]*)(?: [A-Z0-9][\w&'’\-]*)*)((?: > (?:[A-Z0-9][\w&'’\-]*)(?: [A-Z0-9][\w&'’\-]*)*(?: [a-z][\w'’\-]*){0,2}(?=$|[.,;:!?)]| > ))+|(?: > (?:[A-Z0-9][\w&'’\-]*)(?: [A-Z0-9][\w&'’\-]*)*)+)/;
function crumbify() {
  const caret = getSelection().anchorNode;
  // Drop crumbs that were edited into something else.
  editor.querySelectorAll('.crumb').forEach(c => {
    if (c.contains(caret)) return;
    const m = CRUMB.exec(c.textContent);
    if (!m || m[0] !== c.textContent) { c.replaceWith(document.createTextNode(c.textContent)); }
  });
  editor.normalize();
  const walker = document.createTreeWalker(editor, NodeFilter.SHOW_TEXT, {
    acceptNode: n => (n.parentElement.closest('code, pre, a, .crumb, h1, h2, h3') || n === caret ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT),
  });
  const nodes = [];
  while (walker.nextNode()) nodes.push(walker.currentNode);
  nodes.forEach(node => {
    let m;
    while (node && (m = CRUMB.exec(node.nodeValue))) {
      const mid = node.splitText(m.index);
      const rest = mid.splitText(m[0].length);
      const span = el('span', 'crumb');
      span.innerHTML = m[0].split(' > ').map(MD.esc).join(' <span class="gt">&gt;</span> ');
      mid.replaceWith(span);
      node = rest;
    }
  });
}

// ---------- Frosted header, only while scrolled ----------
document.querySelectorAll('.view .scroll').forEach(sc => {
  const view = sc.closest('.view');
  // Fades in over the first 60px of scrolling, so it never pops on or off.
  sc.addEventListener('scroll', () => view.style.setProperty('--frost-o', Math.min(1, sc.scrollTop / 60).toFixed(3)), { passive: true });
});

// ---------- Toolbar overflow ----------
{
  const tools = $('#tools');
  const edges = () => {
    tools.classList.toggle('more-l', tools.scrollLeft > 2);
    tools.classList.toggle('more-r', tools.scrollLeft + tools.clientWidth < tools.scrollWidth - 2);
  };
  tools.addEventListener('scroll', edges, { passive: true });
  // A plain mouse wheel scrolls it sideways too.
  tools.addEventListener('wheel', e => {
    if (Math.abs(e.deltaY) > Math.abs(e.deltaX) && tools.scrollWidth > tools.clientWidth) { e.preventDefault(); tools.scrollLeft += e.deltaY; }
  }, { passive: false });
  new ResizeObserver(edges).observe(tools);
  edges();
}

// ---------- Image resize ----------
// Click an image to select it, then use − / + / Full or drag the corner. The last size is remembered for the next image.

let lastImgWidth = 0, selImg = null, imgSave;
const imgBox = $('#imgBox');

function placeImgBox() {
  if (!selImg || !selImg.isConnected) return selectImg(null);
  const d = imgBox.parentElement.getBoundingClientRect(), r = selImg.getBoundingClientRect();
  Object.assign(imgBox.style, { left: r.left - d.left + 'px', top: r.top - d.top + 'px', width: r.width + 'px', height: r.height + 'px' });
  $('#imgPct').textContent = Math.round(r.width / editor.clientWidth * 100) + '%';
}

function selectImg(img) {
  selImg = img;
  imgBox.classList.toggle('on', !!img);
  if (img) placeImgBox();
}

function setImgWidth(w, commit = true) {
  const max = editor.clientWidth;
  w = Math.round(Math.max(60, Math.min(w, max)));
  const full = w >= max - 2;
  if (full) { selImg.style.width = ''; delete selImg.dataset.w; }
  else { selImg.style.width = w + 'px'; selImg.dataset.w = w; }
  placeImgBox();
  if (!commit) return;
  lastImgWidth = full ? 0 : w;
  tidyImages();
  placeImgBox();
  markDirty();
  clearTimeout(imgSave);
  imgSave = setTimeout(() => api('setImgWidth', { value: String(lastImgWidth) }), 300);
}

imgBox.addEventListener('mousedown', e => {
  e.preventDefault();
  e.stopPropagation();
  if (!e.target.classList.contains('imghandle')) return;
  const x0 = e.clientX, w0 = selImg.getBoundingClientRect().width;
  const move = ev => setImgWidth(w0 + ev.clientX - x0, false);
  const upFn = ev => {
    document.removeEventListener('mousemove', move);
    document.removeEventListener('mouseup', upFn);
    setImgWidth(w0 + ev.clientX - x0);
  };
  document.addEventListener('mousemove', move);
  document.addEventListener('mouseup', upFn);
});
imgBox.addEventListener('click', e => {
  const s = e.target.dataset.s;
  if (!s || !selImg) return;
  const w = selImg.getBoundingClientRect().width, step = editor.clientWidth * 0.1;
  setImgWidth(s === 'full' ? editor.clientWidth : s === '+' ? w + step : w - step);
});
document.addEventListener('mousedown', e => {
  if (e.target.tagName === 'IMG' && editor.contains(e.target)) { selectImg(e.target); return; }
  if (selImg && !imgBox.contains(e.target)) selectImg(null);
});
document.addEventListener('keydown', e => {
  if (!selImg) return;
  if (e.key === 'Backspace' || e.key === 'Delete') { e.preventDefault(); const i = selImg; selectImg(null); i.remove(); ensureTail(); markDirty(); }
  else if (e.metaKey && ['c', 'x'].includes(e.key.toLowerCase())) {
    e.preventDefault();
    const i = selImg, cut = e.key.toLowerCase() === 'x';
    const done = i.dataset.rel ? api('copyImage', { env: state.env, rel: i.dataset.rel }) : api('copyText', { text: i.getAttribute('src') });
    done.then(() => {
      setSave('Copied image');
      if (cut) { selectImg(null); i.remove(); ensureTail(); markDirty(); }
    }).catch(err => api('log', { msg: 'copy image: ' + err }));
  }
  else if (e.metaKey && e.key.toLowerCase() === 'z' && lastInsert && lastInsert.length) { e.preventDefault(); undoInsert(); }
  else if (!e.metaKey) selectImg(null);
}, true);
new ResizeObserver(() => selImg && placeImgBox()).observe(editor);

// ---------- Editor events ----------

editor.addEventListener('input', e => {
  if (e.inputType === 'insertText' && e.data === ' ') typingShortcut();
  if (e.inputType === 'insertParagraph') {
    const li = up('li');
    if (li && li.hasAttribute('data-checked') && !li.textContent.trim()) li.removeAttribute('data-checked');
  }
  ensureTail();
  markDirty();
  lastInsert = null;
  keepCaretVisible();
});

function typingShortcut() {
  const s = getSelection();
  const node = s.anchorNode;
  if (!s.isCollapsed || !node || node.nodeType !== 3) return;
  const blk = node.parentElement.closest('p,div,li,h1,h2,h3,blockquote,pre,td,th');
  if (!blk || !['P', 'DIV'].includes(blk.tagName) || up('li,blockquote,td,th')) return;
  const r = document.createRange();
  r.setStart(blk, 0);
  r.setEnd(node, s.anchorOffset);
  const before = r.toString().replace(/ /g, ' ');
  const type = { '# ': 'h1', '## ': 'h2', '### ': 'h3', '- ': 'ul', '* ': 'ul', '1. ': 'ol', '[] ': 'task', '[ ] ': 'task', '> ': 'blockquote' }[before];
  if (!type) return;
  s.removeAllRanges();
  s.addRange(r);
  document.execCommand('delete');
  savedRange = getSelection().getRangeAt(0).cloneRange();
  setBlock(type);
}

editor.addEventListener('keydown', e => {
  const mod = e.metaKey;
  const k = e.key.toLowerCase();
  if (mod && !e.shiftKey && k === 'z' && lastInsert && lastInsert.length) { e.preventDefault(); undoInsert(); return; }
  if (mod && !e.shiftKey && ['b', 'i', 'u'].includes(k)) { e.preventDefault(); exec({ b: 'bold', i: 'italic', u: 'underline' }[k]); return; }
  if (mod && e.shiftKey && k === 'x') { e.preventDefault(); exec('strikeThrough'); return; }
  if (mod && e.shiftKey && k === 'l') { e.preventDefault(); setBlock(currentBlock() === 'task' ? 'p' : 'task'); return; }
  if (mod && k === 'k') { e.preventDefault(); linkAction(); return; }

  if (e.key === 'Tab') {
    e.preventDefault();
    const cell = cellOf();
    if (cell) {
      const cells = [...cell.closest('table').querySelectorAll('th,td')];
      let next = cells[cells.indexOf(cell) + (e.shiftKey ? -1 : 1)];
      if (!next && !e.shiftKey) { next = addRow(cell.closest('table'), cell.parentElement).cells[0]; markDirty(); }
      if (next) setCaret(next, true);
    } else if (up('li')) exec(e.shiftKey ? 'outdent' : 'indent');
    else if (up('pre')) exec('insertText', '  ');
    return;
  }

  if (e.key === 'Enter' && !e.shiftKey && !mod) {
    if (up('pre')) { e.preventDefault(); exec('insertLineBreak'); return; }
    const blk = up('p,div');
    if (!blk || up('li,td,th,blockquote')) return;
    const text = blk.textContent.trim();
    const fence = text.match(/^```([\w+-]*)$/);
    if (text === '---' || fence) {
      e.preventDefault();
      const p = Object.assign(el('p'), { innerHTML: '<br>' });
      if (fence) {
        const pre = el('pre');
        pre.dataset.lang = fence[1];
        pre.innerHTML = '<code><br></code>';
        blk.replaceWith(pre, p);
        setCaret(pre.firstChild);
      } else {
        blk.replaceWith(el('hr'), p);
        setCaret(p);
      }
      markDirty();
    }
  }
  if (e.key === 'Enter' && mod && up('pre')) {
    e.preventDefault();
    const pre = up('pre');
    const p = Object.assign(el('p'), { innerHTML: '<br>' });
    pre.after(p);
    setCaret(p);
    markDirty();
  }
});

editor.addEventListener('click', e => {
  const a = e.target.closest('a');
  if (a) {
    e.preventDefault();
    if (a.dataset.rel) api('reveal', { path: state.env + '/' + a.dataset.rel });
    else api('openURL', { url: a.getAttribute('href') });
    return;
  }
  const li = e.target;
  if (li.tagName === 'LI' && li.parentElement.classList.contains('tasks') && e.offsetX < 28 && e.offsetY < 28) {
    li.toggleAttribute('data-checked');
    if (li.hasAttribute('data-checked')) li.setAttribute('data-checked', 'true');
    markDirty();
  }
});

const looksLikeMD = t => /\n/.test(t) || /(\*\*|__|`|^#{1,6} |^[-*] |^\d+\. |\[.+\]\(.+\)|\|.+\|)/m.test(t);

function insertParsed(html) {
  const one = html.match(/^<p>([\s\S]*)<\/p>$/);
  exec('insertHTML', one && !one[1].includes('<p>') ? one[1] : html);
  ensureTail();
  tidyImages();
  renderPreviews(true);
}

// ⌘V keeps the formatting; ⌥⌘V pastes the plain text only.
editor.addEventListener('paste', e => { e.preventDefault(); pasteInto(false); });
async function pasteInto(plainText) {
  const r = await api('paste', { env: state.env });
  const inCode = !!up('pre');
  if (r.kind === 'files') return insertFiles(r.items);
  if (inCode) return exec('insertHTML', MD.esc(r.text || '').replace(/\n/g, '<br>'));
  if (plainText) {
    const t = (r.text || '').replace(/\r\n?/g, '\n');
    if (!t) return;
    if (!t.includes('\n')) return exec('insertText', t);
    return insertParsed(t.split(/\n{2,}/).map(par => '<p>' + (MD.esc(par).replace(/\n/g, '<br>') || '<br>') + '</p>').join(''));
  }
  if (r.kind === 'html') {
    const doc = new DOMParser().parseFromString(r.html, 'text/html');
    const md = MD.serialize(doc.body, ctx());
    if (md.trim()) return insertParsed(MD.parse(md, ctx()));
  }
  const t = r.text || '';
  if (!t) return;
  if (/^https?:\/\/\S+$/.test(t.trim())) {
    const url = t.trim();
    if (getSelection().isCollapsed) exec('insertHTML', `<a href="${MD.esc(url)}">${MD.esc(url)}</a>`);
    else exec('createLink', url);
  } else if (looksLikeMD(t)) insertParsed(MD.parse(t, ctx()));
  else exec('insertText', t);
}
// Called by the app's Edit ▸ Paste and Match Style (⌥⌘V).
window.pastePlain = () => {
  const a = document.activeElement;
  if (a === editor || editor.contains(a)) return pasteInto(true);
  if (a && a.matches('input')) api('paste', { env: state.env }).then(r => { if (r.text) document.execCommand('insertText', false, r.text.replace(/\s+/g, ' ')); });
};

editor.addEventListener('dragover', e => { if (e.dataTransfer.types.includes('Files')) e.preventDefault(); });
editor.addEventListener('drop', async e => {
  const files = [...e.dataTransfer.files];
  if (!files.length) return;
  e.preventDefault();
  const items = [];
  for (const f of files) {
    const data = await new Promise(res => {
      const fr = new FileReader();
      fr.onload = () => res(fr.result.split(',')[1]);
      fr.readAsDataURL(f);
    });
    items.push(await api('saveAsset', { env: state.env, name: f.name, data }));
  }
  restoreSel();
  insertFiles(items);
});

// ---------- Typing sound (synthesised, nothing to download) ----------

let typingVolume = 0.5, soundStyle = 'soft', lastKeyAt = 0;
const SOUNDS = { soft: 'Soft', creamy: 'Creamy', poppy: 'Poppy', clacky: 'Clacky', thocky: 'Thocky', lego: 'Lego' };

// The app itself plays the sound (kind: key | space | enter | back); the page only says which key went down.
function thock(kind = 'key', soft = false) {
  if (typingVolume <= 0) return;
  api('tap', { kind, soft, vol: typingVolume, style: soundStyle }).catch(() => {});
}
const soundWarm = () => { if (typingVolume > 0) api('soundWarm').catch(() => {}); };

// Key presses are heard by the app itself, straight from the keyboard, so the sound never waits for this page.
// The page only says whether the caret is in a note's text or title.
let typingOn = null;
function reportTyping() {
  const a = document.activeElement;
  const on = !!a && (a === editor || a === $('#title') || editor.contains(a)) && $('#editorView').classList.contains('active');
  if (on === typingOn) return;
  typingOn = on;
  api('typingFocus', { on }).catch(() => {});
}
// A second ear. Normally a key press comes first and the app has already made its sound. While the system shows
// an inline suggestion it types the letters itself and no key press arrives, so text that is about to change
// without a key press just before it asks the app for the sound.
let quietInput = 0, keyAt = -1e9;
const sawKey = () => { keyAt = performance.now(); };
function typedEcho(e) {
  if (quietInput || e.isComposing || performance.now() - keyAt < 60) return;
  const k = { insertText: 'key', insertParagraph: 'enter', insertLineBreak: 'enter', deleteContentBackward: 'back', deleteContentForward: 'back' }[e.inputType];
  if (!k || typingVolume <= 0) return;
  api('typed', { kind: k === 'key' && e.data === ' ' ? 'space' : k }).catch(() => {});
}
for (const x of [editor, $('#title')]) {
  x.addEventListener('keydown', sawKey, true);
  x.addEventListener('beforeinput', typedEcho, true);
}
// Changes the app makes itself (formatting, pasting, shortcuts) are not typing.
{
  const real = document.execCommand.bind(document);
  document.execCommand = (...a) => { quietInput++; try { return real(...a); } finally { quietInput--; } };
}
document.addEventListener('focusin', reportTyping);
document.addEventListener('focusout', () => setTimeout(reportTyping, 0));
api('settings').then(s => { editor.spellcheck = !!s.spell; recents = s.recents || []; typingVolume = s.typing; soundStyle = s.sound || 'soft'; applyGlow(s.glow); lastImgWidth = s.imgWidth || 0; });

// ---------- Glow colour ----------
// One default colour (Settings), and each environment may have its own.

// Each colour is two shades of one hue. Keys stay the same as before so saved choices still work.
const GLOWS = {
  sky: ['#5c9dff', '#a9cbff'], sunset: ['#ff9466', '#ffc6a8'], lavender: ['#9f7dff', '#cfc0ff'], ocean: ['#22b8d4', '#8fe0ee'],
  meadow: ['#4cc463', '#a6e6a2'], ember: ['#ff5a4a', '#ffa89d'], orange: ['#ff8a1f', '#ffc078'], rose: ['#ff5f8a', '#ffb0c5'],
  mint: ['#2fd3a0', '#a0efd3'], yellow: ['#f2c200', '#ffe48a'], silver: ['#a9adb8', '#d6d8df'], none: null,
};
const GLOW_NAMES = { sunset: 'Peach', ember: 'Red', meadow: 'Green', ocean: 'Teal' };
const glowTitle = n => GLOW_NAMES[n] || n[0].toUpperCase() + n.slice(1);

// Colour helpers for custom colours ("#rrggbb"): the second shade is a lighter tint of the same hue.
const hexRGB = h => [1, 3, 5].map(i => parseInt(h.slice(i, i + 2), 16));
const rgbHex = c => '#' + c.map(v => Math.round(Math.max(0, Math.min(255, v))).toString(16).padStart(2, '0')).join('');
const tint = (h, k) => rgbHex(hexRGB(h).map(v => v + (255 - v) * k));
const isHex = v => /^#[0-9a-f]{6}$/i.test(v || '');
const glowPair = name => isHex(name) ? [name, tint(name, 0.5)] : GLOWS[name] === undefined ? GLOWS.sky : GLOWS[name];
function hsvHex(h, s, v) {
  const f = n => { const k = (n + h / 60) % 6; return v - v * s * Math.max(0, Math.min(k, 4 - k, 1)); };
  return rgbHex([f(5), f(3), f(1)].map(x => x * 255));
}
function hexHSV(hex) {
  const [r, g, b] = hexRGB(hex).map(x => x / 255), mx = Math.max(r, g, b), mn = Math.min(r, g, b), d = mx - mn;
  let h = 0;
  if (d) h = mx === r ? ((g - b) / d) % 6 : mx === g ? (b - r) / d + 2 : (r - g) / d + 4;
  return [(h * 60 + 360) % 360, mx ? d / mx : 0, mx];
}

let globalGlow = 'sky';
const envStyle = (name = state.env) => (state.envStyles || {})[name] || {};
let glowPreview = null; // a colour being dragged in the picker, shown before it is saved
function paintGlow() {
  const g = glowPair(glowPreview || envStyle().glow || globalGlow);
  $('.glow').classList.toggle('off', !g);
  if (g) {
    $('.glow').style.setProperty('--g1', g[0]);
    $('.glow').style.setProperty('--g2', g[1]);
  }
}
function applyGlow(name) {
  globalGlow = name || 'sky';
  paintGlow();
  markSwatches($('#glowSw'), globalGlow);
}
function markSwatches(box, v) {
  box.querySelectorAll('.swatch').forEach(b => b.classList.toggle('on', b.dataset.v === v || (b.dataset.v === 'custom' && isHex(v))));
  const c = box.querySelector('.swatch.custom');
  if (c && isHex(v)) c.style.setProperty('--cc', v);
}

// Colour dots, plus a custom colour. With `withDefault`, the first dot means "use the default from Settings".
// `onPick(value, final)`: final is false while a custom colour is still being dragged.
function swatchRow(current, onPick, withDefault) {
  const box = el('div', 'swatchbox');
  const row = el('div', 'swatches');
  const names = (withDefault ? [''] : []).concat(Object.keys(GLOWS), ['custom']);
  let picker = null;
  for (const name of names) {
    const g = GLOWS[name];
    const b = el('button', 'swatch' + (name === '' ? ' def' : name === 'custom' ? ' custom' : g ? '' : ' none'));
    b.dataset.v = name;
    b.title = name === '' ? 'Default (' + glowTitle(isHex(globalGlow) ? 'custom' : globalGlow) + ')' : name === 'custom' ? 'Custom colour' : glowTitle(name);
    const show = name === '' ? glowPair(globalGlow) : g;
    if (show) { b.style.setProperty('--a', show[0]); b.style.setProperty('--b', show[1]); }
    b.onmousedown = e => e.preventDefault();
    b.onclick = () => {
      if (name === 'custom') {
        if (picker) { picker.remove(); picker = null; return; }
        const start = isHex(current) ? current : glowPair(current || globalGlow)?.[0] || '#ff8a1f';
        picker = colorPicker(start, (hex, final) => {
          current = hex;
          markSwatches(row, hex);
          onPick(hex, final);
        });
        box.append(picker);
        return;
      }
      if (picker) { picker.remove(); picker = null; }
      current = name;
      markSwatches(row, name);
      onPick(name, true);
    };
    row.append(b);
  }
  markSwatches(row, current);
  box.append(row);
  return box;
}

// A small colour picker: saturation/brightness square, hue strip and a hex field.
function colorPicker(start, onChange) {
  let [h, sat, val] = hexHSV(start);
  const w = el('div', 'cpick');
  w.innerHTML = '<div class="cp-sv"><i></i></div><div class="cp-hue"><i></i></div><div class="cp-row"><span class="cp-prev"></span><input class="cp-hex" spellcheck="false" maxlength="7"><button class="cp-done">Done</button></div>';
  const sv = w.querySelector('.cp-sv'), hue = w.querySelector('.cp-hue'), hex = w.querySelector('.cp-hex'), prev = w.querySelector('.cp-prev');
  let saveT;
  const paint = (final, fromField) => {
    const c = hsvHex(h, sat, val);
    sv.style.setProperty('--h', h);
    sv.firstChild.style.left = sat * 100 + '%';
    sv.firstChild.style.top = (1 - val) * 100 + '%';
    hue.firstChild.style.left = h / 360 * 100 + '%';
    prev.style.background = `linear-gradient(135deg, ${c}, ${tint(c, .5)})`;
    if (!fromField) hex.value = c;
    clearTimeout(saveT);
    onChange(c, false);
    saveT = setTimeout(() => onChange(c, true), final ? 0 : 350);
  };
  const drag = (elm, fn) => elm.onmousedown = e => {
    e.preventDefault();
    e.stopPropagation();
    const r = elm.getBoundingClientRect();
    const move = ev => { fn(Math.max(0, Math.min(1, (ev.clientX - r.left) / r.width)), Math.max(0, Math.min(1, (ev.clientY - r.top) / r.height))); paint(false); };
    const up = () => { removeEventListener('mousemove', move); removeEventListener('mouseup', up); paint(true); };
    addEventListener('mousemove', move);
    addEventListener('mouseup', up);
    move(e);
  };
  drag(sv, (x, y) => { sat = x; val = 1 - y; });
  drag(hue, x => { h = Math.min(359.9, x * 360); });
  hex.onkeydown = e => { e.stopPropagation(); if (e.key === 'Enter') hex.blur(); };
  hex.oninput = () => {
    const v = hex.value.trim().replace(/^#?/, '#');
    if (isHex(v)) { [h, sat, val] = hexHSV(v); paint(false, true); }
  };
  w.querySelector('.cp-done').onclick = () => { paint(true); w.remove(); };
  w.onmousedown = e => { if (e.target === w) e.preventDefault(); };
  setTimeout(() => paint(true), 0);
  return w;
}
$('#glowSw').append(swatchRow(globalGlow, (v, final) => {
  globalGlow = v;
  paintGlow();
  if (final) api('setGlow', { value: v });
}));

async function setEnvStyle(name, values) {
  let s;
  for (const [key, value] of Object.entries(values)) s = await api('setEnvStyle', { env: name, key, value: value || '' });
  if (s) { state.envStyles = s.envStyles || {}; paintEnv(); }
}
window.onEnvStyles = ({ styles, glow }) => { state.envStyles = styles || {}; globalGlow = glow || globalGlow; paintEnv(); };

// ---------- Icons (Lucide, bundled) ----------

const ICON_COLORS = { gray: '#8e8e93', red: '#ff453a', orange: '#ff8a1f', yellow: '#e8b400', green: '#30c45a', teal: '#2bb5c9', blue: '#0a84ff', purple: '#a35bf0', pink: '#ff4f86' };
const iconColor = c => ICON_COLORS[c] || 'currentColor';
const lucideHas = n => !!(window.LUCIDE && LUCIDE[n]);
const lucide = (n, s = 18, w = 1.9) => `<svg width="${s}" height="${s}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="${w}" stroke-linecap="round" stroke-linejoin="round">${(window.LUCIDE || {})[n] || ''}</svg>`;
function envIconHTML(name, size) {
  const st = envStyle(name);
  return st.icon && lucideHas(st.icon) ? `<span class="eico" style="color:${iconColor(st.iconColor)}">${lucide(st.icon, size)}</span>` : '';
}
function paintEnv() {
  paintGlow();
  const b = $('#envIco'), st = envStyle();
  const on = !!(st.icon && lucideHas(st.icon));
  b.classList.toggle('on', on);
  if (on) { b.innerHTML = lucide(st.icon, 26, 2.1); b.style.color = iconColor(st.iconColor); }
}
$('#envIco').onclick = e => {
  const st = envStyle(), name = state.env;
  openPop(e.currentTarget, p => iconPicker(p, { icon: st.icon, color: st.iconColor }, v => setEnvStyle(name, { icon: v.icon, iconColor: v.color })));
};

const POPULAR_ICONS = ('folder briefcase rocket star heart sparkles lightbulb target flag book-open notebook-pen file-text list-todo circle-check calendar clock '
  + 'house building users user message-circle mail phone globe code terminal bot brain cpu database palette pen-tool camera eighth-notes film '
  + 'gamepad-2 plane map-pin compass graduation-cap dumbbell bike coffee utensils shopping-cart wallet piggy-bank chart-line trending-up '
  + 'megaphone newspaper mic headphones leaf sun moon cloud zap flame gem gift trophy puzzle shield lock key bookmark tag archive inbox layers '
  + 'anchor car dog cat baby stethoscope pill hammer wrench face-slightly-smiling').split(' ');

// The tags (for searching) are only loaded the first time a picker opens.
let tagsLoading = null;
const loadTags = () => tagsLoading || (tagsLoading = new Promise(res => {
  const sc = document.createElement('script');
  sc.src = 'lucide-tags.js';
  sc.onload = sc.onerror = () => res();
  document.head.append(sc);
}));

// Pick an icon and its colour. `onPick({icon, color})`; icon '' removes it.
function iconPicker(p, cur, onPick, onBack) {
  p.innerHTML = '';
  p.classList.add('picker');
  let color = cur.color || '', icon0 = cur.icon || '';
  const top = el('div', 'pk-top');
  if (onBack) {
    const back = el('button', 'pk-back');
    back.innerHTML = icon('back', 16);
    back.onclick = () => { p.classList.remove('picker'); onBack(); };
    top.append(back);
  }
  const f = el('label', 'field');
  f.innerHTML = icon('search', 15);
  const q = el('input');
  q.placeholder = 'Search icons';
  q.spellcheck = false;
  f.append(q);
  top.append(f);
  const colors = el('div', 'pk-colors');
  for (const c of [''].concat(Object.keys(ICON_COLORS))) {
    const d = el('button', 'pk-color' + (c === color ? ' on' : ''));
    d.style.setProperty('--c', c ? ICON_COLORS[c] : 'var(--ink)');
    d.title = c ? c[0].toUpperCase() + c.slice(1) : 'Default';
    d.onmousedown = e => e.preventDefault();
    d.onclick = () => {
      color = c;
      colors.querySelectorAll('.pk-color').forEach(x => x.classList.toggle('on', x === d));
      grid.style.color = iconColor(color);
      if (icon0) onPick({ icon: icon0, color });
    };
    colors.append(d);
  }
  const grid = el('div', 'pk-grid');
  grid.style.color = iconColor(color);
  const foot = el('div', 'pk-foot');
  const count = el('span');
  const remove = el('button', '', 'Remove icon');
  remove.disabled = !icon0;
  remove.onclick = () => { closePop(); onPick({ icon: '', color: '' }); };
  foot.append(count, remove);
  p.append(top, colors, grid, foot);

  // Common picks first, then every icon A to Z.
  const all = [...new Set(POPULAR_ICONS.filter(lucideHas).concat(Object.keys(window.LUCIDE || {})))];
  let list = all, shown = 0;
  const more = () => {
    const frag = document.createDocumentFragment();
    for (const n of list.slice(shown, shown + 160)) {
      const b = el('button', 'pk-icon' + (n === icon0 ? ' on' : ''));
      b.title = n;
      b.innerHTML = lucide(n, 20);
      b.onmousedown = e => e.preventDefault();
      b.onclick = () => { closePop(); onPick({ icon: n, color }); };
      frag.append(b);
    }
    shown += 160;
    grid.append(frag);
  };
  const filter = () => {
    const words = q.value.toLowerCase().trim().split(/\s+/).filter(Boolean);
    const T = window.LUCIDE_TAGS || {};
    if (!words.length) list = icon0 ? [icon0].concat(all.filter(n => n !== icon0)) : all;
    else {
      // Names that start with the search first, then names that contain it, then tag matches.
      const score = n => {
        const hay = n.replace(/-/g, ' ') + ' ' + (T[n] || '');
        if (!words.every(w => hay.includes(w))) return 0;
        return n.startsWith(words[0]) ? 3 : n.includes(words[0]) ? 2 : 1;
      };
      list = all.map(n => [n, score(n)]).filter(x => x[1]).sort((a, b) => b[1] - a[1]).map(x => x[0]);
    }
    grid.innerHTML = '';
    grid.scrollTop = 0;
    shown = 0;
    count.textContent = list.length === all.length ? all.length + ' icons' : list.length === 1 ? '1 icon' : list.length + ' icons';
    if (!list.length) grid.append(el('div', 'pk-none', 'No icons found'));
    more();
  };
  grid.onscroll = () => { if (shown < list.length && grid.scrollTop + grid.clientHeight > grid.scrollHeight - 120) more(); };
  q.oninput = filter;
  q.onkeydown = e => {
    e.stopPropagation();
    if (e.key === 'Escape') closePop();
    if (e.key === 'Enter' && list.length) { closePop(); onPick({ icon: list[0], color }); }
  };
  filter();
  loadTags().then(() => { if (q.value) filter(); });
  // When the picker replaces a smaller menu, keep it inside the window.
  const l = parseFloat(p.style.left) || 0, t = parseFloat(p.style.top) || 0;
  if (l + p.offsetWidth > innerWidth - 10) p.style.left = Math.max(10, innerWidth - p.offsetWidth - 10) + 'px';
  if (t + p.offsetHeight > innerHeight - 10) p.style.top = Math.max(10, innerHeight - p.offsetHeight - 10) + 'px';
  setTimeout(() => q.focus(), 30);
}

// A note's icon: kept in the note's front matter, so it travels with the .md file.
const FM = /^---\n([\s\S]*?)\n---[ \t]*(?:\n|$)/;
function splitFM(text) {
  text = String(text || '').replace(/\r\n?/g, '\n');
  const m = text.match(FM);
  if (!m || !m[1].split('\n').some(l => /^[\w-]+\s*:/.test(l))) return { lines: [], body: text };
  return { lines: m[1].split('\n'), body: text.slice(m[0].length) };
}
const fmGet = (lines, k) => { const l = (lines || []).find(x => new RegExp('^' + k + '\\s*:').test(x)); return l ? l.slice(l.indexOf(':') + 1).trim().replace(/^["']|["']$/g, '') : ''; };
function fmSet(lines, k, v) {
  const i = lines.findIndex(x => new RegExp('^' + k + '\\s*:').test(x));
  if (!v) { if (i >= 0) lines.splice(i, 1); }
  else if (i >= 0) lines[i] = k + ': ' + v;
  else lines.push(k + ': ' + v);
}
const joinFM = (lines, body) => lines && lines.length ? '---\n' + lines.join('\n') + '\n---\n' + body : body;

function paintNoteIcon() {
  const n = state.note, b = $('#noteIco');
  const ic = n ? fmGet(n.fm, 'icon') : '';
  const on = !!(ic && lucideHas(ic));
  b.classList.toggle('on', on);
  $('#addIco').classList.toggle('gone', on);
  if (on) { b.innerHTML = lucide(ic, 28, 2); b.style.color = iconColor(fmGet(n.fm, 'icon-color')); }
}
function pickNoteIcon(anchor) {
  const n = state.note;
  if (!n) return;
  openPop(anchor, p => iconPicker(p, { icon: fmGet(n.fm, 'icon'), color: fmGet(n.fm, 'icon-color') }, v => {
    if (state.note !== n) return;
    n.fm = n.fm || [];
    fmSet(n.fm, 'icon', v.icon);
    fmSet(n.fm, 'icon-color', v.icon ? v.color : '');
    paintNoteIcon();
    state.dirty = true;
    flush();
  }));
}
$('#noteIco').onclick = e => pickNoteIcon(e.currentTarget);
$('#addIco').onclick = e => pickNoteIcon(e.currentTarget);

// ---------- Settings ----------

let recordingKeys = false;

function renderKeys(keys, rec) {
  const box = $('#scKeys');
  box.classList.toggle('rec', !!rec);
  box.innerHTML = '';
  if (!keys.length) { box.append(el('span', 'wait', 'Hold the new keys…')); return; }
  keys.forEach((k, i) => {
    if (i) box.append(el('span', 'plus', '+'));
    const key = el('span', 'key', k);
    key.style.animationDelay = i * 45 + 'ms';
    box.append(key);
  });
}

function renderSettings(s) {
  renderKeys(s.shortcut);
  $('#setRoot').textContent = s.rootDisplay;
  $('#setRoot').title = s.rootDisplay;
  soundStyle = s.sound || 'soft';
  $('#sndName').textContent = SOUNDS[soundStyle];
  setTypingUI(s.typing);
  applyGlow(s.glow);
  const themes = ['system', 'light', 'dark'];
  $('#themeSeg').style.setProperty('--i', Math.max(0, themes.indexOf(s.theme)));
  document.querySelectorAll('#themeSeg button').forEach(b => b.classList.toggle('on', b.dataset.v === s.theme));
  $('#swWidget').classList.toggle('on', s.widget);
  $('#swLogin').classList.toggle('on', s.login);
  $('#swSpell').classList.toggle('on', !!s.spell);
  editor.spellcheck = !!s.spell;
}

function setTypingUI(v) {
  typingVolume = v;
  const pct = Math.round(v * 100);
  $('#typVol').value = pct;
  $('#typVol').style.setProperty('--fillpct', pct + '%');
  $('#typHint').textContent = pct ? `${SOUNDS[soundStyle]} key sounds while you write · ${pct}%` : 'Muted';
}
$('#sndBtn').onclick = e => openPop(e.currentTarget, p => {
  Object.entries(SOUNDS).forEach(([id, label]) => p.append(item(label, { checked: id === soundStyle, onClick: () => {
    closePop();
    soundStyle = id;
    $('#sndName').textContent = label;
    setTypingUI(typingVolume);
    api('setSound', { value: id });
    [220, 350, 470, 620, 740].forEach((ms, i) => setTimeout(() => thock(i === 3 ? 'space' : 'key'), ms)); // a short preview
  } })));
}, 'right');
let typSave;
$('#typVol').oninput = e => {
  setTypingUI(e.target.value / 100);
  thock('key');
  clearTimeout(typSave);
  typSave = setTimeout(() => api('setTyping', { value: typingVolume }), 250);
};

function hint(text, warn) {
  const h = $('#scHint');
  h.textContent = text;
  h.classList.toggle('warn', !!warn);
}

async function stopRecording(cancel) {
  recordingKeys = false;
  $('#scRec').textContent = 'Change';
  $('#scRec').classList.remove('rec');
  if (cancel) await api('cancelRecord');
  renderSettings(await api('settings'));
}

async function openSettings() {
  if (!state.root) return;
  await flush();
  state.note = null;
  hint('Hold these keys together to open or close your notes.');
  renderSettings(await api('settings'));
  showView('settingsView');
}

$('#setBtn').onclick = openSettings;
$('#setBack').onclick = async () => { if (recordingKeys) await stopRecording(true); await loadNotes(); showView('listView'); };
$('#scRec').onclick = async () => {
  if (recordingKeys) { await stopRecording(true); hint('Hold these keys together to open or close your notes.'); return; }
  recordingKeys = true;
  $('#scRec').textContent = 'Cancel';
  $('#scRec').classList.add('rec');
  renderKeys([], true);
  hint('Use two or more of ⌘ ⌥ ⌃ ⇧ (left and right count separately), then let go.');
  await api('recordShortcut');
};
window.onShortcutLive = keys => { if (recordingKeys) renderKeys(keys, true); };
window.onShortcutDone = async ok => {
  await stopRecording(false);
  hint(ok ? 'Saved. Try it now.' : 'That was only one key. Hold at least two together.', !ok);
};
$('#themeSeg').onclick = async e => {
  const b = e.target.closest('button');
  if (b) renderSettings(await api('setTheme', { value: b.dataset.v }));
};
$('#setFolder').onclick = () => api('chooseRoot');
$('#swWidget').onclick = async () => renderSettings(await api('toggleWidget'));
$('#swLogin').onclick = async () => renderSettings(await api('toggleLogin'));
$('#swSpell').onclick = async () => renderSettings(await api('toggleSpell'));

// ---------- Window chrome ----------

document.addEventListener('mousedown', e => {
  if (e.button !== 0) return;
  if (e.target.id === 'grip') { e.preventDefault(); api('drag', { mode: 'resize' }); return; }
  if (e.target.id === 'app' || e.target.closest('[data-drag]') && !e.target.closest('button,input,a,label,[contenteditable]')) {
    e.preventDefault();
    api('drag', { mode: 'move' });
  }
});

document.addEventListener('keydown', e => {
  if (e.key === 'Escape') {
    if (popAnchor) return closePop();
    if (recordingKeys) return stopRecording(true);
    flush().then(() => api('hide'));
  }
  if (e.metaKey && e.key === ',') { e.preventDefault(); openSettings(); }
  if (e.metaKey && e.key.toLowerCase() === 'w') { e.preventDefault(); flush().then(() => api('hide')); }
  if (e.metaKey && e.key.toLowerCase() === 'f' && state.view === 'listView') { e.preventDefault(); $('#search').focus(); }
  // "\" jumps to search from the notes list, unless you are already typing somewhere.
  if (e.key === '\\' && !e.metaKey && !e.ctrlKey && state.view === 'listView' && !popAnchor && !renaming
      && !document.activeElement.matches('input, [contenteditable]')) { e.preventDefault(); $('#search').focus(); }
});

// ---------- HTML examples ----------
// A code block marked html (or that plainly is a web page) gets a live preview above it.
// The preview is sealed off: it cannot reach the notes, the app or the network.
const isHTML = pre => /^(html?|svg)$/i.test(pre.dataset.lang || '') || (!pre.dataset.lang && /^\s*<(!doctype html|html[\s>])/i.test(pre.textContent));
const HP_HEAD = '<meta charset="utf-8"><meta http-equiv="Content-Security-Policy" content="default-src \'none\'; style-src \'unsafe-inline\'; script-src \'unsafe-inline\'; img-src data:; font-src data:">'
  + '<style>html{color-scheme:light}body{margin:14px;font:14px/1.5 -apple-system,system-ui,sans-serif;color:#1d1d1f}</style>';
const HP_TAIL = '<script>(()=>{const say=()=>parent.postMessage({hp:Math.ceil(document.documentElement.getBoundingClientRect().height)},"*");new ResizeObserver(say).observe(document.documentElement);addEventListener("load",say);say()})()</' + 'script>';
function renderPreviews(collapse) {
  const caret = getSelection().anchorNode;
  editor.querySelectorAll('.htmlprev').forEach(v => { const pre = v.nextElementSibling; if (!pre || pre.tagName !== 'PRE' || !isHTML(pre)) v.remove(); });
  editor.querySelectorAll('pre').forEach(pre => {
    let v = pre.previousElementSibling;
    if (!v || !v.classList.contains('htmlprev')) v = null;
    // The preview was deleted while its code was tucked away: the code goes with it.
    if (!v && pre.classList.contains('hp-hidden')) { pre.remove(); ensureTail(); return; }
    if (!isHTML(pre)) return;
    const code = pre.textContent;
    if (!v) {
      if (!code.trim()) return;
      v = el('div', 'htmlprev');
      v.contentEditable = 'false';
      v.innerHTML = '<div class="hp-bar"><span>Preview</span><button></button></div><iframe sandbox="allow-scripts"></iframe>';
      const b = v.querySelector('button');
      const label = () => (b.textContent = pre.classList.contains('hp-hidden') ? 'Show code' : 'Hide code');
      b.onclick = e => { e.preventDefault(); pre.classList.toggle('hp-hidden'); label(); };
      pre.before(v);
      if (collapse && !pre.contains(caret)) pre.classList.add('hp-hidden');
      label();
    }
    if (v.dataset.code !== code) { v.dataset.code = code; v.querySelector('iframe').srcdoc = HP_HEAD + code + HP_TAIL; }
  });
}
addEventListener('message', e => {
  if (!e.data || typeof e.data.hp !== 'number') return;
  for (const f of editor.querySelectorAll('.htmlprev iframe')) {
    if (f.contentWindow === e.source) f.style.height = Math.max(40, Math.min(e.data.hp, 640)) + 'px';
  }
});

window.onPanelShow = async () => {
  const app = $('#app');
  app.classList.remove('intro');
  void app.offsetWidth;
  app.classList.add('intro');
  if (state.view === 'editorView') { restoreSel(); return; }
  await refresh();
};
window.onPanelHide = () => { closePop(); flush(); if (recordingKeys) stopRecording(false); };
window.addEventListener('blur', () => flush());

// A window opened for one note goes straight to it.
(async () => {
  const q = new URLSearchParams(location.search);
  if (!q.has('open')) return refresh();
  const s = await api('state');
  if (s.envs.includes(q.get('env'))) s.env = q.get('env');
  apply(s);
  if (!state.root) return showView('welcome');
  await loadNotes(false);
  const n = state.notes.find(x => x.path === q.get('open'));
  $('#app').classList.add('intro');
  if (!n || (await openNote(n)) === false) showView('listView');
})();
