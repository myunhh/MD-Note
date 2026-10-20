(function (host, factory) {
  "use strict";
  var api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  if (host) host.MDNoteAnnotationLayout = api;
})(typeof window === "undefined" ? null : window, function () {
  "use strict";

  function blocks(root) {
    return Array.from(root.querySelectorAll("[data-block-id], [data-source-line]"));
  }

  function findBlock(root, id) {
    var matches = blocks(root).filter(function (el) { return el.getAttribute("data-block-id") === id; });
    return { status: matches.length === 1 ? "attached" : matches.length ? "ambiguous" : "detached", element: matches[0] };
  }

  function frame(el, rect) {
    var win = el.ownerDocument.defaultView;
    return { x: rect.left + win.scrollX, y: rect.top + win.scrollY, width: rect.width, height: rect.height };
  }

  // Math rendering duplicates accessible/visual glyphs. Such blocks can carry
  // rigid ink, but source-character ranges cannot safely index those glyphs.
  function textMap(el) {
    var doc = el.ownerDocument;
    var walker = doc.createTreeWalker(el, 4);
    var nodes = [], text = "", node;
    while ((node = walker.nextNode())) {
      if (node.parentElement.closest("script,style,[hidden],[aria-hidden='true'],.katex-mathml")) continue;
      nodes.push({ node: node, start: text.length });
      text += node.nodeValue;
    }
    return { text: text, nodes: nodes, atomic: !!el.querySelector(".katex,math,img") };
  }

  function boundaries(text) {
    if (typeof Intl === "undefined" || !Intl.Segmenter) return null;
    var result = new Set([text.length]);
    for (var segment of new Intl.Segmenter(undefined, { granularity: "grapheme" }).segment(text)) result.add(segment.index);
    return result;
  }

  function resolveRange(text, anchor) {
    var edges = boundaries(text);
    if (!edges) return { status: "detached", reason: "grapheme-segmentation-unavailable" };
    var start = anchor.startUTF16, end = anchor.endUTF16;
    var valid = Number.isInteger(start) && Number.isInteger(end) && start >= 0 && end >= start &&
      end <= text.length && edges.has(start) && edges.has(end);
    if (valid && (!anchor.quote || text.slice(start, end) === anchor.quote)) {
      return { status: "attached", range: { startUTF16: start, endUTF16: end } };
    }
    if (!anchor.quote) return { status: "detached", reason: "invalid-range" };
    var found = [], offset = 0, at;
    while ((at = text.indexOf(anchor.quote, offset)) !== -1) {
      var until = at + anchor.quote.length;
      if (edges.has(at) && edges.has(until) &&
          (!anchor.prefix || text.slice(0, at).endsWith(anchor.prefix)) &&
          (!anchor.suffix || text.slice(until).startsWith(anchor.suffix))) found.push(at);
      offset = at + 1;
    }
    if (found.length !== 1) return { status: found.length ? "ambiguous" : "detached", reason: "quote-not-unique-or-deleted" };
    return { status: "attached", range: { startUTF16: found[0], endUTF16: found[0] + anchor.quote.length } };
  }

  function snapshot(root) {
    return blocks(root).map(function (el) {
      var map = textMap(el);
      return Object.assign({
        blockID: el.getAttribute("data-block-id"),
        blockHash: el.getAttribute("data-block-hash"),
        blockSeq: Number(el.getAttribute("data-block-seq") || 0),
        sourceLineStart: Number(el.getAttribute("data-source-line") || 0),
        sourceLineEnd: Number(el.getAttribute("data-source-line-end") || el.getAttribute("data-source-line") || 0),
        text: el.getAttribute("data-block-text") || map.text,
        rangeText: map.text,
        rangeStartUTF16: 0,
        rangeEndUTF16: map.text.length,
        rangeSupported: !map.atomic,
        studyID: el.closest("[data-study-id]") ? el.closest("[data-study-id]").getAttribute("data-study-id") : null
      }, frame(el, el.getBoundingClientRect()));
    });
  }

  function rangeGeometry(root, anchor) {
    if (!anchor || typeof anchor.blockID !== "string") return { status: "detached", reason: "missing-anchor", rects: [] };
    var match = findBlock(root, anchor.blockID);
    if (match.status !== "attached") return { status: match.status, reason: "block-not-unique-or-deleted", rects: [] };
    var map = textMap(match.element);
    if (map.atomic) return { status: "detached", reason: "atomic-content", rects: [] };
    var resolved = resolveRange(map.text, anchor);
    if (resolved.status !== "attached") return Object.assign(resolved, { rects: [] });
    var start = resolved.range.startUTF16, end = resolved.range.endUTF16;
    if (start === end) return Object.assign(resolved, { rects: [] });
    var first = map.nodes.find(function (part) { return part.start + part.node.length > start; });
    var last = map.nodes.find(function (part) { return part.start + part.node.length >= end; });
    var range = root.ownerDocument.createRange();
    range.setStart(first.node, start - first.start);
    range.setEnd(last.node, end - last.start);
    var rects = Array.from(range.getClientRects()).filter(function (r) { return r.width > 0 && r.height > 0; })
      .map(function (r) { return frame(match.element, r); });
    // Inline spans may produce duplicate rectangles. Merge only touching,
    // same-height fragments so bidirectional gaps are never painted over.
    rects.sort(function (a, b) { return a.y - b.y || a.x - b.x; });
    var merged = [];
    rects.forEach(function (r) {
      var prev = merged[merged.length - 1];
      if (prev && Math.abs(prev.y - r.y) < 0.5 && Math.abs(prev.height - r.height) < 0.5 && r.x <= prev.x + prev.width + 0.5) {
        prev.width = Math.max(prev.x + prev.width, r.x + r.width) - prev.x;
      } else merged.push(Object.assign({}, r));
    });
    return Object.assign(resolved, { rects: merged });
  }

  function project(root, annotation) {
    var anchor = annotation.anchor;
    if (annotation.behavior === "underline" || annotation.behavior === "highlight") {
      var geometry = rangeGeometry(root, anchor);
      return Object.assign({}, geometry, { behavior: annotation.behavior, fragments: geometry.rects.map(function (r) {
        return annotation.behavior === "underline" ?
          { x: r.x, y: r.y + r.height, width: r.width, height: 1 } : Object.assign({}, r);
      }) });
    }
    var target = anchor && findBlock(root, anchor.blockID);
    if (!target || target.status !== "attached") return { status: target ? target.status : "detached", reason: "block-not-unique-or-deleted" };
    if (anchor.quote) {
      var map = textMap(target.element);
      if (!map.atomic) {
        var resolution = resolveRange(map.text, anchor);
        if (resolution.status !== "attached") return resolution;
      }
    }
    var original = annotation.originalBounds;
    if (!original || !Number.isFinite(original.x) || !Number.isFinite(original.y)) return { status: "detached", reason: "missing-original-bounds" };
    var current = frame(target.element, target.element.getBoundingClientRect());
    var dx = current.x - original.x, dy = current.y - original.y;
    return { status: "attached", behavior: "rigid", dx: dx, dy: dy,
      points: (annotation.originalPoints || []).map(function (p) { return Object.assign({}, p, { x: p.x + dx, y: p.y + dy }); }) };
  }

  function identity(text) {
    // Full encoded content avoids hash collisions and is deterministic on reopen.
    return encodeURIComponent(text);
  }

  function applyInsertions(root, insertions, renderMarkdown) {
    var previous = Array.from(root.querySelectorAll("[data-study-id]"));
    var ids = new Set();
    insertions.forEach(function (item) {
      if (!item.id || ids.has(item.id)) throw new Error("Study insertion IDs must be nonempty and unique");
      if (!Number.isFinite(item.height) || item.height < 0) throw new Error("Study insertion height must be finite and nonnegative");
      if (item.kind !== "blank" && item.kind !== "markdown") throw new Error("Unsupported study insertion kind");
      if (item.kind === "markdown" && typeof renderMarkdown !== "function") throw new Error("Markdown renderer required");
      ids.add(item.id);
    });
    var prepared = insertions.slice().sort(function (a, b) { return (a.order || 0) - (b.order || 0); }).map(function (item) {
      var el = root.ownerDocument.createElement("section");
      el.setAttribute("data-study-id", item.id);
      el.setAttribute("data-block-id", item.id);
      el.setAttribute("data-study-kind", item.kind);
      el.style.display = "flow-root";
      el.style.minHeight = item.height + "px";
      if (item.kind === "markdown") {
        el.innerHTML = renderMarkdown(item.markdown || "", item);
        Array.from(el.children).forEach(function (child) {
          if (!child.hasAttribute("data-block-id")) child.setAttribute("data-block-id", item.id + "/content/" + identity(child.textContent + "|" + child.innerHTML));
        });
      }
      return { item: item, element: el };
    });
    previous.forEach(function (el) { el.remove(); });
    var tailByAnchor = new Map(), results = [];
    prepared.forEach(function (entry) {
      var item = entry.item, el = entry.element;
      var match = item.afterBlockID == null ? { status: "attached", element: null } : findBlock(root, item.afterBlockID);
      var target = tailByAnchor.get(item.afterBlockID) || match.element;
      var floating = item.placement === "floating";
      // Fixed placement uses viewport coordinates; snapshots add scroll once.
      if (floating && match.status === "attached" && match.element) {
        var r = match.element.getBoundingClientRect();
        el.style.position = "fixed";
        el.style.left = r.left + "px";
        el.style.top = r.bottom + "px";
        el.style.width = r.width + "px";
      }
      if (match.status !== "attached") root.appendChild(el);
      else if (target) target.after(el);
      else root.prepend(el);
      tailByAnchor.set(item.afterBlockID, el);
      el.setAttribute("data-anchor-status", match.status);
      results.push({ id: item.id, status: match.status, placement: floating ? "floating" : "flow" });
    });
    return results;
  }

  return { snapshot: snapshot, rangeGeometry: rangeGeometry, resolveRange: resolveRange, project: project, applyInsertions: applyInsertions };
});
