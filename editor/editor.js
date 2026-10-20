import { EditorState, TextSelection } from "prosemirror-state";
import { EditorView } from "prosemirror-view";
import { defaultMarkdownParser, defaultMarkdownSerializer, schema } from "prosemirror-markdown";
import { baseKeymap, toggleMark, setBlockType, wrapIn } from "prosemirror-commands";
import { history, undo, redo, undoDepth, redoDepth } from "prosemirror-history";
import { keymap } from "prosemirror-keymap";
import { wrapInList, splitListItem, liftListItem, sinkListItem } from "prosemirror-schema-list";

// These extensions have no CommonMark schema equivalent. They remain rendered,
// and can be deliberately edited as source without normalizing their syntax.
export function supports(source) {
  return !(/(^|\n)\s*\|.*\||(^|\n)\s*>?\s*\[!|(^|\n)\s*[-*+]\s+\[[ xX]\]|~~|\$|\\[([]|<\/?[A-Za-z]|\]\[[^\]]*\]|(^|\n)\s*\[[^\]]+\]:/m.test(source));
}

export function create(host, source, callbacks) {
  let composing = false;
  let changed = false;
  const doc = defaultMarkdownParser.parse(source);
  const commands = {
    bold: toggleMark(schema.marks.strong),
    italic: toggleMark(schema.marks.em),
    code: toggleMark(schema.marks.code),
    paragraph: setBlockType(schema.nodes.paragraph),
    heading: setBlockType(schema.nodes.heading, { level: 2 }),
    quote: wrapIn(schema.nodes.blockquote),
    bullet: wrapInList(schema.nodes.bullet_list),
    numbered: wrapInList(schema.nodes.ordered_list),
    undo, redo
  };
  const state = EditorState.create({
    doc,
    plugins: [history(), keymap({
      "Mod-z": (state, dispatch, editor) => undo(state, dispatch, editor) || callbacks.history("undo"),
      "Mod-Shift-z": (state, dispatch, editor) => redo(state, dispatch, editor) || callbacks.history("redo"),
      "Mod-y": (state, dispatch, editor) => redo(state, dispatch, editor) || callbacks.history("redo"),
      "Mod-b": commands.bold, "Mod-i": commands.italic,
      Enter: splitListItem(schema.nodes.list_item),
      Tab: sinkListItem(schema.nodes.list_item),
      "Shift-Tab": liftListItem(schema.nodes.list_item),
      Backspace: (state) => state.selection.empty && state.selection.from === 1 && callbacks.boundary(-1),
      Delete: (state) => state.selection.empty && state.selection.to === state.doc.content.size - 1 && callbacks.boundary(1),
      Escape: () => { if (!composing) callbacks.finish(); return true; }
    }), keymap(baseKeymap)]
  });
  const view = new EditorView(host, {
    state,
    attributes: { role: "textbox", "aria-multiline": "true", "aria-label": callbacks.label },
    transformPastedHTML(html) {
      const container = document.createElement("template");
      container.innerHTML = html;
      container.content.querySelectorAll("[href],[src]").forEach(element => {
        for (const attribute of ["href", "src"]) {
          const value = element.getAttribute(attribute);
          if (value && /^\s*(?:javascript|vbscript|data):/i.test(value)) element.removeAttribute(attribute);
        }
      });
      return container.innerHTML;
    },
    dispatchTransaction(transaction) {
      view.updateState(view.state.apply(transaction));
      changed ||= transaction.docChanged;
      callbacks.state(status());
      if (transaction.docChanged && !composing) callbacks.change(value(), {
        blockCount: view.state.doc.childCount,
        cursor: view.state.doc.textBetween(0, view.state.selection.from, "").length
      });
    },
    handleDOMEvents: {
      compositionstart() { composing = true; callbacks.state(status()); return false; },
      compositionend() {
        // ProseMirror commits the final DOM mutation before the next task.
        setTimeout(() => {
          if (view.isDestroyed) return;
          composing = false;
          callbacks.state(status());
          if (changed) callbacks.change(value());
        }, 0);
        return false;
      }
    }
  });
  function status() {
    return { composing, canUndo: undoDepth(view.state) > 0, canRedo: redoDepth(view.state) > 0 };
  }
  function value() {
    if (composing || view.composing) throw new Error("composition-in-progress");
    return changed && !view.state.doc.eq(doc) ? defaultMarkdownSerializer.serialize(view.state.doc) : source;
  }
  view.focus();
  if (callbacks.cursor != null) {
    view.dispatch(view.state.tr.setSelection(TextSelection.create(view.state.doc, Math.min(callbacks.cursor + 1, view.state.doc.content.size - 1))));
  }
  return {
    value,
    status,
    command(name) {
      if (composing || view.composing) return false;
      const command = commands[name];
      if (!command) return false;
      const handled = command(view.state, view.dispatch, view);
      view.focus();
      return handled;
    },
    destroy() { view.destroy(); },
    focus() { view.focus(); }
  };
}
