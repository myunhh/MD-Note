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

  function render(markdown) {
    var root = document.getElementById("content");
    root.innerHTML = md.render(stripFrontMatter(markdown || ""));
    rewriteImages(root);
    transformChecklists(root);
    tagBlocks(root);
    transformCallouts(root);
    highlightCode(root);
    renderMath(root);
    watchImages(root);
    document.body.className = "paper-" + paperStyle;
    document.documentElement.style.setProperty("--text-scale", String(textScale));
    return root.querySelectorAll("[data-source-line]").length;
  }

  // --- Geometry for native anchoring -------------------------------------

  // Returns blocks in document coordinates. The web layer is never scrolled
  // (the native outer scroll view owns scrolling), so getBoundingClientRect is
  // already in document space; we still add scroll offset defensively.
  function layout() {
    var els = document.querySelectorAll("#content [data-source-line]");
    var sx = window.scrollX || 0;
    var sy = window.scrollY || 0;
    var out = [];
    els.forEach(function (el) {
      var r = el.getBoundingClientRect();
      var lineEnd = el.getAttribute("data-source-line-end");
      out.push({
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
  };

  setPaper(paperStyle);
})();
