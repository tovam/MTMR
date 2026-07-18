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
          "&": { height: "100%", backgroundColor: "transparent" },
          ".cm-scroller": { overflow: "auto", fontFamily: "var(--font-mono)" },
          ".cm-content": { padding: "12px 0", caretColor: "#8bc5ff" },
          ".cm-gutters": { backgroundColor: "#101318", color: "#58606b", border: "none" },
          ".cm-activeLine": { backgroundColor: "rgba(92, 161, 255, .065)" },
          ".cm-activeLineGutter": { backgroundColor: "rgba(92, 161, 255, .08)", color: "#a9b2bd" },
          ".cm-selectionBackground, &.cm-focused .cm-selectionBackground": { backgroundColor: "#284c72" },
        }, { dark: true }),
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
