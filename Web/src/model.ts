import type {
  Alignment,
  ConfigDocument,
  Diagnostic,
  ItemConfig,
  JsonObject,
  JsonSchema,
  JsonValue,
} from "./types";

export const ALIGNMENTS: Alignment[] = ["left", "center", "right"];

export const FALLBACK_ITEM_TYPES = [
  { type: "staticButton", label: "Bouton statique", icon: "Aa" },
  { type: "timeButton", label: "Heure", icon: "◷" },
  { type: "battery", label: "Batterie", icon: "▰" },
  { type: "brightness", label: "Luminosité", icon: "☀" },
  { type: "volume", label: "Volume", icon: "◖" },
  { type: "music", label: "Musique", icon: "♫" },
  { type: "inputsource", label: "Source de saisie", icon: "⌨" },
  { type: "weather", label: "Météo", icon: "☁" },
  { type: "currency", label: "Devise", icon: "¤" },
  { type: "group", label: "Groupe", icon: "▣" },
  { type: "swipe", label: "Zone tactile", icon: "↔" },
  { type: "shellScriptTitledButton", label: "Script shell", icon: ">_" },
  { type: "appleScriptTitledButton", label: "AppleScript", icon: "⌘" },
] as const;

export const FALLBACK_ACTION_TYPES = [
  "typeText",
  "keyPress",
  "hidKey",
  "appleScript",
  "shellScript",
  "openUrl",
] as const;

export const ACTION_TRIGGERS = ["singleTap", "doubleTap", "tripleTap", "longTap"] as const;

export const EMPTY_DOCUMENT: ConfigDocument = {
  formatVersion: 1,
  items: [],
};

export function cloneDocument(document: ConfigDocument): ConfigDocument {
  return JSON.parse(JSON.stringify(document)) as ConfigDocument;
}

export function stableSource(document: ConfigDocument): string {
  return `${JSON.stringify(document, null, 2)}\n`;
}

export function parseSource(source: string): { document?: ConfigDocument; diagnostics: Diagnostic[] } {
  try {
    const value = JSON.parse(source) as unknown;
    const diagnostics = validateDocumentShape(value);
    return diagnostics.some((entry) => entry.severity === "error")
      ? { diagnostics }
      : { document: value as ConfigDocument, diagnostics };
  } catch (error) {
    const message = error instanceof Error ? error.message : "JSON invalide";
    const position = /position\s+(\d+)/i.exec(message);
    const offset = position ? Number(position[1]) : undefined;
    const location = offset === undefined ? {} : lineAndColumn(source, offset);
    return {
      diagnostics: [{ severity: "error", message, path: "$", ...location }],
    };
  }
}

function lineAndColumn(source: string, offset: number): { line: number; column: number } {
  const prefix = source.slice(0, offset);
  const lines = prefix.split("\n");
  return { line: lines.length, column: (lines.at(-1)?.length ?? 0) + 1 };
}

export function validateDocumentShape(value: unknown): Diagnostic[] {
  const diagnostics: Diagnostic[] = [];
  if (!isRecord(value)) {
    return [{ severity: "error", message: "La racine doit être un objet JSON.", path: "$" }];
  }
  if (value.formatVersion !== 1) {
    diagnostics.push({
      severity: "error",
      message: "formatVersion doit valoir 1.",
      path: "$.formatVersion",
    });
  }
  if (!Array.isArray(value.items)) {
    diagnostics.push({ severity: "error", message: "items doit être un tableau.", path: "$.items" });
    return diagnostics;
  }
  const ids = new Set<string>();
  value.items.forEach((candidate, index) => {
    const path = `$.items[${index}]`;
    if (!isRecord(candidate)) {
      diagnostics.push({ severity: "error", message: "L’élément doit être un objet.", path });
      return;
    }
    if (typeof candidate.id !== "string" || candidate.id.trim() === "") {
      diagnostics.push({ severity: "error", message: "Un identifiant est requis.", path: `${path}.id` });
    } else if (ids.has(candidate.id)) {
      diagnostics.push({ severity: "error", message: `Identifiant dupliqué : ${candidate.id}`, path: `${path}.id` });
    } else {
      ids.add(candidate.id);
    }
    if (typeof candidate.type !== "string" || candidate.type.trim() === "") {
      diagnostics.push({ severity: "error", message: "Un type est requis.", path: `${path}.type` });
    }
    if (candidate.align !== undefined && !ALIGNMENTS.includes(candidate.align as Alignment)) {
      diagnostics.push({ severity: "error", message: "Alignement inconnu.", path: `${path}.align` });
    }
    if (candidate.actions !== undefined && !Array.isArray(candidate.actions)) {
      diagnostics.push({ severity: "error", message: "actions doit être un tableau.", path: `${path}.actions` });
    }
  });
  return diagnostics;
}

export function createID(prefix = "item"): string {
  const uuid = globalThis.crypto?.randomUUID?.();
  return uuid ? `${prefix}-${uuid}` : `${prefix}-${Date.now()}-${Math.random().toString(36).slice(2, 9)}`;
}

export function createItem(type: string, schema?: JsonSchema): ItemConfig {
  const typeSchema = itemSchemaForType(schema, type);
  const item: ItemConfig = {
    id: createID(type),
    type,
    align: "left",
    enabled: true,
  };
  for (const [key, property] of Object.entries(typeSchema?.properties ?? {})) {
    if (!(key in item) && property.default !== undefined) {
      item[key] = structuredClone(property.default);
    }
  }
  if (type === "staticButton" && item.title === undefined) item.title = "Nouveau";
  return item;
}

export function itemLabel(item: ItemConfig): string {
  if (typeof item.title === "string" && item.title.trim()) return item.title;
  const match = FALLBACK_ITEM_TYPES.find((entry) => entry.type === item.type);
  return match?.label ?? item.type;
}

export function moveItem(
  document: ConfigDocument,
  itemID: string,
  align: Alignment,
  beforeID?: string,
): ConfigDocument {
  const next = cloneDocument(document);
  if (itemID === beforeID) return next;
  const from = next.items.findIndex((item) => item.id === itemID);
  if (from < 0) return next;
  const [item] = next.items.splice(from, 1);
  item.align = align;
  if (beforeID) {
    const target = next.items.findIndex((candidate) => candidate.id === beforeID);
    if (target >= 0) {
      next.items.splice(target, 0, item);
      return next;
    }
  }
  const lastInZone = next.items.reduce(
    (last, candidate, index) => ((candidate.align ?? "left") === align ? index : last),
    -1,
  );
  next.items.splice(lastInZone + 1, 0, item);
  return next;
}

export function addItem(
  document: ConfigDocument,
  item: ItemConfig,
  align: Alignment,
  beforeID?: string,
): ConfigDocument {
  const next = cloneDocument(document);
  item.align = align;
  if (beforeID) {
    const target = next.items.findIndex((candidate) => candidate.id === beforeID);
    if (target >= 0) {
      next.items.splice(target, 0, item);
      return next;
    }
  }
  const lastInZone = next.items.reduce(
    (last, candidate, index) => ((candidate.align ?? "left") === align ? index : last),
    -1,
  );
  next.items.splice(lastInZone + 1, 0, item);
  return next;
}

export function resolveReference(root: JsonSchema | undefined, schema: JsonSchema | undefined): JsonSchema | undefined {
  if (!root || !schema?.$ref || !schema.$ref.startsWith("#/")) return schema;
  let value: unknown = root;
  for (const segment of schema.$ref.slice(2).split("/")) {
    if (!isRecord(value)) return schema;
    value = value[segment.replace(/~1/g, "/").replace(/~0/g, "~")];
  }
  return isRecord(value) ? (value as JsonSchema) : schema;
}

export function itemRootSchema(root?: JsonSchema): JsonSchema | undefined {
  const itemsProperty = root?.properties?.items;
  return resolveReference(root, itemsProperty?.items);
}

export function itemSchemaForType(root: JsonSchema | undefined, type: string): JsonSchema | undefined {
  const itemRoot = itemRootSchema(root);
  if (!itemRoot) return undefined;
  const variants = [...(itemRoot.oneOf ?? []), ...(itemRoot.anyOf ?? [])];
  for (const rawVariant of variants) {
    const variant = resolveReference(root, rawVariant) ?? rawVariant;
    const typeProperty = variant.properties?.type;
    if (typeProperty?.const === type || typeProperty?.enum?.includes(type)) {
      return mergeAllOf(root, variant);
    }
  }
  return mergeAllOf(root, itemRoot);
}

export function actionRootSchema(root?: JsonSchema): JsonSchema | undefined {
  const candidate = root?.$defs?.action ?? root?.definitions?.action;
  return resolveReference(root, candidate);
}

export function actionSchemaForType(root: JsonSchema | undefined, type: string): JsonSchema | undefined {
  const actionRoot = actionRootSchema(root);
  if (!actionRoot) return undefined;
  const variants = [...(actionRoot.oneOf ?? []), ...(actionRoot.anyOf ?? [])];
  for (const rawVariant of variants) {
    const variant = mergeAllOf(root, resolveReference(root, rawVariant) ?? rawVariant);
    const actionProperty = variant.properties?.action;
    if (actionProperty?.const === type || actionProperty?.enum?.includes(type)) return variant;
  }
  return mergeAllOf(root, actionRoot);
}

export function schemaActionTypes(root?: JsonSchema): string[] {
  const discovered = new Set<string>();
  const actionRoot = actionRootSchema(root);
  for (const rawVariant of [...(actionRoot?.oneOf ?? []), ...(actionRoot?.anyOf ?? [])]) {
    const variant = mergeAllOf(root, resolveReference(root, rawVariant) ?? rawVariant);
    const property = variant.properties?.action;
    const values = property?.const !== undefined ? [property.const] : property?.enum ?? [];
    for (const value of values) if (typeof value === "string") discovered.add(value);
  }
  return discovered.size > 0 ? [...discovered] : [...FALLBACK_ACTION_TYPES];
}

export function defaultValueForSchema(
  root: JsonSchema | undefined,
  rawSchema: JsonSchema | undefined,
): JsonValue {
  const schema = resolveReference(root, rawSchema) ?? rawSchema;
  if (schema?.default !== undefined) return structuredClone(schema.default);
  const type = propertyType(schema, undefined);
  if (type === "boolean") return false;
  if (type === "number" || type === "integer") return schema?.minimum ?? 0;
  if (type === "array") return [];
  if (type === "object") {
    const sourceKeys = schema?.properties ? Object.keys(schema.properties) : [];
    if (["filePath", "base64", "inline"].every((key) => sourceKeys.includes(key))) {
      return { inline: "" };
    }
    return {};
  }
  return "";
}

export function mergeAllOf(root: JsonSchema | undefined, schema: JsonSchema): JsonSchema {
  const resolved = resolveReference(root, schema) ?? schema;
  const parts = resolved.allOf ?? [];
  if (parts.length === 0) return resolved;
  return parts.reduce<JsonSchema>(
    (combined, rawPart) => {
      const part = mergeAllOf(root, resolveReference(root, rawPart) ?? rawPart);
      return {
        ...combined,
        ...part,
        properties: { ...(combined.properties ?? {}), ...(part.properties ?? {}) },
        required: Array.from(new Set([...(combined.required ?? []), ...(part.required ?? [])])),
      };
    },
    { ...resolved, allOf: undefined },
  );
}

export function schemaItemTypes(root?: JsonSchema): Array<{ type: string; label: string; icon: string }> {
  const discovered = new Map<string, { type: string; label: string; icon: string }>();
  const itemRoot = itemRootSchema(root);
  for (const rawVariant of [...(itemRoot?.oneOf ?? []), ...(itemRoot?.anyOf ?? [])]) {
    const variant = mergeAllOf(root, resolveReference(root, rawVariant) ?? rawVariant);
    const property = variant.properties?.type;
    const values = property?.const !== undefined ? [property.const] : property?.enum ?? [];
    for (const value of values) {
      if (typeof value !== "string") continue;
      const fallback = FALLBACK_ITEM_TYPES.find((entry) => entry.type === value);
      discovered.set(value, {
        type: value,
        label: variant.title ?? fallback?.label ?? value,
        icon: fallback?.icon ?? "◇",
      });
    }
  }
  if (discovered.size === 0) {
    FALLBACK_ITEM_TYPES.forEach((entry) => discovered.set(entry.type, { ...entry }));
  }
  return [...discovered.values()];
}

export function propertyType(schema: JsonSchema | undefined, value: JsonValue | undefined): string {
  const declared = Array.isArray(schema?.type) ? schema?.type.find((entry) => entry !== "null") : schema?.type;
  if (declared) return declared;
  if (schema?.enum) return "enum";
  if (Array.isArray(value)) return "array";
  if (value === null) return "null";
  return typeof value;
}

export function isRecord(value: unknown): value is JsonObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
