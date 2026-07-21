import { useEffect, useMemo, useRef, useState } from "preact/hooks";
import { api } from "../api";
import {
  ACTION_TRIGGERS,
  actionSchemaForType,
  defaultValueForSchema,
  itemEditorName,
  itemPresentation,
  itemSchemaForType,
  propertyType,
  resolveReference,
  schemaActionTypes,
  schemaItemTypes,
} from "../model";
import type {
  ActionConfig,
  Alignment,
  ApplicationDescriptor,
  Diagnostic,
  ItemConfig,
  JsonObject,
  JsonSchema,
  JsonValue,
  PinnedApplicationConfig,
} from "../types";
import { clearDragPayload, getDragPayload, setDragPayload } from "./Palette";
import { ItemTypeIcon } from "./MediaControlIcon";

interface InspectorProps {
  item?: ItemConfig;
  itemPath?: string;
  ancestors?: ItemConfig[];
  schema?: JsonSchema;
  diagnostics?: Diagnostic[];
  editingLocked?: boolean;
  collapsed: boolean;
  onToggle(): void;
  onChange(item: ItemConfig): void;
  onSelect(id: string): void;
  onMoveToGroup(id: string, groupID: string, align?: Alignment, beforeID?: string): void;
  onAddToGroup(type: string, groupID: string, align?: Alignment, beforeID?: string): void;
  onDuplicate(): void;
  onDelete(): void;
}

const FALLBACK_PROPERTIES: Record<string, JsonSchema> = {
  id: { type: "string", title: "Identifiant", readOnly: true },
  type: { type: "string", title: "Type", readOnly: true },
  editorName: { type: "string", title: "Nom dans l’éditeur", description: "Nom privé utilisé uniquement pour vous repérer dans MMTMR." },
  title: { type: "string", title: "Titre" },
  align: { type: "string", title: "Alignement", enum: ["left", "center", "right"] },
  width: { type: "number", title: "Largeur", minimum: 18 },
  bordered: { type: "boolean", title: "Bordure" },
  enabled: { type: "boolean", title: "Activé", default: true },
  notes: { type: "string", title: "Notes" },
  actions: { type: "array", title: "Actions" },
};

const ACTION_PROPERTY_LABELS: Record<string, string> = {
  text: "Texte UTF-8",
  keycode: "Code de touche",
  actionAppleScript: "AppleScript",
  executablePath: "Exécutable",
  shellArguments: "Arguments",
  url: "URL",
  source: "Source",
  refreshInterval: "Rafraîchissement (secondes)",
  alternativeImages: "Images alternatives",
  formatTemplate: "Format de l’heure",
  timeZone: "Fuseau horaire",
  locale: "Locale",
  autoResize: "Largeur automatique",
  spacing: "Marge entre les icônes",
  filter: "Filtre d’applications",
  units: "Unités",
  api_key: "Clé API",
  icon_type: "Type d’icône",
  from: "Depuis",
  to: "Vers",
  full: "Affichage complet",
  disableMarquee: "Désactiver le défilement",
  items: "Éléments imbriqués",
  workTime: "Durée de travail",
  restTime: "Durée de repos",
  flip: "Inverser montant et descendant",
  direction: "Direction",
  fingers: "Nombre de doigts",
  minOffset: "Distance minimale",
  sourceApple: "AppleScript",
  sourceBash: "Script shell",
  maxToShow: "Nombre maximal",
};

function fieldLabel(key: string, schema?: JsonSchema): string {
  return ACTION_PROPERTY_LABELS[key] ?? FALLBACK_PROPERTIES[key]?.title ?? schema?.title ?? key;
}

function childPath(parent: string | undefined, child: string): string | undefined {
  return parent ? `${parent}.${child}` : undefined;
}

function diagnosticsAtPath(
  diagnostics: Diagnostic[],
  path: string | undefined,
  includeDescendants = true,
): Diagnostic[] {
  if (!path) return [];
  return diagnostics.filter((entry) => {
    if (!entry.path) return false;
    if (entry.path === path) return true;
    return includeDescendants && (entry.path.startsWith(`${path}.`) || entry.path.startsWith(`${path}[`));
  });
}

function InlineDiagnostics({ diagnostics }: { diagnostics: Diagnostic[] }) {
  if (diagnostics.length === 0) return null;
  return (
    <>
      {diagnostics.map((entry, index) => (
        <small
          class={`field-error diagnostic-${entry.severity === "information" ? "info" : entry.severity}`}
          key={`${entry.path}-${entry.code}-${entry.message}-${index}`}
        >
          {entry.message}
        </small>
      ))}
    </>
  );
}

function valueFromInput(type: string, input: HTMLInputElement | HTMLSelectElement | HTMLTextAreaElement): JsonValue {
  if (type === "boolean" && input instanceof HTMLInputElement) return input.checked;
  if (type === "number" || type === "integer") return input.value === "" ? 0 : Number(input.value);
  return input.value;
}

function StructuredValue({ value, label, onChange }: { value: JsonValue; label: string; onChange(value: JsonValue): void }) {
  const [text, setText] = useState(() => JSON.stringify(value, null, 2));
  const [invalid, setInvalid] = useState(false);
  useEffect(() => setText(JSON.stringify(value, null, 2)), [value]);
  return (
    <textarea
      class={invalid ? "field-invalid mono-field" : "mono-field"}
      rows={5}
      aria-label={label}
      value={text}
      onInput={(event) => {
        const source = event.currentTarget.value;
        setText(source);
        try {
          const parsed = JSON.parse(source) as JsonValue;
          setInvalid(false);
          onChange(parsed);
        } catch {
          setInvalid(true);
        }
      }}
      aria-invalid={invalid}
    />
  );
}

function PropertyField({
  name,
  schema,
  rootSchema,
  value,
  required,
  diagnostics = [],
  onChange,
  onUnset,
}: {
  name: string;
  schema?: JsonSchema;
  rootSchema?: JsonSchema;
  value: JsonValue | undefined;
  required: boolean;
  diagnostics?: Diagnostic[];
  onChange(value: JsonValue): void;
  onUnset(): void;
}) {
  const resolvedSchema = resolveReference(rootSchema, schema) ?? schema;
  const type = propertyType(resolvedSchema, value);
  const label = fieldLabel(name, resolvedSchema);
  const canUnset = !required && value !== undefined && !resolvedSchema?.readOnly;
  const sourceProperties = resolvedSchema?.properties ?? {};
  const isSource = ["filePath", "base64", "inline"].every((key) => key in sourceProperties);
  const hasErrors = diagnostics.some((entry) => entry.severity === "error");
  const effectiveBoolean = value === true || (value === undefined && resolvedSchema?.default === true);

  if (isSource) {
    const object = typeof value === "object" && value !== null && !Array.isArray(value)
      ? value as JsonObject
      : {};
    const mode = (["inline", "filePath", "base64"] as const).find((key) => typeof object[key] === "string") ?? "inline";
    const content = typeof object[mode] === "string" ? object[mode] as string : "";
    return (
      <div class={`property-field property-source ${hasErrors ? "field-invalid" : ""}`}>
        <span class="field-label">
          <span>{label}{required && <span class="required-mark"> *</span>}</span>
          {canUnset && <button type="button" class="unset-button" onClick={onUnset}>Réinitialiser</button>}
        </span>
        {resolvedSchema?.description && <small class="field-description">{resolvedSchema.description}</small>}
        <select
          aria-label={`${label} — mode`}
          value={mode}
          disabled={resolvedSchema?.readOnly}
          aria-invalid={hasErrors}
          onChange={(event) => onChange({ [event.currentTarget.value]: "" })}
        >
          <option value="inline">Contenu intégré</option>
          <option value="filePath">Chemin de fichier</option>
          <option value="base64">Base64</option>
        </select>
        {mode === "filePath" ? (
          <input
            type="text"
            value={content}
            readOnly={resolvedSchema?.readOnly}
            aria-invalid={hasErrors}
            onInput={(event) => onChange({ filePath: event.currentTarget.value })}
          />
        ) : (
          <textarea
            class="mono-field"
            rows={mode === "inline" ? 6 : 4}
            value={content}
            readOnly={resolvedSchema?.readOnly}
            aria-invalid={hasErrors}
            onInput={(event) => onChange({ [mode]: event.currentTarget.value })}
          />
        )}
        <InlineDiagnostics diagnostics={diagnostics} />
      </div>
    );
  }

  return (
    <div class={`property-field property-${type} ${hasErrors ? "field-invalid" : ""}`}>
      <span class="field-label">
        <span>{label}{required && <span class="required-mark"> *</span>}</span>
        {canUnset && <button type="button" class="unset-button" onClick={onUnset}>Réinitialiser</button>}
      </span>
      {resolvedSchema?.description && <small class="field-description">{resolvedSchema.description}</small>}
      {type === "boolean" ? (
        <span class="switch-row">
          <input
            type="checkbox"
            aria-label={label}
            checked={effectiveBoolean}
            disabled={resolvedSchema?.readOnly}
            aria-invalid={hasErrors}
            onChange={(event) => onChange(event.currentTarget.checked)}
          />
          <span>{effectiveBoolean ? "Oui" : "Non"}</span>
        </span>
      ) : resolvedSchema?.enum ? (
        <select
          aria-label={label}
          value={value === undefined ? "" : String(value)}
          disabled={resolvedSchema.readOnly}
          aria-invalid={hasErrors}
          onChange={(event) => onChange(valueFromInput(type, event.currentTarget))}
        >
          {!required && <option value="">—</option>}
          {resolvedSchema.enum.map((choice) => <option value={String(choice)} key={String(choice)}>{String(choice)}</option>)}
        </select>
      ) : type === "number" || type === "integer" ? (
        <input
          type="number"
          aria-label={label}
          value={typeof value === "number" ? value : ""}
          min={resolvedSchema?.minimum}
          max={resolvedSchema?.maximum}
          step={type === "integer" ? 1 : "any"}
          disabled={resolvedSchema?.readOnly}
          aria-invalid={hasErrors}
          onInput={(event) => onChange(valueFromInput(type, event.currentTarget))}
        />
      ) : type === "array" || type === "object" ? (
        <StructuredValue value={value ?? (type === "array" ? [] : {})} label={label} onChange={onChange} />
      ) : name === "notes" || name.toLowerCase().includes("script") ? (
        <textarea
          aria-label={label}
          rows={name === "notes" ? 3 : 6}
          value={typeof value === "string" ? value : ""}
          readOnly={resolvedSchema?.readOnly}
          aria-invalid={hasErrors}
          onInput={(event) => onChange(event.currentTarget.value)}
        />
      ) : (
        <input
          type="text"
          aria-label={label}
          value={value === undefined ? "" : String(value)}
          readOnly={resolvedSchema?.readOnly}
          minlength={resolvedSchema?.minLength}
          maxlength={resolvedSchema?.maxLength}
          aria-invalid={hasErrors}
          onInput={(event) => onChange(event.currentTarget.value)}
        />
      )}
      <InlineDiagnostics diagnostics={diagnostics} />
    </div>
  );
}

function stringEnum(schema: JsonSchema | undefined): string[] {
  return (schema?.enum ?? []).filter((value): value is string => typeof value === "string");
}

function createAction(type: string, rootSchema?: JsonSchema, preferredTrigger?: string): ActionConfig {
  const actionSchema = actionSchemaForType(rootSchema, type);
  const triggerSchema = resolveReference(rootSchema, actionSchema?.properties?.trigger) ?? actionSchema?.properties?.trigger;
  const triggerOptions = stringEnum(triggerSchema);
  const schemaDefault = triggerSchema?.default;
  const trigger = preferredTrigger && triggerOptions.includes(preferredTrigger)
    ? preferredTrigger
    : typeof schemaDefault === "string" && (triggerOptions.length === 0 || triggerOptions.includes(schemaDefault))
      ? schemaDefault
      : triggerOptions[0] ?? ACTION_TRIGGERS[0];
  const result: ActionConfig = { trigger, action: type };
  const required = new Set(actionSchema?.required ?? []);

  for (const [name, propertySchema] of Object.entries(actionSchema?.properties ?? {})) {
    if (name === "trigger" || name === "action") continue;
    const resolved = resolveReference(rootSchema, propertySchema) ?? propertySchema;
    if (resolved.default !== undefined || required.has(name)) {
      result[name] = defaultValueForSchema(rootSchema, propertySchema);
    }
  }
  return result;
}

function ActionsEditor({
  actions = [],
  schema,
  diagnostics = [],
  path,
  onChange,
}: {
  actions?: ActionConfig[];
  schema?: JsonSchema;
  diagnostics?: Diagnostic[];
  path?: string;
  onChange(actions: ActionConfig[]): void;
}) {
  const actionTypes = schemaActionTypes(schema);
  const defaultActionType = actionTypes.includes("typeText") ? "typeText" : actionTypes[0] ?? "typeText";
  const collectionDiagnostics = diagnosticsAtPath(diagnostics, path, false);
  const replace = (index: number, action: ActionConfig) => {
    onChange(actions.map((candidate, current) => current === index ? action : candidate));
  };

  return (
    <div class="actions-editor">
      <div class="subheading-row">
        <span>Actions</span>
        <button
          type="button"
          class="small-button"
          onClick={() => onChange([...actions, createAction(defaultActionType, schema)])}
        >
          + Ajouter
        </button>
      </div>
      <InlineDiagnostics diagnostics={collectionDiagnostics} />
      {actions.length === 0 && <div class="empty-state compact">Aucune action.</div>}
      {actions.map((action, index) => {
        const actionPath = path ? `${path}[${index}]` : undefined;
        const actionSchema = actionSchemaForType(schema, action.action);
        const triggerSchema = resolveReference(schema, actionSchema?.properties?.trigger) ?? actionSchema?.properties?.trigger;
        const triggerOptions = stringEnum(triggerSchema);
        const validTriggers = triggerOptions.length > 0 ? triggerOptions : [...ACTION_TRIGGERS];
        const unknownTrigger = !validTriggers.includes(action.trigger);
        const unknownActionType = !actionTypes.includes(action.action);
        const fieldNames = new Set([
          ...Object.keys(actionSchema?.properties ?? {}).filter((name) => name !== "trigger" && name !== "action"),
          ...Object.keys(action).filter((name) => name !== "trigger" && name !== "action"),
        ]);
        const actionDiagnostics = diagnosticsAtPath(diagnostics, actionPath, false);
        const actionHasErrors = diagnosticsAtPath(diagnostics, actionPath).some((entry) => entry.severity === "error");

        return (
          <div class={`action-card ${actionHasErrors ? "field-invalid" : ""}`} key={`${action.trigger}-${index}`}>
            <div class="action-card-head">
              <strong>{actionSchema?.title ?? `Action ${index + 1}`}</strong>
              <button
                type="button"
                class="danger-link"
                onClick={() => onChange(actions.filter((_, current) => current !== index))}
              >
                Supprimer
              </button>
            </div>
            <label class="property-field">
              <span class="field-label">Déclencheur</span>
              <select
                value={action.trigger}
                aria-invalid={diagnosticsAtPath(diagnostics, childPath(actionPath, "trigger")).some((entry) => entry.severity === "error")}
                onChange={(event) => replace(index, { ...action, trigger: event.currentTarget.value })}
              >
                {unknownTrigger && <option value={action.trigger} disabled>{action.trigger} — invalide</option>}
                {validTriggers.map((trigger) => (
                  <option value={trigger} key={trigger}>{trigger}</option>
                ))}
              </select>
              <InlineDiagnostics diagnostics={diagnosticsAtPath(diagnostics, childPath(actionPath, "trigger"))} />
            </label>
            <label class="property-field">
              <span class="field-label">Type d’action</span>
              <select
                value={action.action}
                aria-invalid={diagnosticsAtPath(diagnostics, childPath(actionPath, "action")).some((entry) => entry.severity === "error")}
                onChange={(event) => replace(index, createAction(event.currentTarget.value, schema, action.trigger))}
              >
                {unknownActionType && <option value={action.action} disabled>{action.action} — invalide</option>}
                {actionTypes.map((kind) => {
                  const variant = actionSchemaForType(schema, kind);
                  return <option value={kind} key={kind}>{variant?.title ?? kind}</option>;
                })}
              </select>
              <InlineDiagnostics diagnostics={diagnosticsAtPath(diagnostics, childPath(actionPath, "action"))} />
            </label>
            {[...fieldNames].map((name) => {
              const propertySchema = actionSchema?.properties?.[name];
              const required = actionSchema?.required?.includes(name) ?? false;
              return (
                <PropertyField
                  key={name}
                  name={name}
                  schema={propertySchema}
                  rootSchema={schema}
                  value={action[name]}
                  required={required}
                  diagnostics={diagnosticsAtPath(diagnostics, childPath(actionPath, name))}
                  onChange={(value) => replace(index, { ...action, [name]: value })}
                  onUnset={() => {
                    const next = { ...action };
                    delete next[name];
                    replace(index, next);
                  }}
                />
              );
            })}
            <InlineDiagnostics diagnostics={actionDiagnostics} />
          </div>
        );
      })}
    </div>
  );
}

interface GroupDropTarget {
  align: Alignment;
  beforeID?: string;
}

function groupInsertionTarget(zone: HTMLDivElement, clientY: number, draggedItemID?: string): string | undefined {
  const children = Array.from(zone.querySelectorAll<HTMLElement>(".group-child-card"))
    .filter((child) => child.dataset.itemId !== draggedItemID);
  for (const child of children) {
    const bounds = child.getBoundingClientRect();
    if (clientY < bounds.top + bounds.height / 2) return child.dataset.itemId;
  }
  return undefined;
}

function GroupItemsEditor({
  group,
  schema,
  onSelect,
  onMoveToGroup,
  onAddToGroup,
}: {
  group: ItemConfig;
  schema?: JsonSchema;
  onSelect(id: string): void;
  onMoveToGroup(id: string, groupID: string, align?: Alignment, beforeID?: string): void;
  onAddToGroup(type: string, groupID: string, align?: Alignment, beforeID?: string): void;
}) {
  const items = Array.isArray(group.items) ? group.items : [];
  const types = schemaItemTypes(schema);
  const [dropTarget, setDropTarget] = useState<GroupDropTarget>();
  const dropTargetRef = useRef<GroupDropTarget>();
  const updateDropTarget = (target?: GroupDropTarget) => {
    dropTargetRef.current = target;
    setDropTarget(target);
  };
  useEffect(() => {
    const clear = () => updateDropTarget(undefined);
    window.addEventListener("dragend", clear);
    window.addEventListener("drop", clear);
    return () => {
      window.removeEventListener("dragend", clear);
      window.removeEventListener("drop", clear);
    };
  }, []);
  const drop = (event: DragEvent, align: Alignment) => {
    event.preventDefault();
    event.stopPropagation();
    const payload = getDragPayload(event);
    const currentTarget = dropTargetRef.current;
    const beforeID = currentTarget?.align === align ? currentTarget.beforeID : undefined;
    updateDropTarget(undefined);
    clearDragPayload();
    if (!payload) return;
    if (payload.kind === "palette") onAddToGroup(payload.type, group.id, align, beforeID);
    else if (payload.id !== group.id) onMoveToGroup(payload.id, group.id, align, beforeID);
  };

  return (
    <div class="group-items-editor">
      <div class="subheading-row group-editor-heading">
        <span>Contenu du groupe <small>{items.length}</small></span>
        <select
          aria-label="Ajouter un composant au groupe"
          value=""
          onChange={(event) => {
            const type = event.currentTarget.value;
            if (type) onAddToGroup(type, group.id, "left");
            event.currentTarget.value = "";
          }}
        >
          <option value="">+ Ajouter…</option>
          {types.map((entry) => <option value={entry.type} key={entry.type}>{entry.label}</option>)}
        </select>
      </div>
      <p class="group-editor-hint">Ce bouton ouvre une sous-barre sur la Touch Bar physique. Glissez ici les composants qu’elle doit contenir.</p>
      <div class="group-lanes">
        {(["left", "center", "right"] as Alignment[]).map((align) => {
          const laneItems = items.filter((item) => (item.align ?? "left") === align);
          const active = dropTarget?.align === align;
          return (
            <div
              class={`group-lane ${active ? "drag-over" : ""}`}
              data-testid={`group-drop-${align}`}
              key={align}
              onDragOver={(event) => {
                const payload = getDragPayload(event);
                if (!payload || (payload.kind === "item" && payload.id === group.id)) {
                  updateDropTarget(undefined);
                  return;
                }
                event.preventDefault();
                event.stopPropagation();
                if (event.dataTransfer) event.dataTransfer.dropEffect = payload.kind === "palette" ? "copy" : "move";
                updateDropTarget({
                  align,
                  beforeID: groupInsertionTarget(event.currentTarget, event.clientY, payload.kind === "item" ? payload.id : undefined),
                });
              }}
              onDragLeave={(event) => {
                const related = event.relatedTarget;
                if (related instanceof Node && event.currentTarget.contains(related)) return;
                if (dropTargetRef.current?.align === align) updateDropTarget(undefined);
              }}
              onDrop={(event) => drop(event, align)}
            >
              <div class="group-lane-label">{align === "left" ? "Gauche" : align === "center" ? "Centre" : "Droite"}</div>
              {laneItems.length === 0 && !active && <div class="group-lane-empty">Déposer ici</div>}
              {laneItems.map((child) => {
                const presentation = itemPresentation(child.type);
                return (
                  <div key={child.id}>
                    {active && dropTarget?.beforeID === child.id && <div class="group-drop-indicator" />}
                    <div
                      class="group-child-card"
                      data-item-id={child.id}
                      draggable
                      onDragStart={(event) => setDragPayload(event, { kind: "item", id: child.id })}
                      onDragEnd={() => { clearDragPayload(); updateDropTarget(undefined); }}
                    >
                      <button type="button" onClick={() => onSelect(child.id)} title={`Inspecter ${itemEditorName(child)}`}>
                        <span class="group-child-icon" aria-hidden="true"><ItemTypeIcon type={child.type} fallback={presentation.icon} /></span>
                        <span><strong>{itemEditorName(child)}</strong><small>{child.type}</small></span>
                      </button>
                      <span class="drag-handle" aria-hidden="true">⠿</span>
                    </div>
                  </div>
                );
              })}
              {active && dropTarget?.beforeID === undefined && <div class="group-drop-indicator" />}
            </div>
          );
        })}
      </div>
    </div>
  );
}

function AppleToggle({
  label,
  detail,
  checked,
  onChange,
}: {
  label: string;
  detail: string;
  checked: boolean;
  onChange(value: boolean): void;
}) {
  return (
    <label class="apple-toggle-row">
      <span><strong>{label}</strong><small>{detail}</small></span>
      <span class="apple-toggle">
        <input type="checkbox" role="switch" checked={checked} onChange={(event) => onChange(event.currentTarget.checked)} />
        <span aria-hidden="true" />
      </span>
    </label>
  );
}

function PinnedApplicationIcon({ application, label }: { application?: ApplicationDescriptor; label: string }) {
  return application?.icon ? (
    <img class="pinned-app-icon" src={application.icon} title={label} alt="" aria-hidden="true" draggable={false} />
  ) : (
    <span class="pinned-app-icon pinned-app-icon-missing" title={label} aria-hidden="true">A</span>
  );
}

function PinnedDockEditor({ item, onChange }: { item: ItemConfig; onChange(item: ItemConfig): void }) {
  const [catalog, setCatalog] = useState<ApplicationDescriptor[]>([]);
  const [catalogState, setCatalogState] = useState<"loading" | "ready" | "error">("loading");
  const [catalogError, setCatalogError] = useState("");
  const [query, setQuery] = useState("");
  const [selectedIdentifier, setSelectedIdentifier] = useState("");
  const [manualIdentifier, setManualIdentifier] = useState("");
  const [draggedIndex, setDraggedIndex] = useState<number>();
  const [dropIndex, setDropIndex] = useState<number>();
  const configured = Array.isArray(item.applications) ? item.applications : [];
  const spacing = typeof item.spacing === "number" && Number.isFinite(item.spacing)
    ? Math.max(0, Math.min(20, item.spacing))
    : 1;
  const catalogByIdentifier = useMemo(
    () => new Map(catalog.map((application) => [application.bundleIdentifier, application])),
    [catalog],
  );

  const loadCatalog = async () => {
    setCatalogState("loading");
    try {
      const result = await api.applications();
      setCatalog(result.applications);
      setCatalogError("");
      setCatalogState("ready");
    } catch (error) {
      setCatalogError(error instanceof Error ? error.message : "Catalogue indisponible");
      setCatalogState("error");
    }
  };

  useEffect(() => {
    void loadCatalog();
  }, []);

  const configuredIdentifiers = useMemo(
    () => new Set(configured.map((application) => application.bundleIdentifier)),
    [configured],
  );
  const normalizedQuery = query.trim().toLocaleLowerCase();
  const choices = catalog.filter((application) => {
    if (configuredIdentifiers.has(application.bundleIdentifier)) return false;
    if (!normalizedQuery) return true;
    return [application.name, application.bundleIdentifier, application.path]
      .some((value) => value.toLocaleLowerCase().includes(normalizedQuery));
  });
  const effectiveSelectedIdentifier = choices.some((application) => application.bundleIdentifier === selectedIdentifier)
    ? selectedIdentifier
    : choices[0]?.bundleIdentifier ?? "";
  const selectedApplication = catalogByIdentifier.get(effectiveSelectedIdentifier);

  const replaceApplications = (applications: PinnedApplicationConfig[]) => {
    onChange({ ...item, applications });
  };
  const replaceSpacing = (value: number) => {
    if (!Number.isFinite(value)) return;
    onChange({ ...item, spacing: Math.max(0, Math.min(20, value)) });
  };
  const addIdentifier = (bundleIdentifier: string) => {
    const trimmed = bundleIdentifier.trim();
    if (!trimmed || configuredIdentifiers.has(trimmed)) return;
    replaceApplications([...configured, { bundleIdentifier: trimmed }]);
    setSelectedIdentifier("");
  };
  const patchApplication = (index: number, patch: Partial<PinnedApplicationConfig>) => {
    replaceApplications(configured.map((application, candidateIndex) => (
      candidateIndex === index ? { ...application, ...patch } : application
    )));
  };
  const moveApplication = (from: number, to: number) => {
    const bounded = Math.max(0, Math.min(to, configured.length - 1));
    if (from === bounded || from < 0 || from >= configured.length) return;
    const next = [...configured];
    const [application] = next.splice(from, 1);
    next.splice(bounded, 0, application);
    replaceApplications(next);
  };
  const commitDrop = () => {
    if (draggedIndex === undefined || dropIndex === undefined) return;
    const insertion = draggedIndex < dropIndex ? dropIndex - 1 : dropIndex;
    moveApplication(draggedIndex, insertion);
    setDraggedIndex(undefined);
    setDropIndex(undefined);
  };

  return (
    <section class="pinned-dock-editor" aria-label="Applications du Dock fixe">
      <div class="pinned-dock-heading">
        <div>
          <strong>Applications affichées</strong>
          <small>Ordre fixe · ouvertes ou fermées</small>
        </div>
        <span class="count-pill">{configured.length}</span>
      </div>

      <label class="pinned-dock-spacing">
        <span>
          <strong>Marge entre les icônes</strong>
          <small>Espacement horizontal inclus dans la largeur automatique</small>
        </span>
        <div class="pinned-dock-spacing-controls">
          <input
            type="range"
            min="0"
            max="20"
            step="0.5"
            value={spacing}
            aria-label="Marge entre les icônes"
            onInput={(event) => replaceSpacing(event.currentTarget.valueAsNumber)}
          />
          <input
            type="number"
            min="0"
            max="20"
            step="0.5"
            value={spacing}
            aria-label="Marge entre les icônes en points"
            onInput={(event) => replaceSpacing(event.currentTarget.valueAsNumber)}
          />
          <span>pt</span>
        </div>
      </label>

      <div class="pinned-app-picker">
        <label class="property-field">
          <span class="field-label">Rechercher sur ce Mac</span>
          <input
            type="search"
            value={query}
            placeholder="Nom, identifiant ou dossier…"
            onInput={(event) => setQuery(event.currentTarget.value)}
          />
        </label>
        <div class="pinned-app-select-row">
          <div class="pinned-app-select-preview">
            <PinnedApplicationIcon application={selectedApplication} label={selectedApplication?.name ?? "Application"} />
          </div>
          <select
            aria-label="Application à ajouter"
            value={effectiveSelectedIdentifier}
            disabled={catalogState === "loading" || choices.length === 0}
            onChange={(event) => setSelectedIdentifier(event.currentTarget.value)}
          >
            {choices.slice(0, 250).map((application) => (
              <option value={application.bundleIdentifier} key={application.bundleIdentifier}>
                {application.name} — {application.running ? "ouverte" : "fermée"}
              </option>
            ))}
          </select>
          <button
            type="button"
            class="primary-button compact-button"
            aria-label="Ajouter l’application sélectionnée"
            disabled={!effectiveSelectedIdentifier}
            onClick={() => addIdentifier(effectiveSelectedIdentifier)}
          >
            Ajouter
          </button>
        </div>
        <div class="pinned-catalog-meta">
          {catalogState === "loading" && <span>Lecture des applications installées…</span>}
          {catalogState === "ready" && <span>{catalog.length} applications · {choices.length} disponibles</span>}
          {catalogState === "error" && <span class="field-error">{catalogError}</span>}
          <button type="button" class="danger-link" onClick={() => void loadCatalog()}>Actualiser</button>
        </div>
      </div>

      <div
        class="pinned-app-list"
        onDragOver={(event) => {
          if (draggedIndex === undefined || configured.length === 0) return;
          event.preventDefault();
        }}
        onDrop={(event) => {
          event.preventDefault();
          commitDrop();
        }}
      >
        {configured.length === 0 && (
          <div class="empty-state compact">Choisissez une application ci-dessus. Le Dock gardera toujours sa place.</div>
        )}
        {configured.map((application, index) => {
          const installed = catalogByIdentifier.get(application.bundleIdentifier);
          const name = application.label?.trim() || installed?.name || application.bundleIdentifier;
          const before = dropIndex === index;
          const after = dropIndex === configured.length && index === configured.length - 1;
          return (
            <div class="pinned-app-entry" key={`${application.bundleIdentifier}-${index}`}>
              {before && <div class="pinned-app-drop-line" />}
              <article
                class={`pinned-app-card ${draggedIndex === index ? "is-dragging" : ""}`}
                draggable
                onDragStart={(event) => {
                  setDraggedIndex(index);
                  setDropIndex(index);
                  if (event.dataTransfer) {
                    event.dataTransfer.effectAllowed = "move";
                    event.dataTransfer.setData("text/plain", application.bundleIdentifier);
                  }
                }}
                onDragEnd={() => {
                  setDraggedIndex(undefined);
                  setDropIndex(undefined);
                }}
                onDragOver={(event) => {
                  if (draggedIndex === undefined) return;
                  event.preventDefault();
                  const bounds = event.currentTarget.getBoundingClientRect();
                  setDropIndex(event.clientY < bounds.top + bounds.height / 2 ? index : index + 1);
                }}
              >
                <span class="pinned-app-grip" title="Glisser pour réordonner" aria-hidden="true">⠿</span>
                <PinnedApplicationIcon application={installed} label={name} />
                <span class="pinned-app-identity">
                  <strong>{name}</strong>
                  <code>{application.bundleIdentifier}</code>
                </span>
                <span class={`pinned-app-status ${installed?.frontmost ? "frontmost" : installed?.running ? "running" : installed ? "closed" : "missing"}`}>
                  {installed?.frontmost ? "au premier plan" : installed?.running ? "ouverte" : installed ? "fermée" : "introuvable"}
                </span>
                <span class="pinned-app-row-actions">
                  <button type="button" class="icon-button" disabled={index === 0} onClick={() => moveApplication(index, index - 1)} aria-label={`Monter ${name}`}>↑</button>
                  <button type="button" class="icon-button" disabled={index === configured.length - 1} onClick={() => moveApplication(index, index + 1)} aria-label={`Descendre ${name}`}>↓</button>
                  <button type="button" class="icon-button pinned-remove" onClick={() => replaceApplications(configured.filter((_, candidate) => candidate !== index))} aria-label={`Retirer ${name}`}>×</button>
                </span>
                <details class="pinned-app-details">
                  <summary>Nom et chemin facultatifs</summary>
                  <label class="property-field">
                    <span class="field-label">Nom personnel</span>
                    <input
                      type="text"
                      value={application.label ?? ""}
                      placeholder={installed?.name ?? "Nom dans l’éditeur"}
                      onInput={(event) => patchApplication(index, { label: event.currentTarget.value || undefined })}
                    />
                  </label>
                  <label class="property-field">
                    <span class="field-label">Chemin de secours</span>
                    <input
                      type="text"
                      value={application.path ?? ""}
                      placeholder={installed?.path ?? "/Applications/MonApp.app"}
                      onInput={(event) => patchApplication(index, { path: event.currentTarget.value || undefined })}
                    />
                  </label>
                </details>
              </article>
              {after && <div class="pinned-app-drop-line" />}
            </div>
          );
        })}
      </div>

      <details class="pinned-manual-add">
        <summary>Ajouter par identifiant de bundle</summary>
        <p>Pour une application absente du catalogue, saisissez son identifiant macOS.</p>
        <div class="pinned-manual-row">
          <input
            type="text"
            value={manualIdentifier}
            placeholder="com.exemple.Application"
            onInput={(event) => setManualIdentifier(event.currentTarget.value)}
            onKeyDown={(event) => {
              if (event.key !== "Enter") return;
              event.preventDefault();
              addIdentifier(manualIdentifier);
              setManualIdentifier("");
            }}
          />
          <button
            type="button"
            class="secondary-button compact-button"
            aria-label="Ajouter l’identifiant de bundle"
            disabled={!manualIdentifier.trim() || configuredIdentifiers.has(manualIdentifier.trim())}
            onClick={() => {
              addIdentifier(manualIdentifier);
              setManualIdentifier("");
            }}
          >
            Ajouter
          </button>
        </div>
      </details>

      <label class="property-field pinned-long-press">
        <span class="field-label">Appui long</span>
        <span class="field-description">Action après 1,5 seconde sur une application ouverte.</span>
        <select
          value={typeof item.longPressAction === "string" ? item.longPressAction : "quit"}
          onChange={(event) => onChange({ ...item, longPressAction: event.currentTarget.value })}
        >
          <option value="quit">Quitter l’application</option>
          <option value="none">Ne rien faire</option>
        </select>
      </label>
    </section>
  );
}

export function Inspector({
  item,
  itemPath,
  ancestors = [],
  schema,
  diagnostics = [],
  editingLocked = false,
  collapsed,
  onToggle,
  onChange,
  onSelect,
  onMoveToGroup,
  onAddToGroup,
  onDuplicate,
  onDelete,
}: InspectorProps) {
  const itemSchema = useMemo(() => item ? itemSchemaForType(schema, item.type) : undefined, [item, schema]);
  const properties = useMemo(() => {
    if (!item) return {};
    const fallbackKeys = Object.keys(FALLBACK_PROPERTIES).filter((key) => (
      key !== "editorName" || itemSchema?.properties?.editorName !== undefined
    ));
    const keys = new Set([
      ...fallbackKeys,
      ...Object.keys(itemSchema?.properties ?? {}),
      ...Object.keys(item).filter((key) => key !== "editorName" || itemSchema?.properties?.editorName !== undefined),
    ]);
    return Object.fromEntries([...keys].map((key) => [
      key,
      { ...FALLBACK_PROPERTIES[key], ...itemSchema?.properties?.[key] },
    ])) as Record<string, JsonSchema>;
  }, [item, itemSchema]);
  const isSystemUsageGraph = item?.type === "cpu" || item?.type === "memory";
  const supportsActions = !isSystemUsageGraph && (schema ? itemSchema?.properties?.actions !== undefined : true);
  const orderedProperties = useMemo(() => {
    const preferred = [
      "editorName", "title", "notes", "align", "width", "image", "background", "matchAppId",
      "source", "refreshInterval", "formatTemplate", "timeZone", "locale", "alternativeImages",
      "autoResize", "filter", "applications", "showRunningIndicator", "longPressAction",
      "units", "api_key", "icon_type", "from", "to", "full",
      "disableMarquee", "items", "workTime", "restTime", "flip", "direction", "fingers",
      "minOffset", "sourceApple", "sourceBash", "maxToShow", "id", "type",
    ];
    const rank = new Map(preferred.map((name, index) => [name, index]));
    return Object.entries(properties)
      .filter(([name]) => {
        if (["actions", "enabled", "bordered"].includes(name)) return false;
        if (isSystemUsageGraph && ["title", "width", "image", "background"].includes(name)) return false;
        if (item?.type === "group" && name === "items") return false;
        if (["dock", "pinnedDock"].includes(item?.type ?? "") && name === "autoResize") return false;
        if (["dock", "pinnedDock"].includes(item?.type ?? "") && item?.autoResize !== false && name === "width") return false;
        if (item?.type === "pinnedDock" && ["applications", "showRunningIndicator", "longPressAction", "spacing"].includes(name)) return false;
        return true;
      })
      .sort(([left], [right]) => (rank.get(left) ?? 1_000) - (rank.get(right) ?? 1_000));
  }, [isSystemUsageGraph, item, properties]);

  return (
    <aside class={`inspector side-panel ${collapsed ? "is-collapsed" : ""}`} aria-label="Inspecteur">
      <div class="panel-heading">
        <button class="icon-button collapse-button" onClick={onToggle} aria-label={collapsed ? "Ouvrir l’inspecteur" : "Replier l’inspecteur"}>
          {collapsed ? "‹" : "›"}
        </button>
        {!collapsed && <span>Inspecteur</span>}
      </div>
      {!collapsed && (
        <div class="inspector-scroll scroll-region" data-testid="inspector-scroll">
          {!item ? (
            <div class="empty-state">
              <span class="empty-glyph">◇</span>
              Sélectionnez un élément de la barre pour le modifier.
            </div>
          ) : (
            <fieldset class="inspector-fields" disabled={editingLocked}>
              {editingLocked && <div class="draft-lock-banner compact-lock">Brouillon JSON invalide : inspection en lecture seule.</div>}
              {ancestors.length > 0 && (
                <nav class="inspector-breadcrumbs" aria-label="Groupes parents">
                  <span>Dans</span>
                  {ancestors.map((ancestor) => (
                    <button type="button" key={ancestor.id} onClick={() => onSelect(ancestor.id)}>{itemEditorName(ancestor)}</button>
                  ))}
                </nav>
              )}
              <div class="inspector-title">
                <div>
                  <span class="eyebrow">{item.type}</span>
                  <h2>{itemEditorName(item)}</h2>
                </div>
                <span class={`enabled-dot ${item.enabled === false ? "off" : ""}`} title={item.enabled === false ? "Désactivé" : "Activé"} />
              </div>
              <div class="inspector-actions">
                <button class="small-button" onClick={onDuplicate}>Dupliquer</button>
                <button class="small-button danger" onClick={onDelete}>Supprimer</button>
              </div>
              <div class="inspector-primary-toggles">
                <AppleToggle
                  label="Élément actif"
                  detail="Visible dans la Touch Bar"
                  checked={item.enabled !== false}
                  onChange={(enabled) => onChange({ ...item, enabled })}
                />
                {!isSystemUsageGraph && (
                  <AppleToggle
                    label="Bordure"
                    detail="Contour du bouton natif"
                    checked={item.bordered !== false}
                    onChange={(bordered) => onChange({ ...item, bordered })}
                  />
                )}
                {["dock", "pinnedDock"].includes(item.type) && (
                  <AppleToggle
                    label="Largeur automatique"
                    detail="Ajuster le Dock exactement aux icônes"
                    checked={item.autoResize !== false}
                    onChange={(autoResize) => {
                      const next: ItemConfig = { ...item, autoResize };
                      if (autoResize) delete next.width;
                      onChange(next);
                    }}
                  />
                )}
                {item.type === "pinnedDock" && (
                  <AppleToggle
                    label="Indicateur d’exécution"
                    detail="Point blanc sous les apps ouvertes"
                    checked={item.showRunningIndicator !== false}
                    onChange={(showRunningIndicator) => onChange({ ...item, showRunningIndicator })}
                  />
                )}
              </div>
              <InlineDiagnostics diagnostics={diagnosticsAtPath(diagnostics, itemPath, false)} />
              {item.type === "group" && (
                <GroupItemsEditor
                  group={item}
                  schema={schema}
                  onSelect={onSelect}
                  onMoveToGroup={onMoveToGroup}
                  onAddToGroup={onAddToGroup}
                />
              )}
              {item.type === "pinnedDock" && <PinnedDockEditor item={item} onChange={onChange} />}
              <div class="property-list">
                {orderedProperties.map(([name, propertySchema]) => (
                    <PropertyField
                      key={name}
                      name={name}
                      schema={propertySchema}
                      rootSchema={schema}
                      value={item[name]}
                      required={itemSchema?.required?.includes(name) ?? ["id", "type"].includes(name)}
                      diagnostics={diagnosticsAtPath(diagnostics, childPath(itemPath, name))}
                      onChange={(value) => onChange({ ...item, [name]: value })}
                      onUnset={() => {
                        const next = { ...item };
                        delete next[name];
                        onChange(next);
                      }}
                    />
                  ))}
              </div>
              {supportsActions && (
                <ActionsEditor
                  actions={item.actions}
                  schema={schema}
                  diagnostics={diagnostics}
                  path={childPath(itemPath, "actions")}
                  onChange={(actions) => onChange({ ...item, actions })}
                />
              )}
            </fieldset>
          )}
        </div>
      )}
    </aside>
  );
}
