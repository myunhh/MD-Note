/* MD Note web bridge.
 *
 * Responsibilities:
 *   1. Render markdown with markdown-it.
 *   2. Tag every top-level block with a stable identity (content hash + seq) and
 *      its source line, matching the Swift `MDNoteCore` model.
 *   3. Expose geometry so the native layer can anchor ink to blocks.
 *
 * The hashing here is a byte-for-byte match of Swift `Hashing.fnv1a` /
 * `Hashing.normalize`, so block identities are interchangeable across the JS
 * and Swift sides.
 */
(function () {
  "use strict";

  var PAGE_WIDTH = 1390;
  var paperStyle = "plain";
  var textScale = 1;
  var searchQuery = "";
  var searchIndex = 0;
  var searchRevision = -1;
  var searchRanges = [];
  var source = "", revision = 0, editing = false, activeEditor = null;
  var sourceBlocks = [], studyInsertions = [], selectedBlockID = null;
  var documentUndo = [], documentRedo = [];
  var studyBlocks = new Map(), announcedText = new Map();
  var historyIDs = new Map();

  function post(name, value) {
    var handler = window.webkit && window.webkit.messageHandlers[name];
    if (handler) handler.postMessage(value);
    window.dispatchEvent(new CustomEvent("mdnote:" + name, { detail: value }));
  }

  function editorState(extra) {
    var state = activeEditor && activeEditor.editor ? activeEditor.editor.status() : {};
    var value = Object.assign({ composing: false }, state, extra || {});
    value.canUndo = !!value.canUndo || documentUndo.length > 0;
    value.canRedo = !!value.canRedo || documentRedo.length > 0;
    post("editorState", value);
  }

  function snapshot() {
    if (activeEditor && activeEditor.editor && activeEditor.editor.status().composing) {
      throw new Error("composition-in-progress");
    }
    var key = JSON.stringify(sourceState());
    if (!historyIDs.has(key)) historyIDs.set(key, crypto.randomUUID());
    return { markdown: source, revision: revision, composing: false,
      historyID: historyIDs.get(key), edits: [], mappings: [] };
  }

  function sourceState() {
    return { markdown: source, ids: sourceBlocks.map(function (b) { return b.id; }),
      studies: JSON.parse(JSON.stringify(studyInsertions)) };
  }

  function remember() {
    documentUndo.push(sourceState());
    documentRedo = [];
  }

  function announceEdit(mappings) {
    revision++;
    var value = snapshot();
    value.mappings = mappings || [];
    var nextText = new Map();
    document.querySelectorAll("#content [data-block-id]").forEach(function (el) {
      if (el.matches("[data-study-id]") && el.querySelector("[data-block-id]")) return;
      var id = el.dataset.blockId, text = el.textContent || "";
      if (el.classList.contains("rich-editor-host")) {
        el.dataset.blockText = text;
        el.dataset.blockHash = blockHash(text);
      }
      nextText.set(id, text);
      var old = announcedText.get(id);
      if (old == null || old === text || value.mappings.some(function (m) { return m.fromBlockID === id; })) return;
      var start = 0, end = old.length, nextEnd = text.length;
      while (start < end && start < nextEnd && old[start] === text[start]) start++;
      while (end > start && nextEnd > start && old[end - 1] === text[nextEnd - 1]) { end--; nextEnd--; }
      var segmenter = new Intl.Segmenter(undefined, { granularity: "grapheme" });
      var oldEdges = new Set(Array.from(segmenter.segment(old), function (s) { return s.index; }).concat([old.length]));
      var newEdges = new Set(Array.from(segmenter.segment(text), function (s) { return s.index; }).concat([text.length]));
      while (start > 0 && (!oldEdges.has(start) || !newEdges.has(start))) start--;
      while (end < old.length && !oldEdges.has(end)) end++;
      while (nextEnd < text.length && !newEdges.has(nextEnd)) nextEnd++;
      value.edits.push({ blockID: id, startUTF16: start, endUTF16: end, insertedText: text.slice(start, nextEnd), oldText: old });
    });
    announcedText = nextText;
    post("documentEdited", value);
    editorState();
    scheduleLayoutNotify();
  }

  function parseSource(markdown, identities) {
    var body = stripFrontMatter(markdown);
    var prefixLength = markdown.length - body.length;
    var lines = body.match(/[^\n]*\n|[^\n]+$/g) || [];
    var offsets = [prefixLength];
    lines.forEach(function (line) { offsets.push(offsets[offsets.length - 1] + line.length); });
    var tokens = md.parse(body, {});
    return tokens.filter(function (t) { return t.map && t.level === 0 && t.nesting >= 0; })
      .map(function (t, i) {
        var identity = identities && identities[i];
        return { id: typeof identity === "string" ? identity : identity && identity.blockID || crypto.randomUUID(),
          start: offsets[t.map[0]], end: offsets[t.map[1]] == null ? markdown.length : offsets[t.map[1]],
          line: t.map[0] };
      });
  }
  function indexSource(markdown, identities) { sourceBlocks = parseSource(markdown, identities); }

  function bindBlockIDs(root) {
    root.querySelectorAll("[data-source-line]").forEach(function (el) {
      if (el.closest("[data-study-id]")) return;
      var entry = sourceBlocks.find(function (b) { return b.line === Number(el.dataset.sourceLine); });
      if (entry) el.dataset.blockId = entry.id;
      if (editing) { el.tabIndex = 0; el.setAttribute("role", "group"); }
    });
  }

  function closeEditor() {
    if (!activeEditor) return true;
    if (activeEditor.editor && activeEditor.editor.status().composing) return false;
    var old = activeEditor;
    activeEditor = null;
    if (old.editor) old.editor.destroy();
    var previous = old.study ? studyBlocks.get(old.study.id) : sourceBlocks;
    var next = parseSource(old.study ? old.study.markdown : source);
    next.forEach(function (b) {
      var match = previous.find(function (p) { return p.start === b.start; });
      if (match) b.id = match.id;
    });
    if (old.study) {
      old.study.blockIDs = next.map(function (b) { return b.id; });
      studyBlocks.set(old.study.id, next);
      post("studyInsertionsChanged", studyInsertions);
    } else sourceBlocks = next;
    var split = next.filter(function (b) { return b.start >= old.block.start && b.start < old.block.end; });
    var mappings = [], offset = 0;
    if (split.length > 1) split.forEach(function (b) {
      var text = blockText((old.study ? old.study.markdown : source).slice(b.start, b.end));
      mappings.push({ fromBlockID: old.block.id, toBlockID: b.id, fromStartUTF16: offset,
        fromEndUTF16: offset + text.length, offsetDeltaUTF16: -offset, targetText: text });
      offset += text.length;
    });
    draw();
    announceEdit(mappings);
    editorState();
    return true;
  }

  function replaceBlock(block, value) {
    var study = activeEditor && activeEditor.study;
    var original = study ? study.markdown : source;
    var entries = study ? studyBlocks.get(study.id) : sourceBlocks;
    var previous = original.slice(block.start, block.end);
    var ending = previous.match(/(?:\r?\n)*$/)[0];
    var normalized = value.replace(/\r\n?/g, "\n").replace(/\n/g, previous.includes("\r\n") ? "\r\n" : "\n").replace(/(?:\r?\n)*$/, "");
    var replacement = normalized + ending;
    if (replacement === previous) return;
    if (activeEditor && !activeEditor.remembered) { remember(); activeEditor.remembered = true; }
    var delta = replacement.length - previous.length, oldEnd = block.end;
    var updated = original.slice(0, block.start) + replacement + original.slice(block.end);
    if (study) study.markdown = updated;
    else source = updated;
    entries.forEach(function (entry) {
      if (entry === block) entry.end += delta;
      else if (entry.start >= oldEnd) { entry.start += delta; entry.end += delta; }
    });
    if (study) post("studyInsertionsChanged", studyInsertions);
    announceEdit();
  }

  function blockText(markdown) {
    var container = document.createElement("div");
    container.innerHTML = md.render(markdown);
    return Array.from(container.children).map(function (el) { return el.textContent || ""; }).join("");
  }

  function mergeBoundary(direction) {
    if (!activeEditor || activeEditor.study) return false;
    var id = activeEditor.block.id;
    if (!closeEditor()) return false;
    var index = sourceBlocks.findIndex(function (b) { return b.id === id; });
    var other = index + direction;
    if (other < 0 || other >= sourceBlocks.length) return false;
    var left = sourceBlocks[Math.min(index, other)], right = sourceBlocks[Math.max(index, other)];
    var leftRaw = source.slice(left.start, left.end), rightRaw = source.slice(right.start, right.end);
    if (!MDNoteRichEditor.supports(leftRaw) || !MDNoteRichEditor.supports(rightRaw) ||
        md.parse(leftRaw, {})[0].type !== "paragraph_open" || md.parse(rightRaw, {})[0].type !== "paragraph_open") return false;
    remember();
    var leftText = blockText(leftRaw), rightText = blockText(rightRaw);
    var replacement = leftRaw.trimEnd() + rightRaw.trimEnd() + (rightRaw.match(/(?:\r?\n)*$/)[0] || "\n\n");
    var previous = sourceBlocks, delta = replacement.length - (right.end - left.start);
    source = source.slice(0, left.start) + replacement + source.slice(right.end);
    indexSource(source);
    sourceBlocks.forEach(function (b) {
      var oldStart = b.start > left.start ? b.start - delta : b.start;
      var match = previous.find(function (p) { return p.start === oldStart && p !== right; });
      if (match) b.id = match.id;
    });
    draw();
    announceEdit([{ fromBlockID: right.id, toBlockID: left.id, fromStartUTF16: 0,
      fromEndUTF16: rightText.length, offsetDeltaUTF16: leftText.length, targetText: leftText + rightText }]);
    openBlock(document.querySelector('[data-block-id="' + CSS.escape(left.id) + '"]'), false, leftText.length);
    return true;
  }

  function openBlock(el, forceSource, cursor) {
    if (!editing || !el || !closeEditor()) return false;
    var id = el.dataset.blockId;
    el = document.querySelector('[data-block-id="' + CSS.escape(id) + '"]');
    var studyElement = el && el.closest("[data-study-id]");
    var study = studyElement && studyInsertions.find(function (s) { return s.id === studyElement.dataset.studyId; });
    var entries = study ? studyBlocks.get(study.id) || [] : sourceBlocks;
    var block = entries.find(function (b) { return b.id === id; });
    if (!block || !el) return false;
    selectedBlockID = id;
    var raw = (study ? study.markdown : source).slice(block.start, block.end);
    if (forceSource || !MDNoteRichEditor.supports(raw)) {
      openSource(block, el, raw, study);
      return true;
    }
    var host = document.createElement("div");
    host.className = "rich-editor-host";
    Array.prototype.forEach.call(el.attributes, function (a) {
      if (a.name.indexOf("data-") === 0) host.setAttribute(a.name, a.value);
    });
    el.replaceWith(host);
    activeEditor = { block: block, study: study, host: host, editor: null };
    try {
      activeEditor.editor = MDNoteRichEditor.create(host, raw, {
        label: document.documentElement.lang === "ko" ? "마크다운 본문 편집" : "Edit Markdown block",
        change: function (value, transaction) {
          replaceBlock(block, value);
          if (transaction && transaction.blockCount > 1 && parseSource(value).length > 1 && !activeEditor.pendingSplit) {
            var current = activeEditor;
            current.pendingSplit = true;
            setTimeout(function () {
              if (activeEditor !== current || current.editor.status().composing) return;
              var start = current.block.start, end = current.block.end;
              if (!closeEditor()) return;
              var entries = current.study ? studyBlocks.get(current.study.id) : sourceBlocks;
              var split = entries.filter(function (b) { return b.start >= start && b.start < end; });
              var offset = transaction.cursor, target = split[split.length - 1];
              for (var i = 0; i < split.length; i++) {
                var text = blockText((current.study ? current.study.markdown : source).slice(split[i].start, split[i].end));
                if (offset < text.length || i === split.length - 1) { target = split[i]; break; }
                offset -= text.length;
              }
              if (target) openBlock(document.querySelector('[data-block-id="' + CSS.escape(target.id) + '"]'), false, offset);
            }, 0);
          }
        },
        state: function (state) { editorState(state); },
        finish: closeEditor,
        boundary: mergeBoundary,
        history: editorCommand,
        cursor: cursor
      });
    } catch (error) {
      activeEditor = null;
      draw();
      editorState({ error: String(error.message || error) });
      return false;
    }
    return true;
  }

  function openSource(block, el, raw, study) {
    var host = document.createElement("div");
    host.className = "source-editor";
    var label = document.createElement("label");
    label.textContent = document.documentElement.lang === "ko" ? "원문 편집 · 확장 문법 보존" : "Source editing · preserve extended syntax";
    var input = document.createElement("textarea");
    input.value = raw;
    label.appendChild(input);
    host.appendChild(label);
    var composing = false;
    input.addEventListener("compositionstart", function () { composing = true; editorState({ composing: true }); });
    input.addEventListener("compositionend", function () { composing = false; editorState({ composing: false }); });
    [["Apply", "적용", function () {
      if (composing) return;
      remember();
      activeEditor.remembered = true;
      replaceBlock(block, input.value);
      closeEditor();
    }], ["Cancel", "취소", closeEditor]].forEach(function (item) {
      var button = document.createElement("button");
      button.textContent = document.documentElement.lang === "ko" ? item[1] : item[0];
      button.onclick = item[2];
      host.appendChild(button);
    });
    el.replaceWith(host);
    activeEditor = { block: block, study: study, host: host, editor: {
      status: function () { return { composing: composing, canUndo: false, canRedo: false }; },
      value: function () { throw new Error("source-edit-needs-apply"); },
      destroy: function () {}
    }};
    input.focus();
  }

  function flushEditor() {
    if (activeEditor) {
      if (activeEditor.host.classList.contains("source-editor")) throw new Error("source-edit-needs-apply");
      replaceBlock(activeEditor.block, activeEditor.editor.value());
    }
    return snapshot();
  }

  function setTextEditing(enabled) {
    if (!enabled && !closeEditor()) return false;
    editing = !!enabled;
    document.documentElement.classList.toggle("text-editing", editing);
    bindBlockIDs(document.getElementById("content"));
    editorState();
    return true;
  }

  function editorCommand(command) {
    if (activeEditor && activeEditor.editor.command && activeEditor.editor.command(command)) return true;
    if (command === "source") {
      var el = document.querySelector('[data-block-id="' + CSS.escape(selectedBlockID || "") + '"]');
      return openBlock(el, true);
    }
    if (command.indexOf("study") === 0) {
      if (!closeEditor()) return false;
      var item = studyInsertions.find(function (s) { return s.id === selectedBlockID || (s.blockIDs || []).includes(selectedBlockID); });
      if (!item) return false;
      remember();
      if (command === "studyRemove") studyInsertions = studyInsertions.filter(function (s) { return s !== item; });
      if (command === "studyGrow") item.height += 80;
      if (command === "studyShrink") item.height = Math.max(44, item.height - 80);
      if (command === "studyUp" || command === "studyDown") {
        var at = sourceBlocks.findIndex(function (b) { return b.id === item.afterBlockID; });
        var next = at + (command === "studyUp" ? -1 : 1);
        item.afterBlockID = next < 0 ? null : sourceBlocks[Math.min(next, sourceBlocks.length - 1)].id;
      }
      draw();
      post("studyInsertionsChanged", studyInsertions);
      announceEdit();
      return true;
    }
    if (command === "undo" || command === "redo") {
      if (!closeEditor()) return false;
      var from = command === "undo" ? documentUndo : documentRedo;
      var to = command === "undo" ? documentRedo : documentUndo;
      if (!from.length) return false;
      to.push(sourceState());
      var state = from.pop();
      source = state.markdown;
      studyInsertions = state.studies;
      indexSource(source, state.ids);
      draw();
      post("studyInsertionsChanged", studyInsertions);
      announceEdit();
      return true;
    }
    if (command === "newParagraph") {
      if (!closeEditor()) return false;
      remember();
      source += (source.endsWith("\n\n") || !source ? "" : "\n\n") + "\n";
      var id = crypto.randomUUID();
      sourceBlocks.push({ id: id, start: source.length, end: source.length, line: source.split("\n").length - 1 });
      var paragraph = document.createElement("p");
      paragraph.dataset.blockId = id;
      document.getElementById("content").appendChild(paragraph);
      var opened = openBlock(paragraph);
      if (opened) activeEditor.remembered = true;
      return opened;
    }
    return false;
  }

  function clearSearchPaint() {
    if (window.CSS && CSS.highlights) {
      CSS.highlights.delete("document-search");
      CSS.highlights.delete("document-search-active");
    }
    var overlay = document.getElementById("document-search-overlay");
    if (overlay) overlay.remove();
  }

  function paintSearch() {
    clearSearchPaint();
    if (!searchRanges.length) return;
    if (window.CSS && CSS.highlights && window.Highlight) {
      var all = new Highlight();
      searchRanges.forEach(function (range) { all.add(range); });
      CSS.highlights.set("document-search", all);
      CSS.highlights.set("document-search-active", new Highlight(searchRanges[searchIndex]));
      return;
    }
    // iOS 17.0/17.1: a clipped, fixed paint layer never enters block identity
    // or document layout, unlike mark/span wrappers around the matched text.
    var overlay = document.createElement("div");
    overlay.id = "document-search-overlay";
    overlay.setAttribute("aria-hidden", "true");
    searchRanges.forEach(function (range, index) {
      Array.prototype.forEach.call(range.getClientRects(), function (rect) {
        if (!rect.width || !rect.height) return;
        var mark = document.createElement("span");
        mark.className = index === searchIndex ? "search-active" : "search-match";
        mark.style.cssText = "left:" + rect.left + "px;top:" + rect.top +
          "px;width:" + rect.width + "px;height:" + rect.height + "px";
        overlay.appendChild(mark);
      });
    });
    document.body.appendChild(overlay);
  }

  function searchResult() {
    var range = searchRanges[searchIndex];
    return { count: searchRanges.length, index: searchIndex,
      y: range ? range.getBoundingClientRect().top + (window.scrollY || 0) : null };
  }

  function search(query, index, revision) {
    if (revision < searchRevision) return searchResult();
    searchRevision = revision;
    searchQuery = query || "";
    searchRanges = [];
    if (searchQuery) {
      // Escaping gives literal matching while Unicode case folding preserves
      // the original UTF-16 offsets used by DOM Range (lowercasing may not).
      var pattern = new RegExp(searchQuery.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"), "giu");
      var root = document.getElementById("content");
      var walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT | NodeFilter.SHOW_ELEMENT);
      var groups = [], group = null, node;
      while ((node = walker.nextNode())) {
        if (node.nodeType === Node.ELEMENT_NODE) {
          if (node.tagName === "BR") group = null;
          continue;
        }
        if (node.parentElement.closest("script,style,.katex-mathml,[hidden]")) continue;
        var owner = node.parentElement.closest("p,li,td,th,pre,h1,h2,h3,h4,h5,h6,blockquote") || root;
        if (!group || group.owner !== owner) {
          group = { owner: owner, text: "", nodes: [] };
          groups.push(group);
        }
        group.nodes.push({ node: node, start: group.text.length });
        group.text += node.nodeValue;
      }
      groups.forEach(function (entry) {
        pattern.lastIndex = 0;
        var match;
        while ((match = pattern.exec(entry.text))) {
          var start = match.index, end = start + match[0].length;
          var first = entry.nodes.find(function (part) { return part.start + part.node.length > start; });
          var last = entry.nodes.find(function (part) { return part.start + part.node.length >= end; });
          var range = document.createRange();
          range.setStart(first.node, start - first.start);
          range.setEnd(last.node, end - last.start);
          if (range.getClientRects().length) searchRanges.push(range);
        }
      });
    }
    searchIndex = searchRanges.length ? ((index % searchRanges.length) + searchRanges.length) % searchRanges.length : 0;
    paintSearch();
    return searchResult();
  }

  // --- Hashing (must match Swift MDNoteCore.Hashing) ----------------------

  var FNV_OFFSET = 0xcbf29ce484222325n;
  var FNV_PRIME = 0x100000001b3n;
  var U64_MASK = 0xffffffffffffffffn;

  function fnv1a(str) {
    var hash = FNV_OFFSET;
    var bytes = new TextEncoder().encode(str); // UTF-8, matches String.utf8
    for (var i = 0; i < bytes.length; i++) {
      hash ^= BigInt(bytes[i]);
      hash = (hash * FNV_PRIME) & U64_MASK; // wrapping multiply like Swift &*
    }
    return hash.toString(16);
  }

  // Collapse [space tab nl cr] runs to one space + trim (matches Swift).
  function normalize(text) {
    return text.split(/[ \t\n\r]+/).filter(Boolean).join(" ");
  }

  function blockHash(text) {
    return fnv1a(normalize(text));
  }

  // --- markdown-it --------------------------------------------------------

  var md = window.markdownit({
    html: false,        // ignore raw HTML for safety in v1
    linkify: true,
    typographer: true,
    breaks: false,
  });

  // Annotate top-level block tokens with their source line range.
  md.core.ruler.push("inject_line_numbers", function (state) {
    state.tokens.forEach(function (token) {
      if (token.map && token.level === 0 && token.nesting >= 0) {
        token.attrSet("data-source-line", String(token.map[0]));
        token.attrSet("data-source-line-end", String(token.map[1]));
      }
    });
  });

  // --- Rendering + block tagging -----------------------------------------

  // Identity text for a block. textContent alone makes every image-only block
  // (and hr) hash identically — annotated images would swap ink when reordered.
  // Mix in each image's alt + src so distinct images get distinct identities.
  function blockIdentityText(el) {
    var text = el.textContent || "";
    var imgs = el.querySelectorAll("img");
    for (var i = 0; i < imgs.length; i++) {
      text += " img:" + (imgs[i].getAttribute("alt") || "") +
              " " + (imgs[i].getAttribute("src") || "");
    }
    return text;
  }

  function tagBlocks(root) {
    var els = root.querySelectorAll("[data-source-line]");
    var seqCounts = {};
    els.forEach(function (el) {
      var h = blockHash(blockIdentityText(el));
      var seq = seqCounts[h] || 0;
      seqCounts[h] = seq + 1;
      el.setAttribute("data-block-hash", h);
      el.setAttribute("data-block-seq", String(seq));
      // Freeze the plain source text BEFORE KaTeX/highlight mutate the DOM, so
      // layout().text stays the string the hash (and the legacy hash) was built
      // from — math blocks otherwise report rendered-glyph soup and detach ink
      // on a future hashing-scheme migration.
      el.setAttribute("data-block-text", el.textContent || "");
    });
  }

  // --- Late layout shifts (images / web fonts) -----------------------------

  // Images and KaTeX webfonts finish loading after render() has returned, and
  // the native side has already measured geometry by then. Tell it to
  // re-measure (debounced — several images can land in a burst).
  var layoutNotifyTimer = null;
  function scheduleLayoutNotify() {
    if (layoutNotifyTimer) clearTimeout(layoutNotifyTimer);
    layoutNotifyTimer = setTimeout(function () {
      layoutNotifyTimer = null;
      try {
        window.webkit.messageHandlers.layoutChanged.postMessage(1);
      } catch (e) { /* not running inside the app */ }
    }, 150);
  }

  function watchImages(root) {
    root.querySelectorAll("img").forEach(function (img) {
      if (img.complete) return;
      img.addEventListener("load", scheduleLayoutNotify);
      img.addEventListener("error", scheduleLayoutNotify);
    });
  }

  if (document.fonts && document.fonts.addEventListener) {
    document.fonts.addEventListener("loadingdone", scheduleLayoutNotify);
  }

  // Syntax-highlight code blocks. Runs after tagBlocks; highlighting only
  // rewrites innerHTML (textContent + data-* attributes are preserved), so block
  // identity and geometry stay valid.
  function highlightCode(root) {
    if (!window.hljs) return;
    root.querySelectorAll("pre code").forEach(function (el) {
      try {
        window.hljs.highlightElement(el);
        // Surface the detected language as a badge (CSS ::before). hljs only
        // adds a language-* class when it is confident, so the badge appears
        // only for identified languages. textContent is untouched.
        var lang = (el.className.match(/language-([\w+#-]+)/) || [])[1];
        if (lang) { var pre = el.closest("pre"); if (pre) pre.setAttribute("data-lang", lang); }
      } catch (e) { /* unknown lang */ }
    });
  }

  // GFM task lists: turn "[ ] / [x]" list items into checkboxes.
  function transformChecklists(root) {
    var re = /^(\s*(?:<p>\s*)?)\[( |x|X)\]\s+/;
    root.querySelectorAll("li").forEach(function (li) {
      var m = li.innerHTML.match(re);
      if (!m) return;
      li.classList.add("task-list-item");
      var checked = m[2].toLowerCase() === "x" ? " checked" : "";
      li.innerHTML = li.innerHTML.replace(re, m[1] + '<input type="checkbox" disabled' + checked + "> ");
    });
  }

  // LaTeX math via KaTeX auto-render. Runs after block hashing so identities
  // stay tied to the math source, not the rendered output.
  function renderMath(root) {
    if (!window.renderMathInElement) return;
    try {
      window.renderMathInElement(root, {
        delimiters: [
          { left: "$$", right: "$$", display: true },
          { left: "\\[", right: "\\]", display: true },
          { left: "$", right: "$", display: false },
          { left: "\\(", right: "\\)", display: false }
        ],
        throwOnError: false
      });
    } catch (e) { /* ignore */ }
  }

  // Resolve relative <img> sources against the document's folder, served by the
  // native side through the mdasset:// scheme.
  function rewriteImages(root) {
    root.querySelectorAll("img").forEach(function (img) {
      var src = img.getAttribute("src") || "";
      if (!src) return;
      // leave absolute (scheme:), protocol-relative (//), and root-absolute (/)
      if (/^[a-z][a-z0-9+.-]*:/i.test(src) || src.indexOf("//") === 0 || src.charAt(0) === "/") return;
      var clean = src.replace(/^\.\//, "");
      var encoded = clean.split("/").map(encodeURIComponent).join("/");
      img.setAttribute("src", "mdasset://local/" + encoded);
    });
  }

  // Strip a leading YAML front-matter fence so Obsidian/Jekyll/Hugo metadata
  // doesn't render as a stray <hr> + bogus heading at the top of the note.
  // Guarded tightly: the body must be non-empty and contain no blank line, so a
  // real `---` thematic break with prose under it is never eaten. Render-only —
  // never replicated into Swift documentHash, so change-detection is untouched.
  function stripFrontMatter(src) {
    var m = /^﻿?---[ \t]*\r?\n((?:[^\n]*\r?\n)*?)(?:---|\.\.\.)[ \t]*(?:\r?\n|$)/.exec(src);
    if (!m) return src;
    var body = m[1];
    if (!body.trim()) return src;                 // empty fence -> not front matter
    if (/\n[ \t]*\r?\n/.test(body)) return src;   // genuine INTERIOR blank line -> two real rules
    return src.slice(m[0].length);
  }

  // GitHub/Notion callouts: `> [!NOTE]` etc. Runs AFTER tagBlocks so the block
  // hash is still taken over the original "[!NOTE]" text (ink stays anchored);
  // the visible label is drawn by CSS ::before, never injected as text.
  function transformCallouts(root) {
    root.querySelectorAll("blockquote").forEach(function (bq) {
      var first = bq.querySelector("p");
      if (!first) return;
      var m = first.innerHTML.match(/^\s*\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]\s*(?:<br\s*\/?>)?\s*/i);
      if (!m) return;
      bq.classList.add("callout", "callout-" + m[1].toLowerCase());
      first.innerHTML = first.innerHTML.replace(/^\s*\[!\w+\]\s*(?:<br\s*\/?>)?\s*/i, "");
      if (!first.innerHTML.trim()) first.remove();
    });
  }

  function render(markdown, identities, documentUnchanged) {
    if (activeEditor && !closeEditor()) throw new Error("composition-in-progress");
    source = markdown || "";
    documentUndo = [];
    documentRedo = [];
    historyIDs = new Map();
    indexSource(source, documentUnchanged ? identities : []);
    var result = draw();
    if (!documentUnchanged && identities && identities.length) {
      var els = Array.from(document.querySelectorAll("#content > [data-block-id]"));
      els.forEach(function (el) {
        var matches = identities.filter(function (b) { return b.hash === el.dataset.blockHash && b.text === el.dataset.blockText; });
        var duplicates = els.filter(function (other) { return other.dataset.blockHash === el.dataset.blockHash && other.dataset.blockText === el.dataset.blockText; });
        if (matches.length === 1 && duplicates.length === 1 && matches[0].blockID) {
          var block = sourceBlocks.find(function (b) { return b.id === el.dataset.blockId; });
          if (block) block.id = matches[0].blockID;
          el.dataset.blockId = matches[0].blockID;
        }
      });
    }
    announcedText = new Map();
    document.querySelectorAll("#content [data-block-id]").forEach(function (el) { announcedText.set(el.dataset.blockId, el.textContent || ""); });
    return result;
  }

  function draw() {
    clearSearchPaint();
    var root = document.getElementById("content");
    root.innerHTML = md.render(stripFrontMatter(source));
    rewriteImages(root);
    transformChecklists(root);
    tagBlocks(root);
    bindBlockIDs(root);
    transformCallouts(root);
    highlightCode(root);
    renderMath(root);
    watchImages(root);
    applyStudies();
    document.body.className = "paper-" + paperStyle;
    document.documentElement.style.setProperty("--text-scale", String(textScale));
    search(searchQuery, searchIndex, searchRevision);
    return root.querySelectorAll("[data-source-line]").length;
  }

  // --- Geometry for native anchoring -------------------------------------

  // Returns blocks in document coordinates. The web layer is never scrolled
  // (the native outer scroll view owns scrolling), so getBoundingClientRect is
  // already in document space; we still add scroll offset defensively.
  function layout() {
    if (window.MDNoteAnnotationLayout) return window.MDNoteAnnotationLayout.snapshot(document.getElementById("content"));
    var els = document.querySelectorAll("#content [data-source-line]");
    var sx = window.scrollX || 0;
    var sy = window.scrollY || 0;
    var out = [];
    els.forEach(function (el) {
      var r = el.getBoundingClientRect();
      var lineEnd = el.getAttribute("data-source-line-end");
      out.push({
        blockID: el.getAttribute("data-block-id"),
        blockHash: el.getAttribute("data-block-hash"),
        blockSeq: parseInt(el.getAttribute("data-block-seq"), 10),
        sourceLineStart: parseInt(el.getAttribute("data-source-line"), 10),
        sourceLineEnd: parseInt(lineEnd != null ? lineEnd : el.getAttribute("data-source-line"), 10),
        x: r.left + sx,
        y: r.top + sy,
        width: r.width,
        height: r.height,
        text: el.getAttribute("data-block-text") || el.textContent || "",
      });
    });
    return out;
  }

  function contentHeight() {
    return Math.ceil(document.documentElement.scrollHeight);
  }

  // Clickable link regions in document coordinates. One entry per client rect
  // (a wrapped link spans several). Only links the native side can actually
  // open are reported: in-page anchors have no heading ids to land on, and
  // relative paths have no handler (yet).
  function links() {
    var sx = window.scrollX || 0;
    var sy = window.scrollY || 0;
    var out = [];
    document.querySelectorAll("#content a[href]").forEach(function (a) {
      var href = a.getAttribute("href") || "";
      if (!/^(https?:|mailto:)/i.test(href)) return;
      Array.prototype.forEach.call(a.getClientRects(), function (r) {
        if (r.width === 0 || r.height === 0) return;
        out.push({ x: r.left + sx, y: r.top + sy, width: r.width, height: r.height, href: href });
      });
    });
    return out;
  }

  // Headings (h1–h3) for outline/TOC navigation.
  function outline() {
    var sy = window.scrollY || 0;
    var out = [];
    document.querySelectorAll("#content h1, #content h2, #content h3").forEach(function (el) {
      out.push({
        level: parseInt(el.tagName.charAt(1), 10),
        text: (el.textContent || "").trim(),
        y: el.getBoundingClientRect().top + sy,
      });
    });
    return out;
  }

  function setPaper(style) {
    paperStyle = style || "plain";
    if (document.body) { document.body.className = "paper-" + paperStyle; }
  }

  // Uniform reading text scale. Only font-size scales; the 1390/1080 page
  // geometry is fixed, so ink stays pixel-locked. Triggers a re-measure so the
  // native side re-anchors ink to the reflowed block frames.
  function setTextScale(s) {
    textScale = (typeof s === "number" && s > 0) ? s : 1;
    document.documentElement.style.setProperty("--text-scale", String(textScale));
    scheduleLayoutNotify();
  }

  // Word count + reading time over the rendered text. Counts CJK characters
  // individually and Latin runs as words (~250 units/min).
  function stats() {
    var t = (document.getElementById("content").textContent || "");
    var cjkRe = /[぀-ヿ㐀-䶿一-鿿가-힣]/g;
    var cjk = (t.match(cjkRe) || []).length;
    var latin = (t.replace(cjkRe, " ").trim().match(/[^\s]+/g) || []).length;
    var count = latin + cjk;
    return { words: count, minutes: Math.max(1, Math.round(count / 250)) };
  }

  function imageSources(markdown) {
    var sources = [];
    function visit(tokens) {
      tokens.forEach(function (token) {
        if (token.type === "image") {
          sources.push(token.attrGet("src") || "");
        } else if (token.children) {
          visit(token.children);
        }
      });
    }
    visit(md.parse(stripFrontMatter(markdown || ""), {}));
    return sources;
  }

  function applyStudies() {
    if (!window.MDNoteAnnotationLayout) return;
    var root = document.getElementById("content");
    var allocated = false;
    window.MDNoteAnnotationLayout.applyInsertions(root, studyInsertions, function (markdown, item) {
      var container = document.createElement("div");
      container.innerHTML = md.render(markdown);
      var entries = parseSource(markdown, item.blockIDs);
      if (!entries.length) {
        entries = [{ id: (item.blockIDs || [])[0] || crypto.randomUUID(), start: 0, end: markdown.length, line: 0 }];
        container.innerHTML = "<p><br></p>";
      }
      studyBlocks.set(item.id, entries);
      var ids = entries.map(function (b) { return b.id; });
      if (JSON.stringify(ids) !== JSON.stringify(item.blockIDs)) { item.blockIDs = ids; allocated = true; }
      Array.from(container.children).forEach(function (el, i) { if (entries[i]) el.dataset.blockId = entries[i].id; });
      return container.innerHTML;
    });
    root.querySelectorAll("[data-study-id]").forEach(function (el) {
      rewriteImages(el);
      tagBlocks(el);
      el.querySelectorAll("[data-block-id]").forEach(function (child) {
        if (!child.dataset.blockHash) { child.dataset.blockHash = blockHash(blockIdentityText(child)); child.dataset.blockSeq = "0"; }
      });
      el.dataset.blockHash = blockHash("study:" + el.dataset.studyId);
      el.dataset.blockSeq = "0";
      highlightCode(el);
      renderMath(el);
      watchImages(el);
    });
    if (allocated) post("studyInsertionsChanged", studyInsertions);
  }

  function setStudyInsertions(items, recordUndo) {
    if (recordUndo) { if (!closeEditor()) throw new Error("composition-in-progress"); remember(); }
    studyInsertions = items;
    applyStudies();
    if (recordUndo) { post("studyInsertionsChanged", studyInsertions); announceEdit(); }
    scheduleLayoutNotify();
  }

  function selectedTextAnchor() {
    var selection = window.getSelection();
    if (!selection || !selection.rangeCount) return selectedBlockID ?
      { blockID: selectedBlockID, startUTF16: 0, endUTF16: 0, quote: "", prefix: "", suffix: "" } : null;
    var range = selection.getRangeAt(0);
    var element = range.startContainer.nodeType === 1 ? range.startContainer : range.startContainer.parentElement;
    var block = element.closest("[data-block-id]");
    if (!block || !block.contains(range.endContainer)) return null;
    selectedBlockID = block.dataset.blockId;
    var before = document.createRange();
    before.selectNodeContents(block);
    before.setEnd(range.startContainer, range.startOffset);
    var start = before.toString().length, quote = range.toString(), text = block.textContent || "";
    return { blockID: selectedBlockID, startUTF16: start, endUTF16: start + quote.length,
      quote: quote, prefix: text.slice(Math.max(0, start - 32), start), suffix: text.slice(start + quote.length, start + quote.length + 32) };
  }

  function rangeGeometry(anchor) {
    if (!window.MDNoteAnnotationLayout) return null;
    return window.MDNoteAnnotationLayout.rangeGeometry(document.getElementById("content"), anchor);
  }

  document.getElementById("content").addEventListener?.("click", function (event) {
    var target = event.target.closest("[data-block-id]");
    if (!target) return;
    selectedBlockID = target.dataset.blockId;
    if (editing && !target.closest(".rich-editor-host,.source-editor") && !target.matches("[data-study-kind='blank']")) {
      event.preventDefault();
      openBlock(target);
    }
  });
  document.getElementById("content").addEventListener?.("keydown", function (event) {
    if (editing && event.key === "Enter" && !activeEditor) {
      event.preventDefault();
      openBlock(event.target.closest("[data-block-id]"));
    }
  });

  window.MDNote = {
    pageWidth: PAGE_WIDTH,
    render: render,
    layout: layout,
    contentHeight: contentHeight,
    links: links,
    outline: outline,
    blockHash: blockHash,
    normalize: normalize,
    setPaper: setPaper,
    setTextScale: setTextScale,
    stats: stats,
    search: search,
    imageSources: imageSources,
    setTextEditing: setTextEditing,
    editorCommand: editorCommand,
    flushEditor: flushEditor,
    setStudyInsertions: setStudyInsertions,
    selectedTextAnchor: selectedTextAnchor,
    rangeGeometry: rangeGeometry,
    renderFragment: function (markdown) { return md.render(markdown); },
  };

  setPaper(paperStyle);
})();
