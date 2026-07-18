import { cleanup, fireEvent, render, screen, waitFor, within } from "@testing-library/preact";
import userEvent from "@testing-library/user-event";
import { EditorView } from "@codemirror/view";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { App } from "../src/App";

const config = {
  formatVersion: 1,
  items: [{
    id: "hello",
    type: "staticButton",
    title: "Bonjour",
    align: "left",
    enabled: true,
    actions: [{ trigger: "singleTap", action: "typeText", text: "ž" }],
  }],
};

const schema = {
  type: "object",
  properties: {
    items: {
      type: "array",
      items: {
        oneOf: [
          {
            title: "Bouton statique",
            type: "object",
            properties: {
              id: { type: "string", readOnly: true },
              type: { const: "staticButton" },
              title: { type: "string" },
              align: { type: "string", enum: ["left", "center", "right"] },
              enabled: { type: "boolean", default: true },
              actions: { type: "array", items: { $ref: "#/$defs/action" } },
            },
            required: ["id", "type"],
          },
          {
            title: "Groupe",
            type: "object",
            properties: {
              id: { type: "string", readOnly: true },
              type: { const: "group" },
              align: { type: "string", enum: ["left", "center", "right"] },
              enabled: { type: "boolean", default: true },
              items: { type: "array", items: { $ref: "#/properties/items/items" } },
            },
            required: ["id", "type", "items"],
          },
        ],
      },
    },
  },
  $defs: {
    source: {
      type: "object",
      properties: {
        inline: { type: "string" },
        filePath: { type: "string" },
        base64: { type: "string" },
      },
    },
    action: {
      oneOf: [
        {
          title: "Saisir du texte",
          type: "object",
          properties: {
            trigger: { type: "string", enum: ["singleTap", "doubleTap", "tripleTap", "longTap"], default: "singleTap" },
            action: { const: "typeText" },
            text: { type: "string" },
          },
          required: ["trigger", "action", "text"],
        },
        {
          title: "Script shell",
          type: "object",
          properties: {
            trigger: { type: "string", enum: ["singleTap", "doubleTap", "tripleTap", "longTap"], default: "singleTap" },
            action: { const: "shellScript" },
            executablePath: { type: "string" },
            shellArguments: { type: "array", default: [] },
          },
          required: ["trigger", "action", "executablePath"],
        },
      ],
    },
  },
};

function jsonResponse(value: unknown, status = 200) {
  return new Response(JSON.stringify(value), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

class MockWebSocket extends EventTarget {
  static OPEN = 1;
  static instances: MockWebSocket[] = [];
  readyState = MockWebSocket.OPEN;
  constructor(_url: string) {
    super();
    MockWebSocket.instances.push(this);
    queueMicrotask(() => this.dispatchEvent(new Event("open")));
  }
  sendEvent(value: unknown) {
    this.dispatchEvent(new MessageEvent("message", { data: JSON.stringify(value) }));
  }
  close() { this.dispatchEvent(new Event("close")); }
}

function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((fulfill) => { resolve = fulfill; });
  return { promise, resolve };
}

describe("éditeur MMTMR", () => {
  beforeEach(() => {
    MockWebSocket.instances = [];
    vi.stubGlobal("WebSocket", MockWebSocket);
    vi.stubGlobal("fetch", vi.fn(async (input: string | URL | Request, init?: RequestInit) => {
      const url = String(input);
      if (url.endsWith("/session")) return jsonResponse({ ok: true });
      if (url.endsWith("/status")) return jsonResponse({ version: "1.0", port: 8787, configPath: "/Users/test/.mtmr.json", revision: 4, valid: true });
      if (url.endsWith("/schema")) return jsonResponse(schema);
      if (url.endsWith("/validate")) {
        const source = JSON.parse(String(init?.body)).source as string;
        return jsonResponse({ valid: true, document: JSON.parse(source), diagnostics: [] });
      }
      if (url.endsWith("/preview/context")) return jsonResponse({ context: JSON.parse(String(init?.body)) });
      if (url.endsWith("/preview/action")) return jsonResponse({ executed: false, description: "La lettre ž serait saisie." });
      if (url.endsWith("/config") && init?.method === "PUT") {
        const source = JSON.parse(String(init.body)).source as string;
        return jsonResponse({ source, document: JSON.parse(source), revision: 5, diagnostics: [], valid: true });
      }
      return jsonResponse({ source: `${JSON.stringify(config, null, 2)}\n`, document: config, revision: 4, diagnostics: [], valid: true });
    }));
  });

  afterEach(() => {
    cleanup();
    vi.unstubAllGlobals();
  });

  it("affiche le shell et la configuration reçue", async () => {
    render(<App />);
    expect(screen.getByText("MMTMR")).toBeInTheDocument();
    expect(await screen.findByRole("button", { name: "Bonjour" })).toBeInTheDocument();
    expect(screen.getByText("/Users/test/.mtmr.json")).toBeInTheDocument();
    await waitFor(() => expect(screen.getByText("Connecté")).toBeInTheDocument());
  });

  it("établit la session locale avant de charger l’API", async () => {
    render(<App />);
    await screen.findByRole("button", { name: "Bonjour" });
    expect(String(vi.mocked(fetch).mock.calls[0][0])).toMatch(/\/api\/v1\/session$/);
  });

  it("sélectionne un élément et expose son action Unicode dans l’inspecteur", async () => {
    const user = userEvent.setup();
    render(<App />);
    await user.click(await screen.findByRole("button", { name: "Bonjour" }));
    expect(screen.getByRole("heading", { name: "Bonjour" })).toBeInTheDocument();
    expect(screen.getByDisplayValue("ž")).toBeInTheDocument();
  });

  it("reste compatible avec un ancien schéma qui ne connaît pas editorName", async () => {
    render(<App />);
    await screen.findByRole("button", { name: "Bonjour" });
    expect(screen.queryByLabelText(/Nom dans l’éditeur/)).not.toBeInTheDocument();
  });

  it("sépare le nom privé du titre affiché lorsque le schéma le permet", async () => {
    const originalFetch = vi.mocked(fetch).getMockImplementation()!;
    const namedSchema = structuredClone(schema) as typeof schema & Record<string, unknown>;
    (namedSchema.properties.items.items.oneOf[0].properties as Record<string, unknown>).editorName = {
      type: "string",
      title: "Nom dans l’éditeur",
    };
    const namedConfig = { ...config, items: [{ ...config.items[0], editorName: "Lettre slovène" }] };
    vi.mocked(fetch).mockImplementation(async (input, init) => {
      const url = String(input);
      if (url.endsWith("/schema")) return jsonResponse(namedSchema);
      if (url.endsWith("/config") && init?.method !== "PUT") {
        return jsonResponse({ source: `${JSON.stringify(namedConfig, null, 2)}\n`, document: namedConfig, revision: 4, diagnostics: [], valid: true });
      }
      return originalFetch(input, init);
    });
    render(<App />);
    expect(await screen.findByRole("heading", { name: "Lettre slovène" })).toBeInTheDocument();
    expect(screen.getByLabelText(/Nom dans l’éditeur/)).toHaveValue("Lettre slovène");
    expect(screen.getByRole("button", { name: "Bonjour" })).toBeInTheDocument();
  });

  it("ouvre l’inspecteur depuis une ligne de l’ordre source", async () => {
    const user = userEvent.setup();
    render(<App />);
    await screen.findByRole("button", { name: "Bonjour" });
    await user.click(screen.getByRole("button", { name: "Replier l’inspecteur" }));
    expect(screen.getByRole("button", { name: "Ouvrir l’inspecteur" })).toBeInTheDocument();
    await user.click(screen.getByRole("row", { name: /Bonjour staticButton/ }));
    expect(screen.getByRole("button", { name: "Replier l’inspecteur" })).toBeInTheDocument();
    expect(screen.getByRole("heading", { name: "Bonjour" })).toBeInTheDocument();
  });

  it("sépare clairement les éléments des zones left, center et right", async () => {
    render(<App />);
    await screen.findByRole("row", { name: /Bonjour staticButton/ });
    expect(screen.getByRole("separator", { name: "Zone left" })).toHaveTextContent("LEFT");
    expect(screen.getByRole("separator", { name: "Zone center" })).toHaveTextContent("CENTER");
    expect(screen.getByRole("separator", { name: "Zone right" })).toHaveTextContent("RIGHT");
    expect(within(screen.getByTestId("order-zone-left")).getByRole("row", { name: /Bonjour/ })).toBeInTheDocument();
    expect(within(screen.getByTestId("order-zone-center")).getByText("Aucun élément")).toBeInTheDocument();
    expect(within(screen.getByTestId("order-zone-right")).getByText("Aucun élément")).toBeInTheDocument();
  });

  it("réordonne les éléments directement dans le tableau de la barre", async () => {
    const originalFetch = vi.mocked(fetch).getMockImplementation()!;
    const orderedConfig = {
      ...config,
      items: [
        config.items[0],
        { id: "omega", type: "staticButton", title: "Omega", align: "left", enabled: true },
      ],
    };
    vi.mocked(fetch).mockImplementation(async (input, init) => {
      if (String(input).endsWith("/config") && init?.method !== "PUT") {
        return jsonResponse({ source: `${JSON.stringify(orderedConfig, null, 2)}\n`, document: orderedConfig, revision: 4, diagnostics: [], valid: true });
      }
      return originalFetch(input, init);
    });

    render(<App />);
    const hello = await screen.findByRole("row", { name: /Bonjour staticButton left actif/ });
    const omega = screen.getByRole("row", { name: /Omega staticButton left actif/ });
    vi.spyOn(omega, "getBoundingClientRect").mockReturnValue({
      x: 0,
      y: 100,
      left: 0,
      right: 600,
      top: 100,
      bottom: 136,
      width: 600,
      height: 36,
      toJSON: () => ({}),
    });

    fireEvent.dragStart(hello);
    const dragOver = new Event("dragover", { bubbles: true, cancelable: true });
    Object.defineProperty(dragOver, "clientY", { value: 130 });
    fireEvent(omega, dragOver);
    expect(screen.getByTestId("order-drop-omega")).toHaveAttribute("data-edge", "after");

    const drop = new Event("drop", { bubbles: true, cancelable: true });
    Object.defineProperty(drop, "clientY", { value: 130 });
    fireEvent(omega, drop);

    await waitFor(() => {
      expect(screen.getAllByRole("row").map((row) => row.getAttribute("data-item-id")))
        .toEqual(["omega", "hello"]);
    });
    expect(screen.queryByTestId("order-drop-omega")).not.toBeInTheDocument();
    await waitFor(() => {
      const put = vi.mocked(fetch).mock.calls.find(([, init]) => init?.method === "PUT");
      const source = JSON.parse(String(put?.[1]?.body)).source as string;
      const saved = JSON.parse(source) as typeof orderedConfig;
      expect(saved.items.map((item) => item.id)).toEqual(["omega", "hello"]);
      expect(saved.items.map((item) => item.align)).toEqual(["left", "left"]);
    }, { timeout: 2_000 });
  });

  it("déplace un élément du root vers un groupe puis du groupe vers le root", async () => {
    const originalFetch = vi.mocked(fetch).getMockImplementation()!;
    const groupedConfig = {
      ...config,
      items: [
        {
          id: "tools",
          type: "group",
          title: "Outils",
          align: "left",
          enabled: true,
          items: [{ id: "inside", type: "staticButton", title: "Interne", align: "left", enabled: true }],
        },
        config.items[0],
      ],
    };
    vi.mocked(fetch).mockImplementation(async (input, init) => {
      if (String(input).endsWith("/config") && init?.method !== "PUT") {
        return jsonResponse({ source: `${JSON.stringify(groupedConfig, null, 2)}\n`, document: groupedConfig, revision: 4, diagnostics: [], valid: true });
      }
      return originalFetch(input, init);
    });

    render(<App />);
    const helloAtRoot = await screen.findByRole("row", { name: /Bonjour staticButton left actif/ });
    const group = screen.getByRole("row", { name: /Outils group left actif/ });
    vi.spyOn(group, "getBoundingClientRect").mockReturnValue({
      x: 0,
      y: 100,
      left: 0,
      right: 600,
      top: 100,
      bottom: 140,
      width: 600,
      height: 40,
      toJSON: () => ({}),
    });

    fireEvent.dragStart(helloAtRoot);
    const intoGroup = new Event("dragover", { bubbles: true, cancelable: true });
    Object.defineProperty(intoGroup, "clientY", { value: 120 });
    fireEvent(group, intoGroup);
    expect(screen.getByTestId("order-drop-tools")).toHaveTextContent("Dans le groupe");

    const dropIntoGroup = new Event("drop", { bubbles: true, cancelable: true });
    Object.defineProperty(dropIntoGroup, "clientY", { value: 120 });
    fireEvent(group, dropIntoGroup);

    let helloInGroup: HTMLElement | undefined;
    await waitFor(() => {
      helloInGroup = screen.getByRole("row", { name: /Bonjour staticButton left actif/ });
      expect(helloInGroup).toHaveAttribute("data-depth", "1");
    });

    const rightZone = screen.getByTestId("order-zone-right");
    fireEvent.dragStart(helloInGroup!);
    fireEvent.dragOver(rightZone);
    expect(screen.getByTestId("order-zone-drop-right")).toBeInTheDocument();
    fireEvent.drop(rightZone);

    await waitFor(() => {
      const helloAtRootRight = within(rightZone).getByRole("row", { name: /Bonjour staticButton right actif/ });
      expect(helloAtRootRight).toHaveAttribute("data-depth", "0");
    });
    await waitFor(() => {
      const puts = vi.mocked(fetch).mock.calls.filter(([, init]) => init?.method === "PUT");
      const source = JSON.parse(String(puts.at(-1)?.[1]?.body)).source as string;
      const saved = JSON.parse(source) as {
        items: Array<{ id: string; align?: string; items?: Array<{ id: string }> }>;
      };
      expect(saved.items.find((item) => item.id === "hello")).toMatchObject({ align: "right" });
      expect(saved.items.find((item) => item.id === "tools")?.items?.map((item) => item.id)).toEqual(["inside"]);
    }, { timeout: 2_000 });
  });

  it("place les interrupteurs principaux en tête et respecte leurs valeurs par défaut", async () => {
    const user = userEvent.setup();
    render(<App />);
    await screen.findByRole("button", { name: "Bonjour" });
    const enabled = screen.getByRole("switch", { name: /Élément actif/ });
    const bordered = screen.getByRole("switch", { name: /Bordure/ });
    expect(enabled).toBeChecked();
    expect(bordered).toBeChecked();
    await user.click(bordered);
    expect(bordered).not.toBeChecked();
  });

  it("ajoute un composant de palette et active undo", async () => {
    const user = userEvent.setup();
    render(<App />);
    await screen.findByRole("button", { name: "Bonjour" });
    const paletteEntry = await screen.findByTitle("Ajouter Bouton statique");
    fireEvent.dblClick(paletteEntry);
    await waitFor(() => expect(screen.getByRole("button", { name: "Nouveau" })).toBeInTheDocument());
    expect(screen.getByRole("button", { name: "Annuler" })).not.toBeDisabled();
    await user.click(screen.getByRole("button", { name: "Annuler" }));
    expect(screen.queryByRole("button", { name: "Nouveau" })).not.toBeInTheDocument();
  });

  it("explique un composant au survol de la palette", async () => {
    const user = userEvent.setup();
    render(<App />);
    await screen.findByRole("button", { name: "Bonjour" });
    await user.hover(screen.getByTitle("Ajouter Bouton statique"));
    const tooltip = await screen.findByRole("tooltip");
    expect(tooltip).toHaveTextContent("Affiche un libellé fixe");
    expect(tooltip).toHaveTextContent("ž / Ž");
  });

  it("dépose un composant de palette dans la zone centrale", async () => {
    render(<App />);
    await screen.findByRole("button", { name: "Bonjour" });
    const data = new Map<string, string>();
    const transfer = {
      effectAllowed: "none",
      dropEffect: "none",
      setData(type: string, value: string) { data.set(type, value); },
      getData(type: string) { return data.get(type) ?? ""; },
    };
    fireEvent.dragStart(screen.getByTitle("Ajouter Bouton statique"), { dataTransfer: transfer });
    const center = screen.getByTestId("drop-center");
    fireEvent.dragOver(center, { dataTransfer: transfer });
    fireEvent.drop(center, { dataTransfer: transfer });
    await waitFor(() => expect(within(center).getByRole("button", { name: "Nouveau" })).toBeInTheDocument());
  });

  it("déplace un élément existant entre zones même sans DataTransfer exploitable", async () => {
    render(<App />);
    const item = await screen.findByRole("button", { name: "Bonjour" });
    const right = screen.getByTestId("drop-right");

    fireEvent.dragStart(item);
    fireEvent.dragOver(right);
    expect(within(right).getByTestId("drop-slot-right")).toContainElement(within(right).getByTestId("drop-indicator-right"));
    fireEvent.drop(right);

    await waitFor(() => expect(within(right).getByRole("button", { name: "Bonjour" })).toBeInTheDocument());
    expect(within(screen.getByTestId("drop-left")).queryByRole("button", { name: "Bonjour" })).not.toBeInTheDocument();
    await waitFor(() => {
      const put = vi.mocked(fetch).mock.calls.find(([, init]) => init?.method === "PUT");
      const source = JSON.parse(String(put?.[1]?.body)).source as string;
      expect(JSON.parse(source).items[0].align).toBe("right");
    }, { timeout: 2_000 });
  });

  it("affiche et respecte la position exacte d’insertion entre deux éléments", async () => {
    const originalFetch = vi.mocked(fetch).getMockImplementation()!;
    const orderedConfig = {
      ...config,
      items: [
        config.items[0],
        { id: "alpha", type: "staticButton", title: "Alpha", align: "center", enabled: true },
        { id: "omega", type: "staticButton", title: "Omega", align: "center", enabled: true },
      ],
    };
    vi.mocked(fetch).mockImplementation(async (input, init) => {
      if (String(input).endsWith("/config") && init?.method !== "PUT") {
        return jsonResponse({ source: `${JSON.stringify(orderedConfig, null, 2)}\n`, document: orderedConfig, revision: 4, diagnostics: [], valid: true });
      }
      return originalFetch(input, init);
    });

    render(<App />);
    const dragged = await screen.findByRole("button", { name: "Bonjour" });
    const center = screen.getByTestId("drop-center");
    const alpha = within(center).getByRole("button", { name: "Alpha" });
    const omega = within(center).getByRole("button", { name: "Omega" });
    const bounds = (left: number, width: number) => ({
      x: left,
      y: 0,
      left,
      right: left + width,
      top: 0,
      bottom: 34,
      width,
      height: 34,
      toJSON: () => ({}),
    }) as DOMRect;
    vi.spyOn(alpha, "getBoundingClientRect").mockReturnValue(bounds(100, 40));
    vi.spyOn(omega, "getBoundingClientRect").mockReturnValue(bounds(150, 40));
    Object.defineProperty(dragged, "offsetWidth", { configurable: true, value: 60 });

    fireEvent.dragStart(dragged);
    const dragOver = new Event("dragover", { bubbles: true, cancelable: true });
    Object.defineProperties(dragOver, {
      clientX: { value: 145 },
      clientY: { value: 17 },
    });
    fireEvent(center, dragOver);
    const slot = within(center).getByTestId("drop-slot-center");
    expect(slot).toHaveStyle({ width: "60px" });
    expect(slot.nextElementSibling).toBe(omega);
    expect(slot).toContainElement(within(center).getByTestId("drop-indicator-center"));
    fireEvent.drop(center);

    await waitFor(() => {
      expect(within(center).getAllByRole("button").map((button) => button.getAttribute("aria-label")))
        .toEqual(["Alpha", "Bonjour", "Omega"]);
    });
    await waitFor(() => {
      const put = vi.mocked(fetch).mock.calls.find(([, init]) => init?.method === "PUT");
      const source = JSON.parse(String(put?.[1]?.body)).source as string;
      const saved = JSON.parse(source) as typeof orderedConfig;
      expect(saved.items.map((item) => item.id)).toEqual(["alpha", "hello", "omega"]);
      expect(saved.items.find((item) => item.id === "hello")?.align).toBe("center");
    }, { timeout: 2_000 });
  });

  it("permet de déposer un élément directement dans un groupe", async () => {
    const originalFetch = vi.mocked(fetch).getMockImplementation()!;
    const groupedConfig = {
      ...config,
      items: [
        { id: "system", type: "group", align: "left", enabled: true, items: [] },
        config.items[0],
      ],
    };
    vi.mocked(fetch).mockImplementation(async (input, init) => {
      if (String(input).endsWith("/config") && init?.method !== "PUT") {
        return jsonResponse({ source: `${JSON.stringify(groupedConfig, null, 2)}\n`, document: groupedConfig, revision: 4, diagnostics: [], valid: true });
      }
      return originalFetch(input, init);
    });

    render(<App />);
    const child = await screen.findByRole("button", { name: "Bonjour" });
    const preview = screen.getByLabelText("Aperçu de la Touch Bar");
    const group = within(preview).getByRole("button", { name: "Groupe" });
    const left = within(preview).getByTestId("drop-left");
    fireEvent.dragStart(child);
    fireEvent.dragOver(left);
    expect(within(left).getByTestId("drop-indicator-left")).toBeInTheDocument();
    fireEvent.dragOver(group);
    expect(group).toHaveClass("group-drop-active");
    expect(within(left).queryByTestId("drop-indicator-left")).not.toBeInTheDocument();
    fireEvent.drop(group);

    await waitFor(() => expect(screen.queryByRole("button", { name: "Bonjour" })).not.toBeInTheDocument());
    await waitFor(() => expect(within(preview).getByRole("button", { name: "Groupe" })).not.toHaveClass("group-drop-active"));
    expect(within(preview).getByRole("button", { name: "Groupe" })).toHaveAttribute("aria-pressed", "true");
    expect(screen.getByText("Contenu du groupe")).toBeInTheDocument();
    expect(within(screen.getByTestId("group-drop-left")).getByRole("button", { name: /Bonjour staticButton/ })).toBeInTheDocument();
    expect(screen.getByRole("row", { name: /Bonjour staticButton left actif/ })).toHaveAttribute("data-depth", "1");

    const paletteItem = screen.getByTitle("Ajouter Bouton statique");
    const centerLane = screen.getByTestId("group-drop-center");
    fireEvent.dragStart(paletteItem);
    fireEvent.dragOver(centerLane);
    expect(centerLane.querySelector(".group-drop-indicator")).toBeInTheDocument();
    fireEvent.dragEnd(paletteItem);
    await waitFor(() => expect(centerLane.querySelector(".group-drop-indicator")).not.toBeInTheDocument());

    await waitFor(() => {
      const put = vi.mocked(fetch).mock.calls.find(([, init]) => init?.method === "PUT");
      const source = JSON.parse(String(put?.[1]?.body)).source as string;
      const saved = JSON.parse(source) as { items: Array<{ id: string; items?: Array<{ id: string }> }> };
      expect(saved.items.map((item) => item.id)).toEqual(["system"]);
      expect(saved.items[0].items).toEqual([expect.objectContaining({ id: "hello" })]);
    }, { timeout: 2_000 });
  });

  it("enregistre automatiquement un formulaire valide après debounce", async () => {
    const user = userEvent.setup();
    render(<App />);
    await screen.findByRole("button", { name: "Bonjour" });
    const title = screen.getByDisplayValue("Bonjour");
    await user.clear(title);
    await user.type(title, "Salut");
    await waitFor(() => {
      const calls = vi.mocked(fetch).mock.calls;
      const put = calls.find(([, init]) => init?.method === "PUT");
      expect(put).toBeDefined();
      expect(String(put?.[1]?.body)).toContain("Salut");
      expect(new Headers(put?.[1]?.headers).get("If-Match")).toBe('"4"');
    }, { timeout: 2_000 });
  });

  it("conserve une saisie plus récente quand un PUT lent se termine", async () => {
    const user = userEvent.setup();
    const originalFetch = vi.mocked(fetch).getMockImplementation()!;
    const firstPUT = deferred<Response>();
    let firstSource = "";
    let putCount = 0;
    vi.mocked(fetch).mockImplementation(async (input, init) => {
      if (String(input).endsWith("/config") && init?.method === "PUT") {
        putCount += 1;
        if (putCount === 1) {
          firstSource = JSON.parse(String(init.body)).source as string;
          return firstPUT.promise;
        }
      }
      return originalFetch(input, init);
    });

    render(<App />);
    await screen.findByRole("button", { name: "Bonjour" });
    const title = screen.getByDisplayValue("Bonjour");
    await user.clear(title);
    await user.type(title, "Premier");
    await waitFor(() => expect(putCount).toBe(1), { timeout: 2_000 });

    await user.clear(screen.getByDisplayValue("Premier"));
    await user.type(title, "Deuxieme");
    firstPUT.resolve(jsonResponse({
      source: firstSource,
      document: JSON.parse(firstSource),
      revision: 5,
      diagnostics: [],
      valid: true,
    }));

    await waitFor(() => expect(screen.getByDisplayValue("Deuxieme")).toBeInTheDocument());
    await waitFor(() => expect(putCount).toBe(2), { timeout: 2_500 });
    const putCalls = vi.mocked(fetch).mock.calls.filter(([, init]) => init?.method === "PUT");
    expect(String(putCalls[1][1]?.body)).toContain("Deuxieme");
    expect(new Headers(putCalls[1][1]?.headers).get("If-Match")).toBe('"5"');
  });

  it("reconstruit une action depuis le schéma sans garder ses anciens paramètres", async () => {
    const user = userEvent.setup();
    render(<App />);
    await user.click(await screen.findByRole("button", { name: "Bonjour" }));
    const actionType = screen.getByLabelText("Type d’action");
    const trigger = screen.getByLabelText("Déclencheur", { selector: "select" });
    expect(within(trigger).getByRole("option", { name: "tripleTap" })).toBeInTheDocument();

    await user.selectOptions(actionType, "shellScript");
    expect(screen.queryByDisplayValue("ž")).not.toBeInTheDocument();
    expect(screen.getByText("Exécutable")).toBeInTheDocument();
    await user.selectOptions(actionType, "typeText");
    expect(screen.getByText("Texte UTF-8")).toBeInTheDocument();
    expect(screen.queryByDisplayValue("ž")).not.toBeInTheDocument();
  });

  it("verrouille les gestes visuels tant que le brouillon JSON est invalide", async () => {
    const user = userEvent.setup();
    render(<App />);
    await screen.findByRole("button", { name: "Bonjour" });
    await user.click(screen.getByRole("tab", { name: "JSON" }));
    const editorDOM = screen.getByTestId("json-editor").querySelector(".cm-editor") as HTMLElement;
    const view = EditorView.findFromDOM(editorDOM);
    expect(view).not.toBeNull();
    view!.dispatch({ changes: { from: 0, to: view!.state.doc.length, insert: "{" } });

    await user.click(screen.getByRole("tab", { name: "Formulaire" }));
    expect(await screen.findByText(/Le brouillon JSON est invalide/)).toBeInTheDocument();
    expect(screen.getByTitle("Ajouter Bouton statique")).toBeDisabled();
    expect(screen.getByRole("button", { name: "Dupliquer" })).toBeDisabled();
  });

  it("verrouille aussi le formulaire quand le fichier externe reçu est invalide", async () => {
    const originalFetch = vi.mocked(fetch).getMockImplementation()!;
    vi.mocked(fetch).mockImplementation(async (input, init) => {
      if (String(input).endsWith("/config") && init?.method !== "PUT") {
        return jsonResponse({
          source: "{",
          revision: 5,
          diagnostics: [{ severity: "error", message: "JSON externe invalide", code: "json.invalid" }],
          valid: false,
        });
      }
      return originalFetch(input, init);
    });

    render(<App />);
    expect(await screen.findByText(/Le brouillon JSON est invalide/)).toBeInTheDocument();
    expect(screen.getByTitle("Ajouter Bouton statique")).toBeDisabled();
    expect(screen.getByPlaceholderText("Notes sur cette configuration…")).toBeDisabled();
    expect(vi.mocked(fetch).mock.calls.some(([, init]) => init?.method === "PUT")).toBe(false);
  });

  it("ne remplace pas une saisie créée pendant le GET déclenché par WebSocket", async () => {
    const user = userEvent.setup();
    const originalFetch = vi.mocked(fetch).getMockImplementation()!;
    const externalGET = deferred<Response>();
    let configGETCount = 0;
    vi.mocked(fetch).mockImplementation(async (input, init) => {
      if (String(input).endsWith("/config") && init?.method !== "PUT") {
        configGETCount += 1;
        if (configGETCount === 2) return externalGET.promise;
      }
      if (String(input).endsWith("/config") && init?.method === "PUT") {
        return jsonResponse({
          error: { code: "revision_conflict", message: "Révision obsolète" },
          revision: 5,
        }, 409);
      }
      return originalFetch(input, init);
    });

    render(<App />);
    await screen.findByRole("button", { name: "Bonjour" });
    await waitFor(() => expect(MockWebSocket.instances).toHaveLength(1));
    MockWebSocket.instances[0].sendEvent({
      type: "config.changed",
      revision: 5,
      timestamp: new Date().toISOString(),
      payload: {},
    });
    await waitFor(() => expect(configGETCount).toBe(2));

    const title = screen.getByDisplayValue("Bonjour");
    await user.clear(title);
    await user.type(title, "Brouillon pendant GET");
    const external = { ...config, items: [{ ...config.items[0], title: "Externe" }] };
    externalGET.resolve(jsonResponse({
      source: `${JSON.stringify(external, null, 2)}\n`,
      document: external,
      revision: 5,
      diagnostics: [],
      valid: true,
    }));

    expect(await screen.findByDisplayValue("Brouillon pendant GET")).toBeInTheDocument();
    expect(await screen.findByText("Conflit de révision")).toBeInTheDocument();
    await user.click(screen.getByRole("button", { name: "Enregistrer" }));
    await waitFor(() => {
      const put = vi.mocked(fetch).mock.calls.find(([, init]) => init?.method === "PUT");
      expect(new Headers(put?.[1]?.headers).get("If-Match")).toBe('"4"');
    });
  });

  it("conserve le brouillon lorsqu’une révision externe arrive", async () => {
    const user = userEvent.setup();
    render(<App />);
    await screen.findByRole("button", { name: "Bonjour" });
    const title = screen.getByDisplayValue("Bonjour");
    await user.clear(title);
    await user.type(title, "Brouillon local");
    MockWebSocket.instances[0].sendEvent({
      type: "config.changed",
      revision: 99,
      timestamp: new Date().toISOString(),
      payload: {},
    });
    expect(await screen.findByText("Conflit de révision")).toBeInTheDocument();
    expect(screen.getByDisplayValue("Brouillon local")).toBeInTheDocument();
  });

  it("applique la géométrie native reçue par WebSocket", async () => {
    render(<App />);
    await screen.findByRole("button", { name: "Bonjour" });
    await waitFor(() => expect(MockWebSocket.instances).toHaveLength(1));
    MockWebSocket.instances[0].sendEvent({
      type: "runtime.snapshot",
      timestamp: new Date().toISOString(),
      payload: { items: [{ id: "hello", x: 500, width: 123, align: "right", visible: true }] },
    });
    let nativeItem: HTMLElement | undefined;
    await waitFor(() => {
      nativeItem = within(screen.getByTestId("drop-right")).getByRole("button", { name: "Bonjour" });
      expect(nativeItem).toBeInTheDocument();
    });
    expect(nativeItem).toHaveStyle({ width: "123px" });
    expect(screen.getByText("Géométrie native synchronisée")).toBeInTheDocument();
  });

  it("utilise l’image de configuration comme fallback avec l’ancien binaire", async () => {
    const originalFetch = vi.mocked(fetch).getMockImplementation()!;
    const imageConfig = { ...config, items: [{ ...config.items[0], image: { base64: "AA==" } }] };
    vi.mocked(fetch).mockImplementation(async (input, init) => {
      if (String(input).endsWith("/config") && init?.method !== "PUT") {
        return jsonResponse({ source: `${JSON.stringify(imageConfig, null, 2)}\n`, document: imageConfig, revision: 4, diagnostics: [], valid: true });
      }
      return originalFetch(input, init);
    });
    render(<App />);
    const item = await screen.findByRole("button", { name: "Bonjour" });
    expect(item.querySelector("img.touch-item-config-image")).toHaveAttribute("src", "data:image/png;base64,AA==");
    expect(item).toHaveTextContent("Bonjour");
  });

  it("affiche un rendu AppKit complet sans dupliquer son titre ou son icône", async () => {
    render(<App />);
    await screen.findByRole("button", { name: "Bonjour" });
    await waitFor(() => expect(MockWebSocket.instances).toHaveLength(1));
    MockWebSocket.instances[0].sendEvent({
      type: "runtime.snapshot",
      timestamp: new Date().toISOString(),
      payload: {
        items: [{
          id: "hello",
          width: 140,
          height: 40,
          align: "left",
          visible: true,
          kind: "dock",
          title: "Rendu MMTMR",
          renderedImage: "data:image/png;base64,AA==",
        }],
      },
    });
    const item = await screen.findByRole("button", { name: "Rendu MMTMR" });
    expect(item).toHaveClass("has-native-render");
    expect(item).toHaveStyle({ width: "140px", height: "40px" });
    expect(item.querySelector("img.touch-item-complete-render")).toHaveAttribute("src", "data:image/png;base64,AA==");
    expect(item.querySelector(".touch-item-label")).toBeNull();
    expect(item.querySelector(".touch-item-symbol")).toBeNull();
  });

  it("fusionne les snapshots delta, conserve puis supprime explicitement l’image native", async () => {
    render(<App />);
    await screen.findByRole("button", { name: "Bonjour" });
    await waitFor(() => expect(MockWebSocket.instances).toHaveLength(1));
    const socket = MockWebSocket.instances[0];
    socket.sendEvent({
      type: "runtime.snapshot",
      timestamp: new Date().toISOString(),
      payload: { items: [{ id: "hello", align: "left", width: 90, visible: true, title: "Titre natif", renderedImage: "data:image/png;base64,AA==" }] },
    });
    expect((await screen.findByRole("button", { name: "Titre natif" })).querySelector("img")).toBeInTheDocument();

    socket.sendEvent({
      type: "runtime.snapshot",
      timestamp: new Date().toISOString(),
      payload: { items: [{ id: "hello", align: "right", width: 100, visible: true }] },
    });
    let merged: HTMLElement | undefined;
    await waitFor(() => {
      merged = within(screen.getByTestId("drop-right")).getByRole("button", { name: "Titre natif" });
      expect(merged.querySelector("img")).toBeInTheDocument();
    });

    socket.sendEvent({
      type: "runtime.snapshot",
      timestamp: new Date().toISOString(),
      payload: { items: [{ id: "hello", align: "right", width: 100, visible: true, renderedImage: null }] },
    });
    await waitFor(() => expect(screen.getByRole("button", { name: "Titre natif" }).querySelector("img")).toBeNull());
    expect(screen.getByRole("button", { name: "Titre natif" })).toHaveTextContent("Titre natif");

    socket.sendEvent({
      type: "runtime.snapshot",
      timestamp: new Date().toISOString(),
      payload: { items: [{ id: "hello", align: "right", width: 100, visible: true, title: null }] },
    });
    expect(await screen.findByRole("button", { name: "Bonjour" })).toBeInTheDocument();
  });

  it("affiche l’avertissement Accessibilité et un diagnostic input sûr sans révéler les autres payloads", async () => {
    const user = userEvent.setup();
    render(<App />);
    await screen.findByRole("button", { name: "Bonjour" });
    await waitFor(() => expect(MockWebSocket.instances).toHaveLength(1));
    const socket = MockWebSocket.instances[0];
    socket.sendEvent({
      type: "runtime.snapshot",
      timestamp: new Date().toISOString(),
      payload: { items: [], context: { inputAccess: false } },
    });
    expect(await screen.findByRole("alert")).toHaveTextContent("Réglages > Accessibilité");
    expect(screen.getByRole("alert")).toHaveTextContent("saisir les lettres");
    await user.click(screen.getByRole("tab", { name: "Aperçu" }));
    await user.click(screen.getByRole("button", { name: "Personnalisé" }));
    expect(screen.getByRole("alert")).toHaveTextContent("Réglages > Accessibilité");
    socket.sendEvent({ type: "server.error", timestamp: new Date().toISOString(), payload: { code: "input.access", message: "Autorisation refusée" } });
    socket.sendEvent({ type: "server.error", timestamp: new Date().toISOString(), payload: { code: "server.internal", message: "SECRET_PAYLOAD" } });
    await user.click(screen.getByRole("tab", { name: /Journal/ }));
    expect(await screen.findByText(/input\.access: Autorisation refusée/)).toBeInTheDocument();
    expect(screen.queryByText(/SECRET_PAYLOAD/)).not.toBeInTheDocument();
    expect(screen.getAllByText("Reçu de MMTMR").length).toBeGreaterThan(0);
  });

  it("applique le contexte runtime sans le polluer avec une simulation d’action", async () => {
    render(<App />);
    await screen.findByRole("button", { name: "Bonjour" });
    await waitFor(() => expect(MockWebSocket.instances).toHaveLength(1));
    MockWebSocket.instances[0].sendEvent({
      type: "runtime.snapshot",
      timestamp: new Date().toISOString(),
      payload: {
        items: [],
        context: { application: "Xcode", battery: 51, networkConnected: false, theme: "light", time: "2026-07-18T14:26:00Z" },
      },
    });
    await waitFor(() => expect(screen.getByText("Xcode")).toBeInTheDocument());
    expect(screen.getByLabelText("Aperçu de la Touch Bar")).toHaveAttribute("data-theme", "light");

    MockWebSocket.instances[0].sendEvent({
      type: "simulation.changed",
      timestamp: new Date().toISOString(),
      payload: { kind: "action", context: { application: "Ne doit pas apparaître", theme: "dark" }, description: "Action seulement décrite" },
    });
    expect(screen.getByText("Xcode")).toBeInTheDocument();
    expect(screen.queryByText("Ne doit pas apparaître")).not.toBeInTheDocument();
    expect(screen.getByLabelText("Aperçu de la Touch Bar")).toHaveAttribute("data-theme", "light");
  });

  it("simule une action sans demander son exécution", async () => {
    const user = userEvent.setup();
    render(<App />);
    await screen.findByRole("button", { name: "Bonjour" });
    await user.click(screen.getByRole("tab", { name: "Aperçu" }));
    await user.click(screen.getByRole("button", { name: "Décrire l’action" }));
    expect(await screen.findByText("La lettre ž serait saisie.")).toBeInTheDocument();
    const call = vi.mocked(fetch).mock.calls.find(([url]) => String(url).endsWith("/preview/action"));
    expect(call).toBeDefined();
    const body = JSON.parse(String(call?.[1]?.body));
    expect(body).toMatchObject({ itemID: "hello", trigger: "singleTap" });
    expect(body).not.toHaveProperty("execute");
  });

  it("démarre en mode Direct et réinitialise le contexte local sans appel serveur", async () => {
    const user = userEvent.setup();
    render(<App />);
    await screen.findByRole("button", { name: "Bonjour" });
    await user.click(screen.getByRole("tab", { name: "Aperçu" }));
    const direct = screen.getByRole("button", { name: "Direct" });
    const application = screen.getByLabelText("Application active");
    expect(direct).toHaveAttribute("aria-pressed", "true");
    expect(application).toBeDisabled();
    await user.click(screen.getByRole("button", { name: "Personnalisé" }));
    expect(application).not.toBeDisabled();
    await user.click(direct);
    expect(application).toBeDisabled();
    expect(vi.mocked(fetch).mock.calls.some(([url]) => String(url).endsWith("/preview/context"))).toBe(false);
  });

  it("replie indépendamment les deux panneaux latéraux", async () => {
    const user = userEvent.setup();
    render(<App />);
    await screen.findByRole("button", { name: "Bonjour" });
    await user.click(screen.getByRole("button", { name: "Replier la palette" }));
    await user.click(screen.getByRole("button", { name: "Replier l’inspecteur" }));
    expect(screen.getByRole("button", { name: "Ouvrir la palette" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Ouvrir l’inspecteur" })).toBeInTheDocument();
  });

  it("se reconnecte au WebSocket après une coupure", async () => {
    render(<App />);
    await screen.findByRole("button", { name: "Bonjour" });
    await waitFor(() => expect(screen.getByText("Connecté")).toBeInTheDocument());
    expect(MockWebSocket.instances).toHaveLength(1);
    MockWebSocket.instances[0].close();
    await waitFor(() => expect(screen.getByText("Déconnecté")).toBeInTheDocument());
    await waitFor(() => expect(MockWebSocket.instances).toHaveLength(2), { timeout: 1_500 });
    await waitFor(() => expect(screen.getByText("Connecté")).toBeInTheDocument());
  });
});
