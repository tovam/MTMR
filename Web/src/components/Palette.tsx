import { schemaItemTypes } from "../model";
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
  return (
    <aside class={`palette side-panel ${collapsed ? "is-collapsed" : ""}`} aria-label="Palette de composants">
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
                title={`Ajouter ${entry.label}`}
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
    </aside>
  );
}
