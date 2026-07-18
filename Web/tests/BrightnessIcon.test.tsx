import { render } from "@testing-library/preact";
import { describe, expect, it } from "vitest";
import { BrightnessIcon } from "../src/components/BrightnessIcon";

describe("icônes de luminosité", () => {
  it("dessine le soleil et le plus uniquement avec des formes vectorielles", () => {
    const { container } = render(<BrightnessIcon direction="up" />);
    const svg = container.querySelector("svg");

    expect(svg).toHaveAttribute("viewBox", "0 0 32 24");
    expect(svg).toHaveAttribute("data-direction", "up");
    expect(svg?.querySelector(".brightness-icon-sun")).not.toBeNull();
    expect(svg?.querySelector('[data-adjustment="horizontal"]')).not.toBeNull();
    expect(svg?.querySelector('[data-adjustment="vertical"]')).not.toBeNull();
    expect(svg?.querySelector("text")).toBeNull();
  });

  it("dessine le moins sans trait vertical résiduel", () => {
    const { container } = render(<BrightnessIcon direction="down" />);
    const svg = container.querySelector("svg");

    expect(svg).toHaveAttribute("data-direction", "down");
    expect(svg?.querySelector('[data-adjustment="horizontal"]')).not.toBeNull();
    expect(svg?.querySelector('[data-adjustment="vertical"]')).toBeNull();
    expect(svg?.textContent).toBe("");
  });
});
