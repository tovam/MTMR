import { cleanup, render, screen } from "@testing-library/preact";
import { afterEach, describe, expect, it, vi } from "vitest";
import { Inspector } from "../src/components/Inspector";
import type { ItemConfig, JsonSchema } from "../src/types";

const systemUsageSchema: JsonSchema = {
  properties: {
    items: {
      items: {
        oneOf: ["cpu", "memory"].map((type) => ({
          properties: {
            id: { type: "string" },
            type: { const: type },
            enabled: { type: "boolean", default: true },
            refreshInterval: { type: "number", default: 2 },
            bordered: { type: "boolean" },
            actions: { type: "array", items: {} },
          },
        })),
      },
    },
  },
};

function renderGraph(item: ItemConfig) {
  render(
    <Inspector
      item={item}
      schema={systemUsageSchema}
      collapsed={false}
      onToggle={vi.fn()}
      onChange={vi.fn()}
      onSelect={vi.fn()}
      onMoveToGroup={vi.fn()}
      onAddToGroup={vi.fn()}
      onDuplicate={vi.fn()}
      onDelete={vi.fn()}
    />,
  );
}

describe("Inspector system usage compatibility", () => {
  afterEach(cleanup);

  for (const type of ["cpu", "memory"]) {
    it(`masque les anciens champs ignorés pour ${type}`, () => {
      renderGraph({ id: type, type, bordered: true, actions: [] });

      expect(screen.getByRole("switch", { name: /Élément actif/ })).toBeInTheDocument();
      expect(screen.queryByRole("switch", { name: /Bordure/ })).not.toBeInTheDocument();
      expect(screen.queryByText("Actions")).not.toBeInTheDocument();
      expect(screen.queryByLabelText("Titre")).not.toBeInTheDocument();
      expect(screen.queryByLabelText("Largeur")).not.toBeInTheDocument();
    });
  }
});
