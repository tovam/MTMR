import { defaultKeymap, history, historyKeymap, indentWithTab } from "@codemirror/commands";
import { json } from "@codemirror/lang-json";
import { EditorState } from "@codemirror/state";
import {
  EditorView,
  drawSelection,
  dropCursor,
  highlightActiveLine,
  highlightActiveLineGutter,
  keymap,
  lineNumbers,
} from "@codemirror/view";
import { useEffect, useLayoutEffect, useRef } from "preact/hooks";

interface CodeEditorProps {
  value: string;
  onChange(value: string): void;
  label?: string;
}

export function CodeEditor({ value, onChange, label = "Configuration JSON" }: CodeEditorProps) {
  const host = useRef<HTMLDivElement>(null);
  const view = useRef<EditorView>();
  const onChangeRef = useRef(onChange);
  const externalUpdate = useRef(false);

  useEffect(() => { onChangeRef.current = onChange; }, [onChange]);

  useLayoutEffect(() => {
    if (!host.current) return;
    const state = EditorState.create({
      doc: value,
      extensions: [
        lineNumbers(),
        highlightActiveLineGutter(),
        history(),
        drawSelection(),
        dropCursor(),
        highlightActiveLine(),
        keymap.of([indentWithTab, ...defaultKeymap, ...historyKeymap]),
        json(),
        EditorView.lineWrapping,
        EditorView.contentAttributes.of({ "aria-label": label, spellcheck: "false" }),
        EditorView.updateListener.of((update) => {
          if (update.docChanged && !externalUpdate.current) {
            onChangeRef.current(update.state.doc.toString());
          }
        }),
        EditorView.theme({
          "&": { height: "100%", color: "#20262b", backgroundColor: "#ffffff" },
          ".cm-scroller": { overflow: "auto", fontFamily: "var(--font-mono)" },
          ".cm-content": { padding: "12px 0", caretColor: "#0a64bd" },
          ".cm-gutters": { backgroundColor: "#f1f3f4", color: "#747e86", borderRight: "1px solid #dde1e4" },
          ".cm-activeLine": { backgroundColor: "rgba(10, 100, 189, .065)" },
          ".cm-activeLineGutter": { backgroundColor: "#d5e5f4", color: "#39434b" },
          ".cm-selectionBackground, &.cm-focused .cm-selectionBackground": { backgroundColor: "#b8d6f2" },
        }, { dark: false }),
      ],
    });
    view.current = new EditorView({ state, parent: host.current });
    return () => {
      view.current?.destroy();
      view.current = undefined;
    };
  }, [label]);

  useEffect(() => {
    const editor = view.current;
    if (!editor || editor.state.doc.toString() === value) return;
    externalUpdate.current = true;
    editor.dispatch({ changes: { from: 0, to: editor.state.doc.length, insert: value } });
    externalUpdate.current = false;
  }, [value]);

  return <div class="code-editor" ref={host} data-testid="json-editor" />;
}
