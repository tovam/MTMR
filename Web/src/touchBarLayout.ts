import type { Alignment } from "./types";

export interface TouchBarZoneWidths {
  left: number;
  center: number;
  right: number;
}

export interface TouchBarZoneFrame {
  x: number;
  width: number;
}

export type TouchBarZoneFrames = Record<Alignment, TouchBarZoneFrame>;

export const TOUCH_BAR_GROUP_SPACING = 2;

function safe(value: number): number {
  return Number.isFinite(value) ? Math.max(0, value) : 0;
}

/** Mirrors TouchBarPhysicalLayout in the native application. */
export function computeTouchBarZoneFrames(
  containerWidth: number,
  naturalWidths: TouchBarZoneWidths,
  spacing = TOUCH_BAR_GROUP_SPACING,
): TouchBarZoneFrames {
  const width = safe(containerWidth);
  const leftNatural = safe(naturalWidths.left);
  const centerNatural = safe(naturalWidths.center);
  const rightNatural = safe(naturalWidths.right);
  const safeSpacing = safe(spacing);

  if (centerNatural > 0) {
    const centerWidth = Math.min(centerNatural, width);
    const centerX = (width - centerWidth) / 2;
    const leftWidth = Math.min(leftNatural, Math.max(0, centerX - safeSpacing));
    const rightCapacity = Math.max(0, width - (centerX + centerWidth) - safeSpacing);
    const rightWidth = Math.min(rightNatural, rightCapacity);
    return {
      left: { x: 0, width: leftWidth },
      center: { x: centerX, width: centerWidth },
      right: { x: width - rightWidth, width: rightWidth },
    };
  }

  const available = Math.max(0, width - (leftNatural > 0 && rightNatural > 0 ? safeSpacing : 0));
  let leftWidth: number;
  let rightWidth: number;
  if (leftNatural + rightNatural <= available) {
    leftWidth = leftNatural;
    rightWidth = rightNatural;
  } else if (leftNatural <= available / 2) {
    leftWidth = leftNatural;
    rightWidth = Math.min(rightNatural, available - leftNatural);
  } else if (rightNatural <= available / 2) {
    rightWidth = rightNatural;
    leftWidth = Math.min(leftNatural, available - rightNatural);
  } else {
    leftWidth = Math.min(leftNatural, available / 2);
    rightWidth = Math.min(rightNatural, available / 2);
  }

  return {
    left: { x: 0, width: leftWidth },
    center: { x: width / 2, width: 0 },
    right: { x: width - rightWidth, width: rightWidth },
  };
}
