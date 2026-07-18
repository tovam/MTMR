import { expect, test } from "@playwright/test";

const config = {
  formatVersion: 1,
  items: Array.from({ length: 24 }, (_, index) => ({
    id: `item-${index}`,
    type: "staticButton",
    title: `Élément ${index}`,
    align: index % 3 === 0 ? "left" : index % 3 === 1 ? "center" : "right",
    enabled: true,
  })),
};

test.beforeEach(async ({ page }) => {
  await page.addInitScript(() => {
    class InertWebSocket extends EventTarget {
      static OPEN = 1;
      readyState = 1;
      constructor() {
        super();
        queueMicrotask(() => this.dispatchEvent(new Event("open")));
      }
      close() {}
    }
    Object.defineProperty(window, "WebSocket", { configurable: true, value: InertWebSocket });
  });
  await page.route("**/api/v1/**", async (route) => {
    const path = new URL(route.request().url()).pathname;
    if (path.endsWith("/status")) {
      await route.fulfill({ json: { version: "test", port: 8787, configPath: "/Users/test/.mtmr.json", revision: 1, valid: true } });
    } else if (path.endsWith("/schema")) {
      await route.fulfill({ json: { type: "object", properties: { items: { type: "array", items: { type: "object" } } } } });
    } else {
      await route.fulfill({ json: { source: `${JSON.stringify(config, null, 2)}\n`, document: config, revision: 1, diagnostics: [], valid: true } });
    }
  });
  await page.goto("/");
  await expect(page.getByRole("button", { name: "Élément 0" })).toBeVisible();
});

test("le viewport n’a jamais de scroll global", async ({ page }) => {
  const measurements = await page.evaluate(() => ({
    html: [document.documentElement.clientWidth, document.documentElement.scrollWidth, document.documentElement.clientHeight, document.documentElement.scrollHeight],
    body: [document.body.clientWidth, document.body.scrollWidth, document.body.clientHeight, document.body.scrollHeight],
    root: [document.getElementById("root")!.clientHeight, document.getElementById("root")!.scrollHeight],
    shell: [document.querySelector<HTMLElement>(".app-shell")!.clientHeight, document.querySelector<HTMLElement>(".app-shell")!.scrollHeight],
  }));
  expect(measurements.html[0]).toBe(measurements.html[1]);
  expect(measurements.html[2]).toBe(measurements.html[3]);
  expect(measurements.body[0]).toBe(measurements.body[1]);
  expect(measurements.body[2]).toBe(measurements.body[3]);
  expect(measurements.root[0]).toBe(measurements.root[1]);
  expect(measurements.shell[0]).toBe(measurements.shell[1]);
});

test("seules les régions prévues déclarent leur propre overflow", async ({ page }) => {
  const styles = await page.evaluate(() => {
    const style = (selector: string) => {
      const value = getComputedStyle(document.querySelector(selector)!);
      return { x: value.overflowX, y: value.overflowY };
    };
    return {
      body: style("body"),
      palette: style("[data-testid=palette-scroll]"),
      preview: style("[data-testid=preview-scroll]"),
      panel: style("[data-testid=active-panel]"),
      inspector: style("[data-testid=inspector-scroll]"),
    };
  });
  expect(styles.body).toEqual({ x: "hidden", y: "hidden" });
  expect(styles.palette.y).toBe("auto");
  expect(styles.preview.x).toBe("auto");
  expect(styles.preview.y).toBe("hidden");
  expect(styles.panel.y).toBe("auto");
  expect(styles.inspector.y).toBe("auto");
});

test("le header et le footer conservent leur hauteur fixe", async ({ page }) => {
  await expect(page.locator(".app-header")).toHaveCSS("height", "48px");
  await expect(page.locator(".status-bar")).toHaveCSS("height", "24px");
});

test("les panneaux sont réduits sur une petite fenêtre", async ({ page }) => {
  await page.setViewportSize({ width: 760, height: 700 });
  await expect(page.locator(".palette")).toHaveCSS("width", "38px");
  await expect(page.locator(".inspector")).toHaveCSS("width", "38px");
  const noGlobalScroll = await page.evaluate(() => document.body.scrollWidth === document.body.clientWidth);
  expect(noGlobalScroll).toBe(true);
});
