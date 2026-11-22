// Markdown <-> editor DOM. ctx = { env, cat } tells us where the note lives so
// attachment links (stored in <env>/_assets) can be written relative to the note.
const MD = (() => {
  const esc = s => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  const prefix = ctx => (ctx && ctx.cat ? '../' : '');
  const assetURL = (rel, ctx) => 'margin://file/' + encodeURI(ctx.env + '/' + rel);

  function localRel(href) {
    if (/^[a-z][a-z0-9+.-]*:/i.test(href) || href.startsWith('#') || href.startsWith('//')) return null;
    let p = href;
    try { p = decodeURIComponent(href); } catch (e) {}
    return p.replace(/^(\.\.\/|\.\/)+/, '');
  }

  // A width is kept in the alt text as "name|320" (the form Obsidian also understands).
  const splitAlt = alt => { const m = /^(.*)\|(\d{2,4})$/.exec(alt || ''); return m ? [m[1], +m[2]] : [alt || '', 0]; };
  const sizeAttr = w => (w ? ` data-w="${w}" style="width:${w}px"` : '');
  const imgHTML = (rel, alt, ctx, width) => {
    const [a, w] = splitAlt(alt);
    return `<img src="${esc(assetURL(rel, ctx))}" data-rel="${esc(rel)}" alt="${esc(a)}"${sizeAttr(width || w)}>`;
  };
  const chipHTML = (rel, name) =>
    `<a class="file" contenteditable="false" href="#" data-rel="${esc(rel)}" data-name="${esc(name)}">${esc(name)}</a>`;

  // ---------- Markdown -> HTML ----------

  // No lookbehind assertions here: older Safari engines (before 16.4, e.g. early macOS 13) reject the whole file.
  function emph(s) {
    return s
      .replace(/\*\*\*(\S(?:[\s\S]*?\S)??)\*\*\*/g, '<strong><em>$1</em></strong>')
      .replace(/\*\*(\S(?:[\s\S]*?\S)??)\*\*/g, '<strong>$1</strong>')
      .replace(/(^|\W)__(\S(?:[\s\S]*?\S)??)__(?!\w)/g, '$1<strong>$2</strong>')
      .replace(/\*([^*\s](?:[^*]*?[^*\s])??)\*/g, '<em>$1</em>')
      .replace(/(^|\W)_([^_\s](?:[^_]*?[^_\s])??)_(?!\w)/g, '$1<em>$2</em>')
      .replace(/~~(\S(?:[\s\S]*?\S)??)~~/g, '<s>$1</s>');
  }

  function inline(src, ctx) {
    const stash = [];
    const keep = h => { stash.push(h); return '\u0000' + (stash.length - 1) + '\u0000'; };
    let s = src;
    s = s.replace(/\\([\\`*_{}\[\]()#+\-.!|<>~])/g, (m, c) => keep(esc(c)));
    s = s.replace(/`([^`\n]+)`/g, (m, c) => keep('<code>' + esc(c) + '</code>'));
    s = s.replace(/!\[([^\]]*)\]\(\s*<?([^)\s>]+)>?(?:\s+"[^"]*")?\s*\)/g, (m, alt, href) => {
      const rel = localRel(href);
      if (rel != null) return keep(imgHTML(rel, alt, ctx));
      const [a, w] = splitAlt(alt);
      return keep(`<img src="${esc(href)}" alt="${esc(a)}"${sizeAttr(w)}>`);
    });
    s = s.replace(/\[([^\]]+)\]\(\s*<?([^)\s>]+)>?(?:\s+"[^"]*")?\s*\)/g, (m, text, href) => {
      const rel = localRel(href);
      if (rel != null) return keep(chipHTML(rel, text.replace(/^📎\s*/, '')));
      return keep(`<a href="${esc(href)}">${emph(esc(text))}</a>`);
    });
    s = s.replace(/<(https?:\/\/[^>\s]+)>/g, (m, u) => keep(`<a href="${esc(u)}">${esc(u)}</a>`));
    s = esc(s);
    s = s.replace(/&lt;u&gt;([\s\S]*?)&lt;\/u&gt;/g, '<u>$1</u>').replace(/&lt;br\s*\/?&gt;/g, '<br>');
    s = s.replace(/(^|[\s(])(https?:\/\/[^\s<]+[^\s<.,;:!?)\]'"])/g, (m, p, u) => p + keep(`<a href="${u}">${u}</a>`));
    s = emph(s);
    for (let i = 0; i < 6 && /\u0000\d+\u0000/.test(s); i++) s = s.replace(/\u0000(\d+)\u0000/g, (m, n) => stash[+n]);
    return s;
  }

  const lines2html = (ls, ctx) => ls.map(l => inline(l.replace(/(\\| {2,})$/, ''), ctx)).join('<br>');

  const LIST = /^(\s*)([-*+]|\d{1,9}[.)])\s+(.*)$/;
  const HR = /^\s{0,3}([-*_])(\s*\1){2,}\s*$/;
  const SEP = /^\s*\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)*\|?\s*$/;

  function list(lines, ctx) {
    const items = [];
    for (const l of lines) {
      const m = l.match(LIST);
      if (m) items.push({ indent: m[1].replace(/\t/g, '    ').length, ordered: /\d/.test(m[2]), text: [m[3]] });
      else if (items.length && l.trim()) items[items.length - 1].text.push(l.trim());
    }
    let pos = 0;
    const open = t => (t === 'ol' ? '<ol>' : t === 'tasks' ? '<ul class="tasks">' : '<ul>');
    const close = t => (t === 'ol' ? '</ol>' : '</ul>');
    function build(indent) {
      let html = '', cur = null;
      while (pos < items.length && items[pos].indent >= indent) {
        const it = items[pos++];
        const t = it.text[0].match(/^\[([ xX])\](?:\s+([\s\S]*))?$/);
        if (t) it.text[0] = t[2] || '';
        const type = it.ordered ? 'ol' : t ? 'tasks' : 'ul';
        if (cur !== type) { if (cur) html += close(cur); html += open(type); cur = type; }
        const inner = lines2html(it.text.filter((x, i) => x || i), ctx);
        let child = '';
        if (pos < items.length && items[pos].indent > it.indent) child = build(items[pos].indent);
        html += `<li${t && t[1] !== ' ' ? ' data-checked="true"' : ''}>${inner || '<br>'}${child}</li>`;
      }
      return html + (cur ? close(cur) : '');
    }
    return build(items[0].indent);
  }

  // Splits on | unless escaped as \|, without a lookbehind (older Safari engines reject those).
  const splitPipes = s => { const out = []; let cur = ''; for (let i = 0; i < s.length; i++) { if (s[i] === '|' && s[i - 1] !== '\\') { out.push(cur); cur = ''; } else cur += s[i]; } out.push(cur); return out; };
  const cells = row => splitPipes(row.trim().replace(/^\|/, '').replace(/\|$/, '')).map(c => c.trim());

  function blocks(lines, ctx) {
    let out = '', i = 0;
    const para = [];
    const flush = () => { if (para.length) { out += '<p>' + lines2html(para, ctx) + '</p>'; para.length = 0; } };
    while (i < lines.length) {
      const line = lines[i];
      let m;
      if (/^\s*$/.test(line)) { flush(); i++; continue; }
      if ((m = line.match(/^\s{0,3}(```+|~~~+)\s*([\w+-]*)/))) {
        flush();
        const buf = [];
        i++;
        while (i < lines.length && !lines[i].trim().startsWith(m[1])) buf.push(lines[i++]);
        i++;
        out += `<pre data-lang="${m[2]}"><code>${esc(buf.join('\n')) || '<br>'}</code></pre>`;
        continue;
      }
      if ((m = line.match(/^\s{0,3}(#{1,6})\s+(.*?)\s*#*\s*$/))) {
        flush();
        const n = Math.min(m[1].length, 3);
        out += `<h${n}>${inline(m[2], ctx)}</h${n}>`;
        i++;
        continue;
      }
      if (HR.test(line)) { flush(); out += '<hr>'; i++; continue; }
      if (/^\s{0,3}>/.test(line)) {
        flush();
        const buf = [];
        while (i < lines.length && /^\s{0,3}>/.test(lines[i])) buf.push(lines[i++].replace(/^\s{0,3}>\s?/, ''));
        out += '<blockquote>' + blocks(buf, ctx) + '</blockquote>';
        continue;
      }
      if (line.includes('|') && i + 1 < lines.length && lines[i + 1].includes('|') && SEP.test(lines[i + 1])) {
        flush();
        const head = cells(line);
        i += 2;
        let h = '<table><thead><tr>' + head.map(c => `<th>${inline(c, ctx) || '<br>'}</th>`).join('') + '</tr></thead><tbody>';
        while (i < lines.length && lines[i].includes('|') && lines[i].trim()) {
          const row = cells(lines[i++]);
          h += '<tr>' + head.map((_, k) => `<td>${inline(row[k] || '', ctx) || '<br>'}</td>`).join('') + '</tr>';
        }
        out += h + '</tbody></table>';
        continue;
      }
      if (LIST.test(line)) {
        flush();
        const buf = [];
        while (i < lines.length) {
          const l = lines[i];
          if (LIST.test(l) || /^\s+\S/.test(l)) { buf.push(l); i++; continue; }
          if (!l.trim() && i + 1 < lines.length && (LIST.test(lines[i + 1]) || /^\s+\S/.test(lines[i + 1])) && !HR.test(lines[i + 1])) { i++; continue; }
          break;
        }
        out += list(buf, ctx);
        continue;
      }
      para.push(line.trim());
      i++;
    }
    flush();
    return out;
  }

  const parse = (md, ctx) => blocks((md || '').replace(/\r\n?/g, '\n').split('\n'), ctx);

  // ---------- DOM -> Markdown ----------

  const BLOCK = new Set(['P', 'DIV', 'H1', 'H2', 'H3', 'H4', 'H5', 'H6', 'UL', 'OL', 'LI', 'BLOCKQUOTE', 'PRE', 'TABLE', 'HR',
    'FIGURE', 'FIGCAPTION', 'SECTION', 'ARTICLE', 'HEADER', 'FOOTER', 'MAIN', 'ASIDE', 'NAV', 'DL', 'DT', 'DD', 'DETAILS', 'SUMMARY']);
  const SKIP = new Set(['SCRIPT', 'STYLE', 'META', 'LINK', 'TITLE', 'HEAD', 'BUTTON', 'INPUT', 'SELECT', 'TEXTAREA', 'SVG', 'NOSCRIPT', 'TEMPLATE']);

  const escText = t => t
    .replace(/([\\`*\[\]<])/g, '\\$1')
    .replace(/~~/g, '\\~\\~')
    .replace(/_/g, (m, off, str) => (/\w/.test(str[off - 1] || '') && /\w/.test(str[off + 1] || '') ? '_' : '\\_'));

  const wrap = (a, s, b) => {
    const m = s.match(/^(\s*)([\s\S]*?)(\s*)$/);
    return m[2] ? m[1] + a + m[2] + (b || a) + m[3] : s;
  };
  const tidy = t => t.replace(/^(\\?\n|\s)+|(\\?\n|\s)+$/g, '').replace(/[ \t]*(\\?)\n[ \t]*/g, '\\\n');
  const guard = t => (/^\d+[.)]\s/.test(t) ? t.replace(/^(\d+)([.)])/, '$1\\$2')
    : /^(#{1,6}\s|>|[-+]\s|```|~~~)/.test(t) || HR.test(t.split('\n')[0]) ? '\\' + t : t);
  const encPath = p => encodeURI(p).replace(/\(/g, '%28').replace(/\)/g, '%29');

  function preText(n) {
    let out = '';
    for (const c of n.childNodes) {
      if (c.nodeType === 3) out += c.data;
      else if (c.nodeType === 1) {
        if (c.tagName === 'BR') out += '\n';
        else if (!SKIP.has(c.tagName.toUpperCase())) {
          out += preText(c);
          if (c.tagName === 'DIV' || c.tagName === 'P') out += '\n';
        }
      }
    }
    return out;
  }

  function inlineNodes(nodes, ctx) {
    let out = '';
    for (const n of nodes) out += inlineNode(n, ctx);
    return out;
  }

  function inlineNode(n, ctx) {
    if (n.nodeType === 3) return escText(n.data.replace(/ /g, ' ').replace(/\s+/g, ' '));
    if (n.nodeType !== 1) return '';
    const tag = n.tagName.toUpperCase();
    if (SKIP.has(tag) || n.classList.contains('htmlprev')) return '';
    const kids = () => inlineNodes(n.childNodes, ctx);
    switch (tag) {
      case 'BR': return '\\\n';
      case 'B': case 'STRONG': return wrap('**', kids());
      case 'I': case 'EM': return wrap('*', kids());
      case 'U': case 'INS': return wrap('<u>', kids(), '</u>');
      case 'S': case 'DEL': case 'STRIKE': return wrap('~~', kids());
      case 'CODE': case 'KBD': case 'TT': return n.textContent.trim() ? '`' + n.textContent.replace(/`/g, "'") + '`' : '';
      case 'IMG': {
        const rel = n.dataset.rel;
        const src = rel ? encPath(prefix(ctx) + rel) : n.getAttribute('src');
        if (!src || /^(margin|blob|file):/.test(src)) return '';
        const w = parseInt(n.dataset.w, 10);
        return `![${escText(n.getAttribute('alt') || '')}${w ? '|' + w : ''}](${src.replace(/\s/g, '%20').replace(/\)/g, '%29')})`;
      }
      case 'A': {
        if (n.dataset.rel) return `[📎 ${escText(n.dataset.name || n.textContent)}](${encPath(prefix(ctx) + n.dataset.rel)})`;
        const href = n.getAttribute('href') || '';
        const t = kids().trim();
        if (!t) return '';
        if (/^https?:\/\/[^\s<>]+$/.test(href) && n.textContent.trim() === href) return '<' + href + '>';
        if (!/^(https?:|mailto:)/i.test(href)) return t;
        return `[${t.replace(/\\?\n/g, ' ')}](${href.replace(/\s/g, '%20').replace(/\(/g, '%28').replace(/\)/g, '%29')})`;
      }
      case 'SPAN': case 'FONT': {
        let t = kids();
        const st = n.style;
        if (/^(bold|[6-9]00)$/.test(st.fontWeight)) t = wrap('**', t);
        if (st.fontStyle === 'italic') t = wrap('*', t);
        if (/line-through/.test(st.textDecoration + st.textDecorationLine)) t = wrap('~~', t);
        return t;
      }
      case 'UL': case 'OL': return '\n' + listMD(n, ctx, '');
      default: return BLOCK.has(tag) ? kids() + '\n' : kids();
    }
  }

  function listMD(el, ctx, indent) {
    let out = '', i = 0;
    const ordered = el.tagName === 'OL';
    for (const li of el.children) {
      if (li.tagName === 'UL' || li.tagName === 'OL') { out += listMD(li, ctx, indent + '    '); continue; }
      if (li.tagName !== 'LI') continue;
      i++;
      const cb = li.querySelector('input[type=checkbox]');
      const isTask = el.classList.contains('tasks') || !!cb || li.classList.contains('task-list-item');
      const checked = li.dataset.checked === 'true' || !!(cb && cb.checked);
      const inl = [], nested = [];
      for (const c of li.childNodes) {
        if (c.nodeType === 1 && (c.tagName === 'UL' || c.tagName === 'OL')) nested.push(c);
        else inl.push(c);
      }
      const text = tidy(inlineNodes(inl, ctx)).replace(/\n/g, '\n' + indent + '    ');
      const marker = ordered ? i + '. ' : isTask ? `- [${checked ? 'x' : ' '}] ` : '- ';
      out += indent + marker + text + '\n';
      for (const nl of nested) out += listMD(nl, ctx, indent + '    ');
    }
    return out;
  }

  function tableMD(t, ctx) {
    const rows = [...t.querySelectorAll('tr')].filter(r => r.closest('table') === t)
      .map(r => [...r.children].filter(c => c.tagName === 'TD' || c.tagName === 'TH')
        .map(c => tidy(inlineNodes(c.childNodes, ctx)).replace(/\|/g, '\\|').replace(/\\?\n/g, '<br>') || ' '));
    if (!rows.length) return '';
    const w = Math.max(...rows.map(r => r.length));
    const line = r => '| ' + Array.from({ length: w }, (_, k) => r[k] || ' ').join(' | ') + ' |';
    return [line(rows[0]), '| ' + Array(w).fill('---').join(' | ') + ' |', ...rows.slice(1).map(line)].join('\n') + '\n\n';
  }

  function blockChildren(el, ctx) {
    let out = '', run = [];
    const flush = () => {
      if (!run.length) return;
      const t = tidy(inlineNodes(run, ctx));
      if (t) out += guard(t) + '\n\n';
      run = [];
    };
    for (const n of el.childNodes) {
      if (n.nodeType === 1 && n.classList.contains('htmlprev')) continue; // the live preview is display only
      if (n.nodeType === 1 && BLOCK.has(n.tagName.toUpperCase())) { flush(); out += block(n, ctx); }
      else if (n.nodeType === 1 || n.nodeType === 3) run.push(n);
    }
    flush();
    return out;
  }

  const hasBlock = el => [...el.children].some(c => BLOCK.has(c.tagName.toUpperCase()));

  function block(n, ctx) {
    const tag = n.tagName.toUpperCase();
    switch (tag) {
      case 'H1': case 'H2': case 'H3': case 'H4': case 'H5': case 'H6': {
        const t = tidy(inlineNodes(n.childNodes, ctx)).replace(/\\?\n/g, ' ');
        return t ? '#'.repeat(Math.min(+tag[1], 3)) + ' ' + t + '\n\n' : '';
      }
      case 'UL': case 'OL': return listMD(n, ctx, '') + '\n';
      case 'LI': return '- ' + tidy(inlineNodes(n.childNodes, ctx)) + '\n\n';
      case 'BLOCKQUOTE': {
        const inner = blockChildren(n, ctx).trim();
        return inner ? inner.split('\n').map(l => (l ? '> ' + l : '>')).join('\n') + '\n\n' : '';
      }
      case 'PRE': {
        const code = n.querySelector('code');
        const lang = n.dataset.lang || ((code && code.className.match(/language-([\w+-]+)/)) || [])[1] || '';
        return '```' + lang + '\n' + preText(code || n).replace(/\n+$/, '') + '\n```\n\n';
      }
      case 'TABLE': return tableMD(n, ctx);
      case 'HR': return '---\n\n';
      default: {
        if (hasBlock(n)) return blockChildren(n, ctx);
        const t = tidy(inlineNodes(n.childNodes, ctx));
        return t ? guard(t) + '\n\n' : '';
      }
    }
  }

  const serialize = (root, ctx) => {
    const out = blockChildren(root, ctx).replace(/\n{3,}/g, '\n\n').trim();
    return out ? out + '\n' : '';
  };

  return { parse, serialize, imgHTML, chipHTML, esc };
})();
