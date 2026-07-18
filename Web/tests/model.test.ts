import { describe, expect, it } from "vitest";
import {
  addItem,
  createItem,
  moveItem,
  parseSource,
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
    expect(schemaItemTypes(schema)).toContainEqual({ type: "testButton", label: "Bouton test", icon: "◇" });
    expect(addItem({ formatVersion: 1, items: [] }, item, "center").items[0].align).toBe("center");
  });
});
