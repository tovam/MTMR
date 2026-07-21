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

export interface PaletteItemPresentation {
  type: string;
  label: string;
  icon: string;
  description: string;
  examples: readonly string[];
}

export const FALLBACK_ITEM_TYPES: readonly PaletteItemPresentation[] = [
  { type: "staticButton", label: "Bouton statique", icon: "Aa", description: "Affiche un libellé fixe et déclenche une ou plusieurs actions. Idéal pour saisir un caractère ou lancer une commande.", examples: ["ž / Ž", "Ouvrir une URL", "Raccourci"] },
  { type: "appleScriptTitledButton", label: "AppleScript", icon: "⌘", description: "Exécute périodiquement un AppleScript pour afficher une information ou un état. Le script reste exécuté par MMTMR, jamais par l’aperçu web.", examples: ["État d’une app", "Texte dynamique"] },
  { type: "shellScriptTitledButton", label: "Titre Shell", icon: ">_", description: "Calcule périodiquement le titre avec un script shell. Pratique pour une information locale courte.", examples: ["Branche Git", "Statut service"] },
  { type: "timeButton", label: "Heure", icon: "◷", description: "Affiche l’heure selon un format, un fuseau et une locale. L’aperçu direct reprend la valeur fournie par MMTMR.", examples: ["14:32", "sam. 18", "UTC"] },
  { type: "battery", label: "Batterie", icon: "▰", description: "Affiche le niveau et l’état de la batterie du Mac. La valeur réelle arrive par le mode Direct.", examples: ["82 %", "En charge"] },
  { type: "cpu", label: "Utilisation CPU", icon: "CPU▥", description: "Mini-historique carré du processeur : chaque colonne d’un pixel représente une mesure et le graphique avance vers la gauche.", examples: ["Historique CPU", "1 colonne / mesure"] },
  { type: "memory", label: "Utilisation RAM", icon: "RAM▥", description: "Le même mini-historique pour la mémoire occupée, sans texte ni décoration. Le cache récupérable est considéré disponible.", examples: ["Historique RAM", "1 colonne / mesure"] },
  { type: "dock", label: "Applications", icon: "▦", description: "Présente les applications actives sous forme de Dock tactile. Les icônes exactes nécessitent le rendu Direct de MMTMR.", examples: ["Finder", "Safari", "Terminal"] },
  { type: "pinnedDock", label: "Dock fixe", icon: "▣", description: "Affiche exactement les applications choisies, dans un ordre fixe, qu’elles soient ouvertes ou fermées. Un toucher active ou lance l’application.", examples: ["Finder + Firefox", "Terminal + Notes", "Apps de travail"] },
  { type: "volume", label: "Volume", icon: "◖", description: "Ajoute le contrôle interactif du volume système. Ce composant gère lui-même ses gestes.", examples: ["Curseur audio", "Muet"] },
  { type: "brightness", label: "Luminosité", icon: "☀", description: "Ajoute le contrôle interactif de luminosité. Une image personnalisée peut remplacer le symbole.", examples: ["Curseur écran", "☀"] },
  { type: "weather", label: "Météo", icon: "☁", description: "Affiche la météo depuis le fournisseur configuré. Une clé API et les unités peuvent être précisées.", examples: ["☀ 24°", "☂ 12°"] },
  { type: "yandexWeather", label: "Météo Yandex", icon: "☂", description: "Affiche la météo issue de Yandex. Le contenu se met à jour selon l’intervalle choisi.", examples: ["Nuageux 17°", "Pluie"] },
  { type: "currency", label: "Devise", icon: "€", description: "Convertit et affiche une paire de devises. Le mode complet ajoute davantage de détail.", examples: ["EUR → USD", "GBP → EUR"] },
  { type: "inputsource", label: "Source de saisie", icon: "⌨", description: "Affiche la source de saisie active. Utile pour repérer immédiatement la langue du clavier.", examples: ["ABC", "FR", "RU"] },
  { type: "music", label: "Musique", icon: "♫", description: "Affiche le média en cours de lecture. Le texte peut défiler lorsque le titre est long.", examples: ["♫ Lecture", "Artiste — titre"] },
  { type: "group", label: "Groupe", icon: "⧉", description: "Crée un bouton qui ouvre une sous-barre sur la Touch Bar physique. Les composants rangés dedans quittent la barre principale.", examples: ["Transport", "Système"] },
  { type: "nightShift", label: "Night Shift", icon: "◐", description: "Active ou désactive Night Shift. L’état exact est fourni par macOS.", examples: ["Activé", "Désactivé"] },
  { type: "dnd", label: "Ne pas déranger", icon: "☾", description: "Bascule le mode Ne pas déranger. Le bouton reflète l’état système lorsque disponible.", examples: ["Concentration", "Silence"] },
  { type: "pomodoro", label: "Pomodoro", icon: "◴", description: "Lance une alternance travail et repos. Les deux durées sont configurables.", examples: ["25 min", "5 min"] },
  { type: "network", label: "Réseau", icon: "⇅", description: "Affiche le débit réseau montant et descendant. Les unités peuvent être dynamiques, en octets ou en bits.", examples: ["↓ 4,2 Mo/s", "↑ 320 Ko/s"] },
  { type: "darkMode", label: "Mode sombre", icon: "◑", description: "Bascule l’apparence claire ou sombre de macOS. L’aperçu Direct suit le thème courant.", examples: ["Clair", "Sombre"] },
  { type: "swipe", label: "Zone tactile", icon: "↔", description: "Déclenche un script après un balayage de plusieurs doigts. La zone elle-même reste visuellement discrète.", examples: ["2 doigts →", "3 doigts ←"] },
  { type: "upnext", label: "Événements à venir", icon: "◳", description: "Affiche les prochains événements du calendrier. La fenêtre temporelle et le nombre de résultats sont réglables.", examples: ["Réunion 15:00", "Demain 09:30"] },
  { type: "escape", label: "Échap", icon: "esc", description: "Envoie la touche Échap. C’est le remplacement classique de la touche physique.", examples: ["Esc"] },
  { type: "delete", label: "Supprimer", icon: "⌫", description: "Envoie la touche de suppression arrière. Peut être placé où il reste facilement accessible.", examples: ["⌫"] },
  { type: "brightnessUp", label: "Luminosité +", icon: "☀↑", description: "Augmente la luminosité de l’écran d’un cran. L’action est native et immédiate.", examples: ["Écran +"] },
  { type: "brightnessDown", label: "Luminosité −", icon: "☀↓", description: "Diminue la luminosité de l’écran d’un cran. L’action est native et immédiate.", examples: ["Écran −"] },
  { type: "illuminationUp", label: "Rétroéclairage +", icon: "✦↑", description: "Augmente le rétroéclairage du clavier. Disponible selon le matériel.", examples: ["Clavier +"] },
  { type: "illuminationDown", label: "Rétroéclairage −", icon: "✦↓", description: "Diminue le rétroéclairage du clavier. Disponible selon le matériel.", examples: ["Clavier −"] },
  { type: "volumeDown", label: "Volume −", icon: "🔉", description: "Baisse le volume système d’un cran. Le symbole est distinct du contrôle continu de volume.", examples: ["Son −"] },
  { type: "volumeUp", label: "Volume +", icon: "🔊", description: "Augmente le volume système d’un cran. Le symbole est distinct du contrôle continu de volume.", examples: ["Son +"] },
  { type: "mute", label: "Muet", icon: "🔇", description: "Active ou désactive la sortie audio. L’action utilise la touche média native.", examples: ["Couper le son"] },
  { type: "previous", label: "Précédent", icon: "◀|", description: "Revient à la piste ou au chapitre précédent. Fonctionne avec les applications multimédia compatibles.", examples: ["Piste précédente"] },
  { type: "play", label: "Lecture / pause", icon: "▶", description: "Bascule entre lecture et pause. Fonctionne avec les applications multimédia compatibles.", examples: ["Lecture", "Pause"] },
  { type: "next", label: "Suivant", icon: "|▶", description: "Passe à la piste ou au chapitre suivant. Fonctionne avec les applications multimédia compatibles.", examples: ["Piste suivante"] },
  { type: "sleep", label: "Veille", icon: "zZ", description: "Place le Mac en veille. À réserver à une zone qui évite les appuis accidentels.", examples: ["Veille Mac"] },
  { type: "displaySleep", label: "Éteindre l’écran", icon: "▰z", description: "Met uniquement les écrans en veille. Le Mac continue de fonctionner.", examples: ["Écran en veille"] },
  { type: "exitTouchbar", label: "Quitter la Touch Bar", icon: "⏏", description: "Ferme la barre modale MMTMR. Utile comme contrôle de sortie permanent.", examples: ["Quitter"] },
  { type: "close", label: "Fermer", icon: "×", description: "Ferme la barre ou la vue courante selon le contexte. Le comportement est fourni par MMTMR.", examples: ["Fermer"] },
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
  const validateItems = (items: unknown[], itemsPath: string) => items.forEach((candidate, index) => {
    const path = `${itemsPath}[${index}]`;
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
    if (candidate.type === "pinnedDock") {
      if (!Array.isArray(candidate.applications)) {
        diagnostics.push({ severity: "error", message: "applications doit être un tableau.", path: `${path}.applications` });
      } else {
        const applicationIDs = new Set<string>();
        candidate.applications.forEach((application, applicationIndex) => {
          const applicationPath = `${path}.applications[${applicationIndex}]`;
          if (!isRecord(application)) {
            diagnostics.push({ severity: "error", message: "L’application doit être un objet.", path: applicationPath });
            return;
          }
          if (typeof application.bundleIdentifier !== "string" || application.bundleIdentifier.trim() === "") {
            diagnostics.push({ severity: "error", message: "Un identifiant de bundle est requis.", path: `${applicationPath}.bundleIdentifier` });
          } else if (applicationIDs.has(application.bundleIdentifier)) {
            diagnostics.push({ severity: "error", message: `Application dupliquée : ${application.bundleIdentifier}`, path: `${applicationPath}.bundleIdentifier` });
          } else {
            applicationIDs.add(application.bundleIdentifier);
          }
        });
      }
    }
    if (candidate.items !== undefined) {
      if (Array.isArray(candidate.items)) validateItems(candidate.items, `${path}.items`);
      else diagnostics.push({ severity: "error", message: "items doit être un tableau.", path: `${path}.items` });
    }
  });
  validateItems(value.items, "$.items");
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
  if (type === "group") {
    if (item.title === undefined) item.title = "Groupe";
    if (item.items === undefined) item.items = [];
  }
  if (type === "pinnedDock") {
    if (item.applications === undefined) item.applications = [];
    if (item.autoResize === undefined) item.autoResize = true;
    if (item.showRunningIndicator === undefined) item.showRunningIndicator = true;
    if (item.longPressAction === undefined) item.longPressAction = "quit";
    if (item.spacing === undefined) item.spacing = 1;
  }
  if (type === "cpu" || type === "memory") {
    if (item.refreshInterval === undefined) item.refreshInterval = 2;
    delete item.bordered;
  }
  if (item.editorName === undefined && typeSchema?.properties?.editorName !== undefined) {
    item.editorName = FALLBACK_ITEM_TYPES.find((entry) => entry.type === type)?.label ?? type;
  }
  return item;
}

export function itemLabel(item: ItemConfig): string {
  if (typeof item.title === "string" && item.title.trim()) return item.title;
  const match = FALLBACK_ITEM_TYPES.find((entry) => entry.type === item.type);
  return match?.label ?? item.type;
}

export function itemEditorName(item: ItemConfig): string {
  if (typeof item.editorName === "string" && item.editorName.trim()) return item.editorName;
  return itemLabel(item);
}

export function itemPresentation(type: string): PaletteItemPresentation {
  return FALLBACK_ITEM_TYPES.find((entry) => entry.type === type) ?? {
    type,
    label: type,
    icon: "•",
    description: "Composant déclaré par le schéma MMTMR. Ses réglages sont disponibles dans l’inspecteur.",
    examples: [type],
  };
}

export interface ItemTreeLocation {
  item: ItemConfig;
  parent?: ItemConfig;
  index: number;
  indices: number[];
}

function childItems(item: ItemConfig): ItemConfig[] {
  return Array.isArray(item.items) ? item.items : [];
}

function findInItems(
  items: ItemConfig[],
  itemID: string,
  parent: ItemConfig | undefined,
  indices: number[],
): ItemTreeLocation | undefined {
  for (let index = 0; index < items.length; index += 1) {
    const item = items[index];
    const nextIndices = [...indices, index];
    if (item.id === itemID) return { item, parent, index, indices: nextIndices };
    const nested = findInItems(childItems(item), itemID, item, nextIndices);
    if (nested) return nested;
  }
  return undefined;
}

export function findItemLocation(document: ConfigDocument, itemID: string | undefined): ItemTreeLocation | undefined {
  return itemID ? findInItems(document.items, itemID, undefined, []) : undefined;
}

export function findItem(document: ConfigDocument, itemID: string | undefined): ItemConfig | undefined {
  return findItemLocation(document, itemID)?.item;
}

export function itemPath(document: ConfigDocument, itemID: string | undefined): string | undefined {
  const location = findItemLocation(document, itemID);
  if (!location) return undefined;
  return location.indices.reduce(
    (path, index, depth) => `${path}${depth === 0 ? "" : ".items"}[${index}]`,
    "$.items",
  );
}

export function itemAncestors(document: ConfigDocument, itemID: string | undefined): ItemConfig[] {
  const location = findItemLocation(document, itemID);
  if (!location || location.indices.length < 2) return [];
  const ancestors: ItemConfig[] = [];
  let items = document.items;
  for (const index of location.indices.slice(0, -1)) {
    const item = items[index];
    if (!item) break;
    ancestors.push(item);
    items = childItems(item);
  }
  return ancestors;
}

export function flattenItems(items: ItemConfig[]): ItemConfig[] {
  return items.flatMap((item) => [item, ...flattenItems(childItems(item))]);
}

function mutableLocation(
  items: ItemConfig[],
  itemID: string,
): { item: ItemConfig; collection: ItemConfig[]; index: number } | undefined {
  for (let index = 0; index < items.length; index += 1) {
    const item = items[index];
    if (item.id === itemID) return { item, collection: items, index };
    const nested = mutableLocation(childItems(item), itemID);
    if (nested) return nested;
  }
  return undefined;
}

function insertAligned(
  collection: ItemConfig[],
  item: ItemConfig,
  align: Alignment,
  beforeID?: string,
) {
  item.align = align;
  if (beforeID) {
    const target = collection.findIndex((candidate) => candidate.id === beforeID);
    if (target >= 0) {
      collection.splice(target, 0, item);
      return;
    }
  }
  const lastInZone = collection.reduce(
    (last, candidate, index) => ((candidate.align ?? "left") === align ? index : last),
    -1,
  );
  collection.splice(lastInZone + 1, 0, item);
}

function containsItem(item: ItemConfig, itemID: string): boolean {
  return item.id === itemID || childItems(item).some((child) => containsItem(child, itemID));
}

export function moveItem(
  document: ConfigDocument,
  itemID: string,
  align: Alignment,
  beforeID?: string,
): ConfigDocument {
  const next = cloneDocument(document);
  if (itemID === beforeID) return next;
  const source = mutableLocation(next.items, itemID);
  if (!source) return next;
  const [item] = source.collection.splice(source.index, 1);
  insertAligned(next.items, item, align, beforeID);
  return next;
}

/**
 * Reorders an item inside its current source array without changing its
 * alignment or moving it into/out of a group. `beforeID` must identify a
 * sibling; omitting it moves the item to the end of its current array.
 */
export function reorderItem(
  document: ConfigDocument,
  itemID: string,
  beforeID?: string,
): ConfigDocument {
  const next = cloneDocument(document);
  if (itemID === beforeID) return next;
  const source = mutableLocation(next.items, itemID);
  if (!source) return next;

  if (beforeID) {
    const target = mutableLocation(next.items, beforeID);
    if (!target || target.collection !== source.collection) return next;
  }

  const [item] = source.collection.splice(source.index, 1);
  const insertionIndex = beforeID
    ? source.collection.findIndex((candidate) => candidate.id === beforeID)
    : source.collection.length;
  source.collection.splice(insertionIndex < 0 ? source.collection.length : insertionIndex, 0, item);
  return next;
}

export function addItem(
  document: ConfigDocument,
  item: ItemConfig,
  align: Alignment,
  beforeID?: string,
): ConfigDocument {
  const next = cloneDocument(document);
  insertAligned(next.items, structuredClone(item), align, beforeID);
  return next;
}

export function addItemToGroup(
  document: ConfigDocument,
  item: ItemConfig,
  groupID: string,
  align: Alignment = "left",
  beforeID?: string,
): ConfigDocument {
  const next = cloneDocument(document);
  const target = mutableLocation(next.items, groupID)?.item;
  if (!target || target.type !== "group") return next;
  if (!Array.isArray(target.items)) target.items = [];
  insertAligned(target.items, structuredClone(item), align, beforeID);
  return next;
}

export function moveItemToGroup(
  document: ConfigDocument,
  itemID: string,
  groupID: string,
  align?: Alignment,
  beforeID?: string,
): ConfigDocument {
  const next = cloneDocument(document);
  if (itemID === groupID || itemID === beforeID) return next;
  const source = mutableLocation(next.items, itemID);
  if (!source || containsItem(source.item, groupID)) return next;
  const preservedAlign = source.item.align ?? "left";
  const [item] = source.collection.splice(source.index, 1);
  const target = mutableLocation(next.items, groupID)?.item;
  if (!target || target.type !== "group") return cloneDocument(document);
  if (!Array.isArray(target.items)) target.items = [];
  insertAligned(target.items, item, align ?? preservedAlign, beforeID);
  return next;
}

export function updateItem(document: ConfigDocument, replacement: ItemConfig): ConfigDocument {
  const next = cloneDocument(document);
  const location = mutableLocation(next.items, replacement.id);
  if (location) location.collection[location.index] = structuredClone(replacement);
  return next;
}

export function removeItem(document: ConfigDocument, itemID: string): ConfigDocument {
  const next = cloneDocument(document);
  const location = mutableLocation(next.items, itemID);
  if (location) location.collection.splice(location.index, 1);
  return next;
}

function cloneItemWithFreshIDs(item: ItemConfig): ItemConfig {
  const copy = structuredClone(item);
  copy.id = createID(copy.type);
  if (typeof copy.editorName === "string" && copy.editorName) copy.editorName = `${copy.editorName} copie`;
  if (typeof copy.title === "string" && copy.title) copy.title = `${copy.title} copie`;
  if (Array.isArray(copy.items)) copy.items = copy.items.map(cloneItemWithFreshIDs);
  return copy;
}

export function duplicateItem(
  document: ConfigDocument,
  itemID: string,
): { document: ConfigDocument; item?: ItemConfig } {
  const next = cloneDocument(document);
  const location = mutableLocation(next.items, itemID);
  if (!location) return { document: next };
  const copy = cloneItemWithFreshIDs(location.item);
  location.collection.splice(location.index + 1, 0, copy);
  return { document: next, item: copy };
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

export function schemaItemTypes(root?: JsonSchema): PaletteItemPresentation[] {
  const discovered = new Map<string, PaletteItemPresentation>();
  const itemRoot = itemRootSchema(root);
  for (const rawVariant of [...(itemRoot?.oneOf ?? []), ...(itemRoot?.anyOf ?? [])]) {
    const variant = mergeAllOf(root, resolveReference(root, rawVariant) ?? rawVariant);
    const property = variant.properties?.type;
    const values = property?.const !== undefined ? [property.const] : property?.enum ?? [];
    for (const value of values) {
      if (typeof value !== "string") continue;
      const known = FALLBACK_ITEM_TYPES.find((entry) => entry.type === value);
      const fallback = known ?? itemPresentation(value);
      discovered.set(value, {
        type: value,
        label: known?.label ?? variant.title ?? value,
        icon: fallback.icon,
        description: fallback.description || variant.description || `Composant ${variant.title ?? value}.`,
        examples: fallback.examples,
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
