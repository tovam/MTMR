import { useRef, useState } from "preact/hooks";
import { schemaItemTypes } from "../model";
import type { PaletteItemPresentation } from "../model";
import type { JsonSchema } from "../types";

export const DRAG_TYPE = "application/x-mmtmr-item";

export type DragPayload =
  | { kind: "palette"; type: string }
  | { kind: "item"; id: string };

export function setDragPayload(event: DragEvent, payload: DragPayload) {
  if (!event.dataTransfer) return;
  const serialized = JSON.stringify(payload);
  event.dataTransfer.effectAllowed = payload.kind === "palette" ? "copy" : "move";
  event.dataTransfer.setData(DRAG_TYPE, serialized);
  event.dataTransfer.setData("text/plain", serialized);
}

export function getDragPayload(event: DragEvent): DragPayload | undefined {
  if (!event.dataTransfer) return undefined;
  const raw = event.dataTransfer.getData(DRAG_TYPE) || event.dataTransfer.getData("text/plain");
  try {
    const value = JSON.parse(raw) as DragPayload;
    return value.kind === "palette" || value.kind === "item" ? value : undefined;
  } catch {
    return undefined;
  }
}

interface PaletteProps {
  schema?: JsonSchema;
  collapsed: boolean;
  editingLocked?: boolean;
  onToggle(): void;
  onAdd(type: string): void;
}

export function Palette({ schema, collapsed, editingLocked = false, onToggle, onAdd }: PaletteProps) {
  const types = schemaItemTypes(schema);
  const asideRef = useRef<HTMLElement>(null);
  const [detail, setDetail] = useState<{ entry: PaletteItemPresentation; top: number }>();
  const showDetail = (entry: PaletteItemPresentation, target: HTMLElement) => {
    const aside = asideRef.current?.getBoundingClientRect();
    const rect = target.getBoundingClientRect();
    const naturalTop = rect.top - (aside?.top ?? 0) - 8;
    setDetail({ entry, top: Math.max(48, Math.min(naturalTop, (aside?.height ?? 500) - 188)) });
  };
  return (
    <aside
      ref={asideRef}
      class={`palette side-panel ${collapsed ? "is-collapsed" : ""}`}
      aria-label="Palette de composants"
      onMouseLeave={() => setDetail(undefined)}
    >
      <div class="panel-heading">
        {!collapsed && <><span>Composants</span><span class="count-pill">{types.length}</span></>}
        <button class="icon-button collapse-button" onClick={onToggle} aria-label={collapsed ? "Ouvrir la palette" : "Replier la palette"}>
          {collapsed ? "›" : "‹"}
        </button>
      </div>
      {!collapsed && (
        <div class="palette-scroll scroll-region" data-testid="palette-scroll">
          <p class="panel-hint">{editingLocked ? "Corrigez d’abord le brouillon JSON invalide." : "Glissez un composant dans la barre ou double-cliquez pour l’ajouter à gauche."}</p>
          <div class="palette-list">
            {types.map((entry) => (
              <button
                class="palette-item"
                key={entry.type}
                draggable={!editingLocked}
                disabled={editingLocked}
                onDragStart={(event) => setDragPayload(event, { kind: "palette", type: entry.type })}
                onDblClick={() => onAdd(entry.type)}
                onMouseEnter={(event) => showDetail(entry, event.currentTarget)}
                onFocus={(event) => showDetail(entry, event.currentTarget)}
                onBlur={() => setDetail(undefined)}
                title={`Ajouter ${entry.label}`}
                aria-describedby={`palette-help-${entry.type}`}
              >
                <span class="palette-icon" aria-hidden="true">{entry.icon}</span>
                <span>
                  <strong>{entry.label}</strong>
                  <small>{entry.type}</small>
                </span>
                <span class="drag-handle" aria-hidden="true">⠿</span>
              </button>
            ))}
          </div>
        </div>
      )}
      {!collapsed && detail && (
        <div
          class="palette-popover"
          id={`palette-help-${detail.entry.type}`}
          role="tooltip"
          style={{ top: `${detail.top}px` }}
        >
          <div class="palette-popover-heading">
            <span class="palette-popover-icon" aria-hidden="true">{detail.entry.icon}</span>
            <div><strong>{detail.entry.label}</strong><code>{detail.entry.type}</code></div>
          </div>
          <p>{detail.entry.description}</p>
          <div class="palette-examples" aria-label="Exemples">
            {detail.entry.examples.slice(0, 3).map((example) => <span key={example}>{example}</span>)}
          </div>
        </div>
      )}
    </aside>
  );
}
