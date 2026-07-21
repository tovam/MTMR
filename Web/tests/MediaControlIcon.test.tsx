import { render } from "@testing-library/preact";
import { describe, expect, it } from "vitest";
import { MediaControlIcon, SystemUsageIcon } from "../src/components/MediaControlIcon";

describe("MediaControlIcon", () => {
  it("distingue les deux niveaux de luminosité avec des soleils vectoriels", () => {
    const up = render(<MediaControlIcon kind="brightnessUp" />).container;
    const down = render(<MediaControlIcon kind="brightnessDown" />).container;
    expect(up.querySelector("svg")).toHaveAttribute("data-kind", "brightnessUp");
    expect(down.querySelector("svg")).toHaveAttribute("data-kind", "brightnessDown");
    expect(Number(up.querySelector("circle")?.getAttribute("r"))).toBeGreaterThan(
      Number(down.querySelector("circle")?.getAttribute("r")),
    );
    expect(up.querySelectorAll("line")).toHaveLength(8);
    expect(down.querySelectorAll("line")).toHaveLength(8);
  });

  it("dessine une onde discrète pour volume moins et trois pour volume plus", () => {
    const down = render(<MediaControlIcon kind="volumeDown" />).container;
    const up = render(<MediaControlIcon kind="volumeUp" />).container;
    expect(down.querySelectorAll(".media-icon-speaker > path")).toHaveLength(2);
    expect(up.querySelectorAll(".media-icon-speaker > path")).toHaveLength(4);
  });

  it("rend le CPU et la RAM comme le même graphique de colonnes d’un pixel", () => {
    const cpu = render(<SystemUsageIcon kind="cpu" />).container;
    const memory = render(<SystemUsageIcon kind="memory" />).container;
    expect(cpu.querySelector("svg")).toHaveAttribute("data-kind", "cpu");
    expect(memory.querySelector("svg")).toHaveAttribute("data-kind", "memory");
    expect(cpu.querySelectorAll(".system-usage-bar")).toHaveLength(60);
    expect(memory.querySelectorAll(".system-usage-bar")).toHaveLength(60);
    expect(cpu.querySelector("text, circle")).not.toBeInTheDocument();
    expect(memory.querySelector("text, circle")).not.toBeInTheDocument();
    expect(cpu.querySelector(".system-usage-background")).not.toBeInTheDocument();
    expect(memory.querySelector(".system-usage-background")).not.toBeInTheDocument();
    expect(cpu.querySelector(".system-usage-bar")).toHaveAttribute("width", "1");
    expect(memory.querySelector(".system-usage-bar")).toHaveAttribute("width", "1");
  });
});
