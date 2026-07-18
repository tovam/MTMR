import { useEffect, useMemo, useState } from "preact/hooks";
import {
  ACTION_TRIGGERS,
  actionSchemaForType,
  defaultValueForSchema,
  itemEditorName,
  itemSchemaForType,
  propertyType,
  resolveReference,
  schemaActionTypes,
} from "../model";
import type { ActionConfig, Diagnostic, ItemConfig, JsonObject, JsonSchema, JsonValue } from "../types";

interface InspectorProps {
  item?: ItemConfig;
  itemPath?: string;
  schema?: JsonSchema;
  diagnostics?: Diagnostic[];
  editingLocked?: boolean;
  collapsed: boolean;
  onToggle(): void;
  onChange(item: ItemConfig): void;
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

export function Inspector({
  item,
  itemPath,
  schema,
  diagnostics = [],
  editingLocked = false,
  collapsed,
  onToggle,
  onChange,
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
  const supportsActions = schema ? itemSchema?.properties?.actions !== undefined : true;
  const orderedProperties = useMemo(() => {
    const preferred = [
      "editorName", "title", "notes", "align", "width", "image", "background", "matchAppId",
      "source", "refreshInterval", "formatTemplate", "timeZone", "locale", "alternativeImages",
      "autoResize", "filter", "units", "api_key", "icon_type", "from", "to", "full",
      "disableMarquee", "items", "workTime", "restTime", "flip", "direction", "fingers",
      "minOffset", "sourceApple", "sourceBash", "maxToShow", "id", "type",
    ];
    const rank = new Map(preferred.map((name, index) => [name, index]));
    return Object.entries(properties)
      .filter(([name]) => !["actions", "enabled", "bordered"].includes(name))
      .sort(([left], [right]) => (rank.get(left) ?? 1_000) - (rank.get(right) ?? 1_000));
  }, [properties]);

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
                <AppleToggle
                  label="Bordure"
                  detail="Contour du bouton natif"
                  checked={item.bordered !== false}
                  onChange={(bordered) => onChange({ ...item, bordered })}
                />
              </div>
              <InlineDiagnostics diagnostics={diagnosticsAtPath(diagnostics, itemPath, false)} />
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
