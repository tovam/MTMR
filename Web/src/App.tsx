import { useEffect, useState } from "preact/hooks";
import { addItem, cloneDocument, createID, createItem, moveItem } from "./model";
import type { Alignment, EditorTab, ItemConfig } from "./types";
import { Inspector } from "./components/Inspector";
import { Palette } from "./components/Palette";
import { TouchBarPreview } from "./components/TouchBarPreview";
import { WorkspacePanels } from "./components/WorkspacePanels";
import { useEditorState } from "./useEditorState";

function saveStateLabel(value: ReturnType<typeof useEditorState>["saveState"]): string {
  switch (value) {
    case "dirty": return "Brouillon";
    case "validating": return "Validation";
    case "saving": return "Enregistrement";
    case "saved": return "Synchronisé";
    case "conflict": return "Conflit";
    case "error": return "Invalide";
    default: return "Prêt";
  }
}

function useResponsiveCollapse() {
  const query = "(max-width: 820px)";
  const [collapsed, setCollapsed] = useState(() => typeof window !== "undefined" && window.matchMedia(query).matches);
  useEffect(() => {
    const media = window.matchMedia(query);
    const onChange = (event: MediaQueryListEvent) => setCollapsed(event.matches);
    media.addEventListener("change", onChange);
    return () => media.removeEventListener("change", onChange);
  }, []);
  return [collapsed, setCollapsed] as const;
}

export function App() {
  const editor = useEditorState();
  const [tab, setTab] = useState<EditorTab>("form");
  const [paletteCollapsed, setPaletteCollapsed] = useResponsiveCollapse();
  const [inspectorCollapsed, setInspectorCollapsed] = useResponsiveCollapse();

  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      const target = event.target as HTMLElement | null;
      const editable = target?.matches("input, textarea, select, [contenteditable=true], .cm-content");
      if (editable || !(event.metaKey || event.ctrlKey) || event.key.toLowerCase() !== "z") return;
      event.preventDefault();
      if (event.shiftKey) editor.redo();
      else editor.undo();
    };
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [editor.redo, editor.undo]);

  const add = (item: ItemConfig, align: Alignment, beforeID?: string) => {
    if (editor.formLocked) return;
    editor.commitDocument(addItem(editor.document, item, align, beforeID), "item.added");
    editor.select(item.id);
  };

  const addFromPalette = (type: string) => {
    if (editor.formLocked) return;
    add(createItem(type, editor.schema), "left");
  };

  const move = (id: string, align: Alignment, beforeID?: string) => {
    if (editor.formLocked) return;
    editor.commitDocument(moveItem(editor.document, id, align, beforeID), "item.moved");
    editor.select(id);
  };

  const replaceSelected = (item: ItemConfig) => {
    if (editor.formLocked) return;
    editor.updateDocument((draft) => {
      const index = draft.items.findIndex((candidate) => candidate.id === item.id);
      if (index >= 0) draft.items[index] = item;
    }, "item.changed");
  };

  const duplicateSelected = () => {
    if (!editor.selectedItem || editor.formLocked) return;
    const copy = cloneDocument({ formatVersion: 1, items: [editor.selectedItem] }).items[0];
    copy.id = createID(copy.type);
    if (typeof copy.editorName === "string" && copy.editorName) copy.editorName = `${copy.editorName} copie`;
    if (typeof copy.title === "string" && copy.title) copy.title = `${copy.title} copie`;
    const index = editor.document.items.findIndex((candidate) => candidate.id === editor.selectedItem?.id);
    const document = cloneDocument(editor.document);
    document.items.splice(index + 1, 0, copy);
    editor.commitDocument(document, "item.duplicated");
    editor.select(copy.id);
  };

  const selectFromList = (id: string) => {
    editor.select(id);
    setInspectorCollapsed(false);
  };

  const deleteSelected = () => {
    if (!editor.selectedItem || editor.formLocked) return;
    const index = editor.document.items.findIndex((candidate) => candidate.id === editor.selectedItem?.id);
    const document = cloneDocument(editor.document);
    document.items.splice(index, 1);
    editor.commitDocument(document, "item.deleted");
    editor.select(document.items[index]?.id ?? document.items[index - 1]?.id);
  };

  return (
    <div class="app-shell" data-testid="app-shell">
      <div class="app-header">
        <div class="brand-block">
          <div class="brand-mark" aria-hidden="true"><span /><span /><span /></div>
          <div>
            <strong>MMTMR</strong>
            <span>Éditeur de Touch Bar</span>
          </div>
        </div>
        <div class="header-path" title={editor.status.configPath}>
          <span class="path-label">Configuration</span>
          <code>{editor.status.configPath}</code>
        </div>
        <div class="header-actions">
          <span class={`connection-state connection-${editor.connection}`}>
            <i />{editor.connection === "connected" ? "Connecté" : editor.connection === "connecting" ? "Connexion…" : "Déconnecté"}
          </span>
          <span class="revision-chip">r{editor.revision}</span>
          <button class="icon-button" disabled={!editor.canUndo} onClick={editor.undo} title="Annuler (⌘Z)" aria-label="Annuler">↶</button>
          <button class="icon-button" disabled={!editor.canRedo} onClick={editor.redo} title="Rétablir (⇧⌘Z)" aria-label="Rétablir">↷</button>
          <button class="secondary-button compact-button" onClick={editor.reload}>Recharger</button>
          <button class="primary-button compact-button" onClick={editor.save} disabled={["saving", "validating"].includes(editor.saveState)}>
            Enregistrer
          </button>
        </div>
      </div>

      <TouchBarPreview
        document={editor.document}
        schema={editor.schema}
        selectedID={editor.selectedID}
        simulation={editor.simulation}
        runtimeSnapshot={editor.runtimeSnapshot}
        editingLocked={editor.formLocked}
        onSelect={editor.select}
        onMove={move}
        onAdd={add}
      />

      <div class="workspace">
        <Palette
          schema={editor.schema}
          collapsed={paletteCollapsed}
          editingLocked={editor.formLocked}
          onToggle={() => setPaletteCollapsed((value) => !value)}
          onAdd={addFromPalette}
        />

        <div class="workspace-center">
          <WorkspacePanels
            tab={tab}
            document={editor.document}
            source={editor.rawSource}
            diagnostics={editor.diagnostics}
            events={editor.events}
            simulation={editor.simulation}
            simulationDirect={editor.simulationDirect}
            simulationResult={editor.simulationResult}
            selectedItem={editor.selectedItem}
            saveState={editor.saveState}
            editingLocked={editor.formLocked}
            onTab={setTab}
            onSource={editor.setRawSource}
            onDocument={(document) => editor.commitDocument(document, "document.changed")}
            onSelectItem={selectFromList}
            onSimulation={editor.updateSimulation}
            onBeginSimulation={editor.beginSimulation}
            onResetSimulation={editor.resetSimulation}
            onSimulateAction={editor.simulateAction}
          />
        </div>

        <Inspector
          item={editor.selectedItem}
          itemPath={editor.selectedItem ? `$.items[${editor.document.items.findIndex((item) => item.id === editor.selectedItem?.id)}]` : undefined}
          schema={editor.schema}
          diagnostics={editor.diagnostics}
          editingLocked={editor.formLocked}
          collapsed={inspectorCollapsed}
          onToggle={() => setInspectorCollapsed((value) => !value)}
          onChange={replaceSelected}
          onDuplicate={duplicateSelected}
          onDelete={deleteSelected}
        />
      </div>

      <div class="status-bar">
        <div><span class={`status-light status-${editor.saveState}`} />{saveStateLabel(editor.saveState)}</div>
        <div class="status-summary">
          <span>{editor.document.items.length} élément{editor.document.items.length > 1 ? "s" : ""}</span>
          <span>{editor.diagnostics.filter((entry) => entry.severity === "error").length} erreur{editor.diagnostics.filter((entry) => entry.severity === "error").length > 1 ? "s" : ""}</span>
          <span>MMTMR {editor.status.version}</span>
          <span>127.0.0.1:{editor.status.port}</span>
        </div>
      </div>
    </div>
  );
}
