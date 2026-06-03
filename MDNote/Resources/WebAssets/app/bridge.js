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

  var PAGE_WIDTH = 1700;
  var paperStyle = "plain";

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

  function tagBlocks(root) {
    var els = root.querySelectorAll("[data-source-line]");
    var seqCounts = {};
    els.forEach(function (el) {
      var text = el.textContent || "";
      var h = blockHash(text);
      var seq = seqCounts[h] || 0;
      seqCounts[h] = seq + 1;
      el.setAttribute("data-block-hash", h);
      el.setAttribute("data-block-seq", String(seq));
    });
  }

  // Syntax-highlight code blocks. Runs after tagBlocks; highlighting only
  // rewrites innerHTML (textContent + data-* attributes are preserved), so block
  // identity and geometry stay valid.
  function highlightCode(root) {
    if (!window.hljs) return;
    root.querySelectorAll("pre code").forEach(function (el) {
      try { window.hljs.highlightElement(el); } catch (e) { /* unknown lang */ }
    });
  }

  function render(markdown) {
    var root = document.getElementById("content");
    root.innerHTML = md.render(markdown || "");
    tagBlocks(root);
    highlightCode(root);
    document.body.className = "paper-" + paperStyle;
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
        text: el.textContent || "",
      });
    });
    return out;
  }

  function contentHeight() {
    return Math.ceil(document.documentElement.scrollHeight);
  }

  function setPaper(style) {
    paperStyle = style || "plain";
    if (document.body) { document.body.className = "paper-" + paperStyle; }
  }

  window.MDNote = {
    pageWidth: PAGE_WIDTH,
    render: render,
    layout: layout,
    contentHeight: contentHeight,
    blockHash: blockHash,
    normalize: normalize,
    setPaper: setPaper,
  };

  setPaper(paperStyle);
})();
