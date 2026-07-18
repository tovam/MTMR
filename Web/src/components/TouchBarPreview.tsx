import { createItem, itemLabel } from "../model";
import type {
  Alignment,
  ConfigDocument,
  ItemConfig,
  JsonObject,
  JsonSchema,
  RuntimeItemGeometry,
  SimulationContext,
} from "../types";
import { getDragPayload, setDragPayload } from "./Palette";

interface TouchBarPreviewProps {
  document: ConfigDocument;
  schema?: JsonSchema;
  selectedID?: string;
  simulation: SimulationContext;
  runtimeSnapshot?: JsonObject;
  editingLocked?: boolean;
  onSelect(id: string): void;
  onMove(id: string, align: Alignment, beforeID?: string): void;
  onAdd(item: ItemConfig, align: Alignment, beforeID?: string): void;
}

function dropHandler(
  event: DragEvent,
  align: Alignment,
  schema: JsonSchema | undefined,
  onMove: TouchBarPreviewProps["onMove"],
  onAdd: TouchBarPreviewProps["onAdd"],
  editingLocked = false,
  beforeID?: string,
) {
  if (editingLocked) return;
  event.preventDefault();
  event.stopPropagation();
  const payload = getDragPayload(event);
  if (!payload) return;
  if (payload.kind === "item") onMove(payload.id, align, beforeID);
  else onAdd(createItem(payload.type, schema), align, beforeID);
}

function displayTitle(item: ItemConfig, simulation: SimulationContext): string {
  if (item.type === "timeButton") return simulation.time;
  if (item.type === "battery") return `${simulation.battery}%`;
  if (item.type === "inputsource") return "ABC";
  if (item.type === "music") return "♫ Lecture";
  return itemLabel(item);
}

function PreviewItem({
  item,
  align,
  schema,
  selected,
  simulation,
  geometry,
  onSelect,
  onMove,
  onAdd,
  editingLocked,
}: {
  item: ItemConfig;
  align: Alignment;
  schema?: JsonSchema;
  selected: boolean;
  simulation: SimulationContext;
  geometry?: RuntimeItemGeometry;
  onSelect(id: string): void;
  onMove: TouchBarPreviewProps["onMove"];
  onAdd: TouchBarPreviewProps["onAdd"];
  editingLocked: boolean;
}) {
  return (
    <button
      class={`touch-item ${selected ? "is-selected" : ""} ${item.enabled === false ? "is-disabled" : ""}`}
      style={typeof geometry?.width === "number"
        ? { width: `${Math.max(18, geometry.width)}px` }
        : typeof item.width === "number" ? { width: `${Math.max(18, item.width)}px` } : undefined}
      draggable={!editingLocked}
      onDragStart={(event) => {
        if (editingLocked) {
          event.preventDefault();
          return;
        }
        setDragPayload(event, { kind: "item", id: item.id });
      }}
      onDragOver={(event) => {
        event.preventDefault();
        if (event.dataTransfer) event.dataTransfer.dropEffect = "move";
      }}
      onDrop={(event) => dropHandler(event, align, schema, onMove, onAdd, editingLocked, item.id)}
      onClick={() => onSelect(item.id)}
      aria-pressed={selected}
      title={`${itemLabel(item)} · ${item.type}`}
    >
      {displayTitle(item, simulation)}
    </button>
  );
}

export function TouchBarPreview(props: TouchBarPreviewProps) {
  const rawGeometry = Array.isArray(props.runtimeSnapshot?.items)
    ? props.runtimeSnapshot.items
    : Array.isArray(props.runtimeSnapshot?.geometry) ? props.runtimeSnapshot.geometry : [];
  const geometries = new Map<string, RuntimeItemGeometry>();
  rawGeometry.forEach((candidate) => {
    if (!candidate || typeof candidate !== "object" || Array.isArray(candidate)) return;
    const record = candidate as JsonObject;
    const id = record.id ?? record.itemID ?? record.identifier;
    if (typeof id !== "string") return;
    const frame = record.frame && typeof record.frame === "object" && !Array.isArray(record.frame) ? record.frame as JsonObject : undefined;
    geometries.set(id, {
      id,
      x: typeof record.x === "number" ? record.x : typeof frame?.x === "number" ? frame.x : undefined,
      width: typeof record.width === "number" ? record.width : typeof frame?.width === "number" ? frame.width : undefined,
      align: ["left", "center", "right"].includes(String(record.align)) ? record.align as Alignment : undefined,
      visible: typeof record.visible === "boolean" ? record.visible : undefined,
    });
  });
  const byAlignment = (align: Alignment) => props.document.items
    .filter((item) => geometries.get(item.id)?.visible !== false && (geometries.get(item.id)?.align ?? item.align ?? "left") === align)
    .sort((left, right) => {
      const leftX = geometries.get(left.id)?.x;
      const rightX = geometries.get(right.id)?.x;
      return typeof leftX === "number" && typeof rightX === "number" ? leftX - rightX : 0;
    });
  return (
    <section class={`preview-shell preview-theme-${props.simulation.theme}`} data-theme={props.simulation.theme} aria-label="Aperçu de la Touch Bar">
      <div class="section-title-row">
        <div>
          <span class="eyebrow">Aperçu en direct</span>
          <span class="section-subtitle">{geometries.size > 0 ? "Géométrie native synchronisée" : "Disposition logique · en attente de la géométrie native"}</span>
        </div>
        <div class="preview-context">
          <span>{props.simulation.application}</span>
          <span>{props.simulation.battery}%</span>
          <span>{props.simulation.theme === "light" ? "Clair" : "Sombre"}</span>
          <span class={props.simulation.networkConnected ? "online" : "offline"}>
            {props.simulation.networkConnected ? "En ligne" : "Hors ligne"}
          </span>
        </div>
      </div>
      <div class="preview-scroll" data-testid="preview-scroll">
        <div class="touchbar-frame">
          {(["left", "center", "right"] as Alignment[]).map((align) => (
            <div
              class={`drop-zone drop-zone-${align}`}
              data-testid={`drop-${align}`}
              data-align={align}
              key={align}
              onDragOver={(event) => {
                if (props.editingLocked) return;
                event.preventDefault();
                if (event.dataTransfer) event.dataTransfer.dropEffect = "move";
                event.currentTarget.classList.add("drag-over");
              }}
              onDragLeave={(event) => event.currentTarget.classList.remove("drag-over")}
              onDrop={(event) => {
                event.currentTarget.classList.remove("drag-over");
                dropHandler(event, align, props.schema, props.onMove, props.onAdd, props.editingLocked);
              }}
            >
              {byAlignment(align).length === 0 && <span class="drop-placeholder">{align}</span>}
              {byAlignment(align).map((item) => (
                <PreviewItem
                  key={item.id}
                  item={item}
                  align={align}
                  schema={props.schema}
                  selected={props.selectedID === item.id}
                  simulation={props.simulation}
                  geometry={geometries.get(item.id)}
                  onSelect={props.onSelect}
                  onMove={props.onMove}
                  onAdd={props.onAdd}
                  editingLocked={props.editingLocked ?? false}
                />
              ))}
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
