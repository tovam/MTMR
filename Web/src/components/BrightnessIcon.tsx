export type BrightnessDirection = "up" | "down";

interface BrightnessIconProps {
  direction: BrightnessDirection;
  className?: string;
}

/**
 * Compact, font-independent display-brightness icon.
 *
 * The sun and the plus/minus sign are deliberately drawn as vector strokes:
 * they stay crisp inside the 20 px Touch Bar preview and do not depend on the
 * platform's rendering of Unicode glyphs.
 */
export function BrightnessIcon({ direction, className = "" }: BrightnessIconProps) {
  return (
    <svg
      class={`brightness-icon ${className}`.trim()}
      viewBox="0 0 32 24"
      aria-hidden="true"
      focusable="false"
      data-direction={direction}
    >
      <g
        class="brightness-icon-sun"
        fill="none"
        stroke="currentColor"
        stroke-width="1.75"
        stroke-linecap="round"
        stroke-linejoin="round"
      >
        <circle cx="10.5" cy="12" r="3.35" />
        <path d="M10.5 3.25v2.1M10.5 18.65v2.1M1.75 12h2.1M17.15 12h2.1M4.31 5.81l1.49 1.49M15.2 16.7l1.49 1.49M4.31 18.19 5.8 16.7M15.2 7.3l1.49-1.49" />
      </g>

      <circle
        class="brightness-icon-badge"
        cx="24.5"
        cy="12"
        r="5.25"
        stroke="currentColor"
        stroke-width="1.4"
      />
      <path
        class="brightness-icon-adjustment"
        data-adjustment="horizontal"
        d="M21.85 12h5.3"
        fill="none"
        stroke="currentColor"
        stroke-width="1.8"
        stroke-linecap="round"
      />
      {direction === "up" && (
        <path
          class="brightness-icon-adjustment"
          data-adjustment="vertical"
          d="M24.5 9.35v5.3"
          fill="none"
          stroke="currentColor"
          stroke-width="1.8"
          stroke-linecap="round"
        />
      )}
    </svg>
  );
}

export function brightnessDirectionForType(type: string): BrightnessDirection | undefined {
  if (type === "brightnessUp") return "up";
  if (type === "brightnessDown") return "down";
  return undefined;
}
