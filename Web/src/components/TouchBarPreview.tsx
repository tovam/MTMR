import { useEffect, useRef, useState } from "preact/hooks";
import { createItem, itemLabel, itemPresentation } from "../model";
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

function configuredImageDataURL(item: ItemConfig): string | undefined {
  const source = item.image;
  if (!source || typeof source !== "object" || Array.isArray(source)) return undefined;
  const base64 = source.base64;
  if (typeof base64 === "string" && base64.length > 0) return `data:image/png;base64,${base64}`;
  const inline = source.inline;
  if (typeof inline === "string" && inline.startsWith("data:image/")) return inline;
  if (typeof inline === "string" && inline.trimStart().startsWith("<svg")) {
    return `data:image/svg+xml;charset=utf-8,${encodeURIComponent(inline)}`;
  }
  return undefined;
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
  const kind = geometry?.kind ?? item.type;
  const presentation = itemPresentation(kind);
  const fallbackTitle = displayTitle(item, simulation);
  const displayedTitle = typeof geometry?.title === "string" ? geometry.title : fallbackTitle;
  const renderedImage = typeof geometry?.renderedImage === "string" && geometry.renderedImage.startsWith("data:image/")
    ? geometry.renderedImage
    : undefined;
  const configuredImage = renderedImage ? undefined : configuredImageDataURL(item);
  const showFallbackIcon = !renderedImage && !configuredImage && (
    displayedTitle.length === 0
    || !["staticButton", "appleScriptTitledButton", "shellScriptTitledButton", "timeButton"].includes(kind)
  );
  const sizeStyle = {
    ...(typeof geometry?.width === "number"
      ? { width: `${Math.max(18, geometry.width)}px` }
      : typeof item.width === "number" ? { width: `${Math.max(18, item.width)}px` } : {}),
    ...(typeof geometry?.height === "number" ? { height: `${Math.max(18, geometry.height)}px` } : {}),
  };
  return (
    <button
      class={`touch-item ${renderedImage ? "has-native-render" : ""} ${selected ? "is-selected" : ""} ${item.enabled === false ? "is-disabled" : ""}`}
      style={sizeStyle}
      data-kind={kind}
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
      aria-label={displayedTitle || presentation.label}
      title={`${itemLabel(item)} · ${item.type}`}
    >
      {renderedImage ? (
        <img class="touch-item-image touch-item-complete-render" src={renderedImage} alt="" aria-hidden="true" />
      ) : (
        <>
          {configuredImage && <img class="touch-item-image touch-item-config-image" src={configuredImage} alt="" aria-hidden="true" />}
          {showFallbackIcon && <span class="touch-item-symbol" aria-hidden="true">{presentation.icon}</span>}
          {displayedTitle && <span class="touch-item-label">{displayedTitle}</span>}
        </>
      )}
    </button>
  );
}

export function TouchBarPreview(props: TouchBarPreviewProps) {
  const fitRef = useRef<HTMLDivElement>(null);
  const trackRef = useRef<HTMLDivElement>(null);
  const [scale, setScale] = useState(1);
  const snapshotContext = props.runtimeSnapshot?.context;
  const runtimeInputAccess = snapshotContext && typeof snapshotContext === "object" && !Array.isArray(snapshotContext)
    && typeof snapshotContext.inputAccess === "boolean"
    ? snapshotContext.inputAccess
    : props.simulation.inputAccess;
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
      height: typeof record.height === "number" ? record.height : typeof frame?.height === "number" ? frame.height : undefined,
      align: ["left", "center", "right"].includes(String(record.align)) ? record.align as Alignment : undefined,
      visible: typeof record.visible === "boolean" ? record.visible : undefined,
      title: typeof record.title === "string" ? record.title : undefined,
      renderedImage: typeof record.renderedImage === "string" ? record.renderedImage : undefined,
      kind: typeof record.kind === "string" ? record.kind : undefined,
    });
  });

  useEffect(() => {
    const fit = fitRef.current;
    const track = trackRef.current;
    if (!fit || !track) return;
    const measure = () => {
      const available = fit.clientWidth;
      const natural = track.scrollWidth;
      const availableHeight = fit.clientHeight;
      const naturalHeight = track.scrollHeight;
      setScale(available > 0 && natural > 0 && availableHeight > 0 && naturalHeight > 0
        ? Math.min(1, available / natural, availableHeight / naturalHeight)
        : 1);
    };
    measure();
    const observer = typeof ResizeObserver === "undefined" ? undefined : new ResizeObserver(measure);
    observer?.observe(fit);
    observer?.observe(track);
    return () => observer?.disconnect();
  }, [props.document, props.runtimeSnapshot]);
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
          <span class="preview-safety">Cliquer sélectionne l’élément : aucune action n’est envoyée au Mac.</span>
        </div>
        <div class="preview-meta">
          {runtimeInputAccess === false && (
            <span class="input-access-warning" role="alert">
              Autorisez MMTMR dans Réglages &gt; Accessibilité pour les lettres, volume et luminosité.
            </span>
          )}
          <div class="preview-context">
            <span>{props.simulation.application}</span>
            <span>{props.simulation.battery}%</span>
            <span>{props.simulation.theme === "light" ? "Clair" : "Sombre"}</span>
            <span class={props.simulation.networkConnected ? "online" : "offline"}>
              {props.simulation.networkConnected ? "En ligne" : "Hors ligne"}
            </span>
          </div>
        </div>
      </div>
      <div class="preview-scroll" data-testid="preview-scroll" data-fit-scale={scale.toFixed(3)}>
        <div class="touchbar-frame">
          <div class="touchbar-fit" ref={fitRef}>
            <div class="touchbar-track" ref={trackRef} style={{ transform: `scale(${scale})` }}>
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
        </div>
      </div>
    </section>
  );
}
