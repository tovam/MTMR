import { describe, expect, it } from "vitest";
import { computeTouchBarZoneFrames, TOUCH_BAR_GROUP_SPACING } from "../src/touchBarLayout";

describe("computeTouchBarZoneFrames", () => {
  it("anchors natural side groups to the real edges and center to the midpoint", () => {
    expect(computeTouchBarZoneFrames(1_000, { left: 400, center: 100, right: 250 })).toEqual({
      left: { x: 0, width: 400 },
      center: { x: 450, width: 100 },
      right: { x: 750, width: 250 },
    });
  });

  it("clips both sides before allowing them to displace the center", () => {
    const frames = computeTouchBarZoneFrames(1_000, { left: 700, center: 100, right: 700 });
    expect(frames.center.x + frames.center.width / 2).toBe(500);
    expect(frames.left.x).toBe(0);
    expect(frames.left.x + frames.left.width + TOUCH_BAR_GROUP_SPACING).toBe(frames.center.x);
    expect(frames.right.x).toBe(frames.center.x + frames.center.width + TOUCH_BAR_GROUP_SPACING);
    expect(frames.right.x + frames.right.width).toBe(1_000);
  });

  it("lets an asymmetric side use free space when there is no center group", () => {
    expect(computeTouchBarZoneFrames(1_000, { left: 800, center: 0, right: 100 })).toEqual({
      left: { x: 0, width: 800 },
      center: { x: 500, width: 0 },
      right: { x: 900, width: 100 },
    });
  });

  it("shares space without overlap when both sides overflow", () => {
    const frames = computeTouchBarZoneFrames(1_000, { left: 800, center: 0, right: 800 });
    expect(frames.left.width).toBe(499);
    expect(frames.right.width).toBe(499);
    expect(frames.left.x + frames.left.width + TOUCH_BAR_GROUP_SPACING).toBe(frames.right.x);
  });

  it("anchors the center to a calibrated chassis coordinate", () => {
    const frames = computeTouchBarZoneFrames(
      1_000,
      { left: 400, center: 100, right: 250 },
      TOUCH_BAR_GROUP_SPACING,
      462,
    );
    expect(frames.left.x).toBe(0);
    expect(frames.center.x + frames.center.width / 2).toBe(462);
    expect(frames.right.x + frames.right.width).toBe(1_000);
  });
});
