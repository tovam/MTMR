import { describe, expect, it } from "vitest";
import {
  addItem,
  addItemToGroup,
  createItem,
  duplicateItem,
  moveItem,
  moveItemToGroup,
  parseSource,
  reorderItem,
  schemaItemTypes,
  stableSource,
} from "../src/model";
import type { ConfigDocument, JsonSchema } from "../src/types";

describe("modèle de configuration", () => {
  it("sérialise du JSON strict avec indentation et retour final", () => {
    const source = stableSource({ formatVersion: 1, notes: "UTF-8 ž", items: [] });
    expect(source).toBe('{\n  "formatVersion": 1,\n  "notes": "UTF-8 ž",\n  "items": []\n}\n');
    expect(JSON.parse(source)).toMatchObject({ formatVersion: 1, notes: "UTF-8 ž" });
  });

  it("garde un JSON brut invalide sous forme de diagnostic", () => {
    const result = parseSource('{ "formatVersion": 1, "items": [ }');
    expect(result.document).toBeUndefined();
    expect(result.diagnostics[0]).toMatchObject({ severity: "error" });
  });

  it("refuse les identifiants dupliqués avant l’enregistrement", () => {
    const result = parseSource(JSON.stringify({
      formatVersion: 1,
      items: [
        { id: "same", type: "staticButton" },
        { id: "same", type: "staticButton" },
      ],
    }));
    expect(result.document).toBeUndefined();
    expect(result.diagnostics.some((entry) => entry.message.includes("dupliqué"))).toBe(true);
  });

  it("refuse aussi un identifiant dupliqué au fond d’un groupe", () => {
    const result = parseSource(JSON.stringify({
      formatVersion: 1,
      items: [
        { id: "same", type: "staticButton" },
        { id: "group", type: "group", items: [{ id: "same", type: "play" }] },
      ],
    }));
    expect(result.document).toBeUndefined();
    expect(result.diagnostics).toContainEqual(expect.objectContaining({
      path: "$.items[1].items[0].id",
    }));
  });

  it("déplace les éléments et met à jour leur alignement", () => {
    const document: ConfigDocument = {
      formatVersion: 1,
      items: [
        { id: "a", type: "staticButton", align: "left" },
        { id: "b", type: "staticButton", align: "right" },
      ],
    };
    const result = moveItem(document, "a", "right", "b");
    expect(result.items.map((item) => item.id)).toEqual(["a", "b"]);
    expect(result.items[0].align).toBe("right");
    expect(document.items[0].align).toBe("left");
  });

  it("réordonne la source sans changer l’alignement ni le niveau d’imbrication", () => {
    const document: ConfigDocument = {
      formatVersion: 1,
      items: [
        { id: "a", type: "staticButton", align: "left" },
        { id: "b", type: "staticButton", align: "right" },
        { id: "group", type: "group", items: [
          { id: "c", type: "volumeDown", align: "left" },
          { id: "d", type: "volumeUp", align: "right" },
        ] },
      ],
    };

    const root = reorderItem(document, "b", "a");
    expect(root.items.map((item) => item.id)).toEqual(["b", "a", "group"]);
    expect(root.items[0].align).toBe("right");

    const nested = reorderItem(root, "d", "c");
    expect(nested.items[2].items?.map((item) => item.id)).toEqual(["d", "c"]);
    expect(nested.items[2].items?.[0].align).toBe("right");
    expect(document.items.map((item) => item.id)).toEqual(["a", "b", "group"]);

    const refusedCrossLevel = reorderItem(nested, "c", "a");
    expect(refusedCrossLevel).toEqual(nested);
  });

  it("ajoute et déplace réellement des éléments dans un groupe", () => {
    const document: ConfigDocument = {
      formatVersion: 1,
      items: [
        { id: "group", type: "group", align: "left", items: [] },
        { id: "sound", type: "volumeUp", align: "right" },
      ],
    };
    const added = addItemToGroup(document, { id: "light", type: "brightnessUp" }, "group", "center");
    const moved = moveItemToGroup(added, "sound", "group", "right");
    expect(moved.items.map((item) => item.id)).toEqual(["group"]);
    expect(moved.items[0].items).toEqual(expect.arrayContaining([
      expect.objectContaining({ id: "light", align: "center" }),
      expect.objectContaining({ id: "sound", align: "right" }),
    ]));

    const extracted = moveItem(moved, "light", "left");
    expect(extracted.items.map((item) => item.id)).toEqual(["group", "light"]);
    expect(extracted.items[0].items).toEqual([expect.objectContaining({ id: "sound" })]);
    expect(document.items[0].items).toEqual([]);
  });

  it("duplique un groupe avec de nouveaux identifiants pour tout le sous-arbre", () => {
    const document: ConfigDocument = {
      formatVersion: 1,
      items: [{
        id: "group",
        type: "group",
        items: [{ id: "child", type: "staticButton", title: "ž" }],
      }],
    };
    const result = duplicateItem(document, "group");
    expect(result.document.items).toHaveLength(2);
    expect(result.item?.id).not.toBe("group");
    expect(result.item?.items?.[0].id).not.toBe("child");
    expect(document.items).toHaveLength(1);
  });

  it("crée un élément depuis les valeurs par défaut du schéma", () => {
    const schema: JsonSchema = {
      type: "object",
      properties: {
        items: {
          type: "array",
          items: {
            oneOf: [{
              title: "Bouton test",
              type: "object",
              properties: {
                type: { const: "testButton" },
                width: { type: "number", default: 42 },
              },
            }],
          },
        },
      },
    };
    const item = createItem("testButton", schema);
    expect(item).toMatchObject({ type: "testButton", align: "left", enabled: true, width: 42 });
    expect(schemaItemTypes(schema)).toContainEqual(expect.objectContaining({ type: "testButton", label: "Bouton test", icon: "•" }));
    expect(item).not.toHaveProperty("editorName");
    expect(addItem({ formatVersion: 1, items: [] }, item, "center").items[0].align).toBe("center");
  });

  it("initialise un groupe vide prêt à recevoir des composants", () => {
    expect(createItem("group")).toMatchObject({ type: "group", title: "Groupe", items: [] });
  });

  it("crée un Dock ajusté à ses icônes par défaut", () => {
    const schema: JsonSchema = {
      properties: {
        items: {
          items: {
            oneOf: [{
              properties: {
                type: { const: "dock" },
                autoResize: { type: "boolean", default: true },
              },
            }],
          },
        },
      },
    };

    expect(createItem("dock", schema)).toMatchObject({ type: "dock", autoResize: true });
  });

  it("n’ajoute editorName que lorsque le schéma du binaire le permet", () => {
    const oldSchema: JsonSchema = {
      properties: { items: { items: { oneOf: [{ properties: { type: { const: "staticButton" } } }] } } },
    };
    const newSchema: JsonSchema = {
      properties: { items: { items: { oneOf: [{ properties: { type: { const: "staticButton" }, editorName: { type: "string" } } }] } } },
    };
    expect(createItem("staticButton", oldSchema)).not.toHaveProperty("editorName");
    expect(createItem("staticButton", newSchema)).toMatchObject({ editorName: "Bouton statique" });
  });

  it("déclare les 38 composants avec des libellés français et des icônes distinctes", () => {
    const entries = schemaItemTypes();
    expect(entries).toHaveLength(38);
    expect(entries.find((entry) => entry.type === "volumeUp")).toMatchObject({ label: "Volume +", icon: "🔊" });
    expect(entries.find((entry) => entry.type === "volumeDown")).toMatchObject({ label: "Volume −", icon: "🔉" });
    expect(entries.every((entry) => entry.icon !== "◇" && entry.description.length > 0 && entry.examples.length > 0)).toBe(true);
    expect(new Set(entries.map((entry) => entry.icon)).size).toBe(38);
  });
});
