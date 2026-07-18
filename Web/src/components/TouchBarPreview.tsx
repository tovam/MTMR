import { Fragment } from "preact";
import { useEffect, useLayoutEffect, useRef, useState } from "preact/hooks";
import { createItem, itemLabel, itemPresentation } from "../model";
import { computeTouchBarZoneFrames, type TouchBarZoneFrames } from "../touchBarLayout";
import type {
  Alignment,
  ConfigDocument,
  ItemConfig,
  JsonObject,
  JsonSchema,
  RuntimeItemGeometry,
  SimulationContext,
} from "../types";
import { clearDragPayload, getDragPayload, setDragPayload } from "./Palette";
import { ItemTypeIcon } from "./MediaControlIcon";

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
  onMoveIntoGroup(id: string, groupID: string): void;
  onAddIntoGroup(type: string, groupID: string): void;
}

interface DropIndicatorTarget {
  align: Alignment;
  beforeID?: string;
  draggedItemID?: string;
  previewWidth: number;
}

interface ZoneOverflow {
  leading: boolean;
  trailing: boolean;
}

const DEFAULT_DROP_PREVIEW_WIDTH = 64;

function insertionTarget(
  zone: HTMLDivElement,
  clientX: number,
  draggedItemID?: string,
): string | undefined {
  const items = Array.from(zone.children).filter((child): child is HTMLElement => (
    child instanceof HTMLElement
    && child.classList.contains("touch-item")
    && child.dataset.itemId !== draggedItemID
  ));

  for (const item of items) {
    const bounds = item.getBoundingClientRect();
    if (clientX < bounds.left + bounds.width / 2) return item.dataset.itemId;
  }
  return undefined;
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
  clearDragPayload();
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
  selected,
  simulation,
  geometry,
  onSelect,
  onMoveIntoGroup,
  onAddIntoGroup,
  onClearBarDropTarget,
  editingLocked,
  previewScale,
}: {
  item: ItemConfig;
  selected: boolean;
  simulation: SimulationContext;
  geometry?: RuntimeItemGeometry;
  onSelect(id: string): void;
  onMoveIntoGroup(id: string, groupID: string): void;
  onAddIntoGroup(type: string, groupID: string): void;
  onClearBarDropTarget(): void;
  editingLocked: boolean;
  previewScale: number;
}) {
  const [groupDropActive, setGroupDropActive] = useState(false);
  const kind = geometry?.kind ?? item.type;
  useEffect(() => {
    if (kind !== "group") return;
    const clear = () => setGroupDropActive(false);
    window.addEventListener("dragend", clear);
    window.addEventListener("drop", clear);
    return () => {
      window.removeEventListener("dragend", clear);
      window.removeEventListener("drop", clear);
    };
  }, [kind]);
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
      class={`touch-item ${renderedImage ? "has-native-render" : ""} ${selected ? "is-selected" : ""} ${item.enabled === false ? "is-disabled" : ""} ${groupDropActive ? "group-drop-active" : ""}`}
      style={sizeStyle}
      data-kind={kind}
      data-item-id={item.id}
      draggable={!editingLocked}
      onDragStart={(event) => {
        if (editingLocked) {
          event.preventDefault();
          return;
        }
        const renderedWidth = event.currentTarget.getBoundingClientRect().width;
        const width = event.currentTarget.offsetWidth || renderedWidth / Math.max(previewScale, 0.001);
        setDragPayload(event, {
          kind: "item",
          id: item.id,
          ...(Number.isFinite(width) && width > 0 ? { width } : {}),
        });
      }}
      onDragEnd={clearDragPayload}
      onDragOver={(event) => {
        if (editingLocked || kind !== "group") return;
        const payload = getDragPayload(event);
        if (!payload || (payload.kind === "item" && payload.id === item.id)) return;
        event.preventDefault();
        event.stopPropagation();
        onClearBarDropTarget();
        if (event.dataTransfer) event.dataTransfer.dropEffect = payload.kind === "palette" ? "copy" : "move";
        setGroupDropActive(true);
      }}
      onDragLeave={(event) => {
        if (!groupDropActive) return;
        const related = event.relatedTarget;
        if (related instanceof Node && event.currentTarget.contains(related)) return;
        setGroupDropActive(false);
      }}
      onDrop={(event) => {
        if (editingLocked || kind !== "group") return;
        const payload = getDragPayload(event);
        if (!payload || (payload.kind === "item" && payload.id === item.id)) return;
        event.preventDefault();
        event.stopPropagation();
        setGroupDropActive(false);
        clearDragPayload();
        if (payload.kind === "palette") onAddIntoGroup(payload.type, item.id);
        else onMoveIntoGroup(payload.id, item.id);
      }}
      onClick={() => onSelect(item.id)}
      aria-pressed={selected}
      aria-label={displayedTitle || presentation.label}
      title={`${itemLabel(item)} · ${item.type}`}
    >
      {renderedImage ? (
        <img class="touch-item-image touch-item-complete-render" src={renderedImage} alt="" aria-hidden="true" draggable={false} />
      ) : (
        <>
          {configuredImage && <img class="touch-item-image touch-item-config-image" src={configuredImage} alt="" aria-hidden="true" draggable={false} />}
          {showFallbackIcon && (
            <span class="touch-item-symbol" aria-hidden="true">
              <ItemTypeIcon type={kind} fallback={presentation.icon} />
            </span>
          )}
          {displayedTitle && <span class="touch-item-label">{displayedTitle}</span>}
          {kind === "group" && (
            <span class="touch-item-group-count" aria-hidden="true">
              {Array.isArray(item.items) ? item.items.length : 0}
            </span>
          )}
        </>
      )}
    </button>
  );
}

export function TouchBarPreview(props: TouchBarPreviewProps) {
  const fitRef = useRef<HTMLDivElement>(null);
  const trackRef = useRef<HTMLDivElement>(null);
  const zoneRefs = useRef<Partial<Record<Alignment, HTMLDivElement>>>({});
  const [scale, setScale] = useState(1);
  const [dropTarget, setDropTarget] = useState<DropIndicatorTarget>();
  const [zoneFrames, setZoneFrames] = useState<TouchBarZoneFrames>();
  const [zoneOverflow, setZoneOverflow] = useState<Record<Alignment, ZoneOverflow>>({
    left: { leading: false, trailing: false },
    center: { leading: false, trailing: false },
    right: { leading: false, trailing: false },
  });
  const scrollMemory = useRef<Record<Alignment, { initialized: boolean; maximum: number }>>({
    left: { initialized: false, maximum: 0 },
    center: { initialized: false, maximum: 0 },
    right: { initialized: false, maximum: 0 },
  });
  const dropTargetRef = useRef<DropIndicatorTarget>();
  const updateDropTarget = (target?: DropIndicatorTarget) => {
    const current = dropTargetRef.current;
    if (
      current?.align === target?.align
      && current?.beforeID === target?.beforeID
      && current?.draggedItemID === target?.draggedItemID
      && current?.previewWidth === target?.previewWidth
    ) return;
    dropTargetRef.current = target;
    setDropTarget(target);
  };
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
  const byAlignment = (align: Alignment) => props.document.items
    .filter((item) => geometries.get(item.id)?.visible !== false && (geometries.get(item.id)?.align ?? item.align ?? "left") === align)
    .sort((left, right) => {
      const leftX = geometries.get(left.id)?.x;
      const rightX = geometries.get(right.id)?.x;
      return typeof leftX === "number" && typeof rightX === "number" ? leftX - rightX : 0;
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
  useEffect(() => {
    const clear = () => updateDropTarget(undefined);
    window.addEventListener("dragend", clear);
    window.addEventListener("drop", clear);
    return () => {
      window.removeEventListener("dragend", clear);
      window.removeEventListener("drop", clear);
    };
  }, []);

  useLayoutEffect(() => {
    const track = trackRef.current;
    if (!track) return;
    const measure = () => {
      const trackWidth = track.clientWidth || track.getBoundingClientRect().width / Math.max(scale, 0.001);
      if (!(trackWidth > 0)) return;
      const naturalWidth = (align: Alignment) => {
        const zone = zoneRefs.current[align];
        if (!zone) return 0;
        const children = Array.from(zone.children).filter((child): child is HTMLElement => (
          child instanceof HTMLElement
          && (child.classList.contains("touch-item") || child.classList.contains("drop-preview-slot"))
        ));
        if (children.length === 0) return 0;
        const gap = Number.parseFloat(getComputedStyle(zone).columnGap || getComputedStyle(zone).gap) || 0;
        return children.reduce((total, child) => {
          const renderedWidth = child.offsetWidth || child.getBoundingClientRect().width / Math.max(scale, 0.001);
          return total + Math.max(0, renderedWidth);
        }, gap * Math.max(0, children.length - 1));
      };
      const next = computeTouchBarZoneFrames(trackWidth, {
        left: naturalWidth("left"),
        center: naturalWidth("center"),
        right: naturalWidth("right"),
      });
      setZoneFrames((current) => {
        const unchanged = current && (["left", "center", "right"] as Alignment[]).every((align) => (
          Math.abs(current[align].x - next[align].x) < 0.25
          && Math.abs(current[align].width - next[align].width) < 0.25
        ));
        return unchanged ? current : next;
      });
    };
    measure();
    const observer = typeof ResizeObserver === "undefined" ? undefined : new ResizeObserver(measure);
    observer?.observe(track);
    (["left", "center", "right"] as Alignment[]).forEach((align) => {
      const zone = zoneRefs.current[align];
      if (zone) observer?.observe(zone);
    });
    return () => observer?.disconnect();
  }, [props.document, props.runtimeSnapshot, dropTarget, scale]);

  const refreshZoneOverflow = () => {
    const next = {} as Record<Alignment, ZoneOverflow>;
    (["left", "center", "right"] as Alignment[]).forEach((align) => {
      const zone = zoneRefs.current[align];
      const maximum = zone ? Math.max(0, zone.scrollWidth - zone.clientWidth) : 0;
      const offset = zone?.scrollLeft ?? 0;
      next[align] = {
        leading: offset > 1,
        trailing: offset < maximum - 1,
      };
      scrollMemory.current[align].maximum = maximum;
    });
    setZoneOverflow((current) => (["left", "center", "right"] as Alignment[]).every((align) => (
      current[align].leading === next[align].leading
      && current[align].trailing === next[align].trailing
    )) ? current : next);
  };

  useLayoutEffect(() => {
    if (!zoneFrames) return;
    (["left", "center", "right"] as Alignment[]).forEach((align) => {
      const zone = zoneRefs.current[align];
      if (!zone) return;
      const memory = scrollMemory.current[align];
      const previousMaximum = memory.maximum;
      const wasAtTrailingEdge = previousMaximum > 0 && zone.scrollLeft >= previousMaximum - 1;
      const maximum = Math.max(0, zone.scrollWidth - zone.clientWidth);
      if (!memory.initialized) {
        if (align === "right") zone.scrollLeft = maximum;
        else if (align === "center") zone.scrollLeft = maximum / 2;
        else zone.scrollLeft = 0;
        memory.initialized = true;
      } else if (align === "right" && (wasAtTrailingEdge || previousMaximum === 0)) {
        zone.scrollLeft = maximum;
      } else {
        zone.scrollLeft = Math.min(zone.scrollLeft, maximum);
      }
      memory.maximum = maximum;
    });
    refreshZoneOverflow();
  }, [zoneFrames, props.document, dropTarget]);

  const zoneStyle = (align: Alignment) => {
    const frame = zoneFrames?.[align];
    if (!frame) return undefined;
    const isEmptyTarget = byAlignment(align).length === 0 && dropTarget?.align !== align;
    if (!isEmptyTarget || frame.width > 0) {
      return { left: `${frame.x}px`, width: `${frame.width}px` };
    }
    const placeholderWidth = 66;
    const trackWidth = trackRef.current?.clientWidth ?? 0;
    const x = align === "left" ? 0 : align === "right"
      ? Math.max(0, trackWidth - placeholderWidth)
      : Math.max(0, trackWidth / 2 - placeholderWidth / 2);
    return { left: `${x}px`, width: `${placeholderWidth}px` };
  };
  const dropPreviewWidth = (payload: ReturnType<typeof getDragPayload>): number => {
    if (payload?.kind === "item") {
      if (typeof payload.width === "number") return payload.width;
      const dragged = Array.from(trackRef.current?.querySelectorAll<HTMLElement>(".touch-item") ?? [])
        .find((element) => element.dataset.itemId === payload.id);
      if (dragged) {
        const width = dragged.offsetWidth || dragged.getBoundingClientRect().width / Math.max(scale, 0.001);
        if (Number.isFinite(width) && width > 0) return width;
      }
    }
    if (payload?.kind === "palette") {
      const candidate = createItem(payload.type, props.schema);
      if (typeof candidate.width === "number") return Math.max(18, candidate.width);
      const label = itemLabel(candidate);
      return Math.max(DEFAULT_DROP_PREVIEW_WIDTH, Math.min(180, 28 + label.length * 7));
    }
    return DEFAULT_DROP_PREVIEW_WIDTH;
  };
  const previewSlot = (align: Alignment) => (
    <span
      class="drop-preview-slot"
      data-testid={`drop-slot-${align}`}
      style={{ width: `${dropTarget?.previewWidth ?? DEFAULT_DROP_PREVIEW_WIDTH}px` }}
      aria-hidden="true"
    >
      <span class="drop-indicator" data-testid={`drop-indicator-${align}`} />
    </span>
  );
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
              Autorisez MMTMR dans Réglages &gt; Accessibilité pour saisir les lettres dans les autres apps.
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
              {(["left", "center", "right"] as Alignment[]).map((align) => {
                const zoneItems = byAlignment(align);
                const active = dropTarget?.align === align;
                const items = dropTarget?.draggedItemID
                  ? zoneItems.filter((item) => item.id !== dropTarget.draggedItemID)
                  : zoneItems;
                return (
                  <div
                    class={`drop-zone drop-zone-${align} ${active ? "drag-over" : ""} ${zoneOverflow[align].leading ? "overflow-leading" : ""} ${zoneOverflow[align].trailing ? "overflow-trailing" : ""}`}
                    data-testid={`drop-${align}`}
                    data-align={align}
                    key={align}
                    ref={(element) => { zoneRefs.current[align] = element ?? undefined; }}
                    style={zoneStyle(align)}
                    onScroll={refreshZoneOverflow}
                    onDragOver={(event) => {
                      if (props.editingLocked) return;
                      event.preventDefault();
                      const payload = getDragPayload(event);
                      if (event.dataTransfer) event.dataTransfer.dropEffect = payload?.kind === "palette" ? "copy" : "move";
                      const draggedItemID = payload?.kind === "item" ? payload.id : undefined;
                      updateDropTarget({
                        align,
                        beforeID: insertionTarget(event.currentTarget, event.clientX, draggedItemID),
                        draggedItemID,
                        previewWidth: dropPreviewWidth(payload),
                      });
                    }}
                    onDragLeave={(event) => {
                      const related = event.relatedTarget;
                      if (related instanceof Node && event.currentTarget.contains(related)) return;
                      const bounds = event.currentTarget.getBoundingClientRect();
                      const stillInside = event.clientX >= bounds.left && event.clientX <= bounds.right
                        && event.clientY >= bounds.top && event.clientY <= bounds.bottom;
                      if (!stillInside) updateDropTarget(undefined);
                    }}
                    onDrop={(event) => {
                      const beforeID = dropTargetRef.current?.align === align
                        ? dropTargetRef.current.beforeID
                        : undefined;
                      updateDropTarget(undefined);
                      dropHandler(event, align, props.schema, props.onMove, props.onAdd, props.editingLocked, beforeID);
                    }}
                  >
                    {items.length === 0 && !active && <span class="drop-placeholder">{align}</span>}
                    {active && items.length === 0 && previewSlot(align)}
                    {items.map((item) => (
                      <Fragment key={item.id}>
                        {active && dropTarget?.beforeID === item.id && previewSlot(align)}
                        <PreviewItem
                          item={item}
                          selected={props.selectedID === item.id}
                          simulation={props.simulation}
                          geometry={geometries.get(item.id)}
                          onSelect={props.onSelect}
                          onMoveIntoGroup={props.onMoveIntoGroup}
                          onAddIntoGroup={props.onAddIntoGroup}
                          onClearBarDropTarget={() => updateDropTarget(undefined)}
                          editingLocked={props.editingLocked ?? false}
                          previewScale={scale}
                        />
                      </Fragment>
                    ))}
                    {active && items.length > 0 && dropTarget?.beforeID === undefined && previewSlot(align)}
                  </div>
                );
              })}
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}
