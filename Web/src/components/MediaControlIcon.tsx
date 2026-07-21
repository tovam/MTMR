export type MediaControlKind = "brightnessUp" | "brightnessDown" | "volumeUp" | "volumeDown";
export type SystemUsageKind = "cpu" | "memory";

interface MediaControlIconProps {
  kind: MediaControlKind;
  className?: string;
}

export function mediaControlKindForType(type: string): MediaControlKind | undefined {
  return ["brightnessUp", "brightnessDown", "volumeUp", "volumeDown"].includes(type)
    ? type as MediaControlKind
    : undefined;
}

function Sun({ large }: { large: boolean }) {
  const center = 12;
  const radius = large ? 4.1 : 2.8;
  const rayStart = large ? 6.8 : 5.1;
  const rayEnd = large ? 9.1 : 7.2;
  const rays = Array.from({ length: 8 }, (_, index) => {
    const angle = index * Math.PI / 4;
    const cosine = Math.cos(angle);
    const sine = Math.sin(angle);
    return {
      x1: center + cosine * rayStart,
      y1: center + sine * rayStart,
      x2: center + cosine * rayEnd,
      y2: center + sine * rayEnd,
    };
  });
  return (
    <g class="media-icon-sun" transform="translate(6 0)">
      <circle cx={center} cy={center} r={radius} />
      {rays.map((ray, index) => (
        <line key={index} x1={ray.x1} y1={ray.y1} x2={ray.x2} y2={ray.y2} />
      ))}
    </g>
  );
}

function Speaker({ loud }: { loud: boolean }) {
  return (
    <g class="media-icon-speaker">
      <path class="media-icon-speaker-body" d="M4.5 9.25h4.1l5.15-4.1v13.7l-5.15-4.1H4.5z" />
      <path d="M17.05 9.15c1.65 1.55 1.65 4.15 0 5.7" />
      {loud && <path d="M20.25 6.45c3.25 3.05 3.25 8.05 0 11.1" />}
      {loud && <path d="M23.45 3.85c4.75 4.5 4.75 11.8 0 16.3" />}
    </g>
  );
}

/** Vector equivalents of the native Touch Bar brightness and volume glyphs. */
export function MediaControlIcon({ kind, className = "" }: MediaControlIconProps) {
  const brightness = kind === "brightnessUp" || kind === "brightnessDown";
  return (
    <svg
      class={`media-control-icon ${className}`.trim()}
      viewBox="0 0 36 24"
      aria-hidden="true"
      focusable="false"
      data-kind={kind}
    >
      <g
        fill="none"
        stroke="currentColor"
        stroke-width="1.65"
        stroke-linecap="round"
        stroke-linejoin="round"
      >
        {brightness
          ? <Sun large={kind === "brightnessUp"} />
          : <Speaker loud={kind === "volumeUp"} />}
      </g>
    </svg>
  );
}

function systemUsageSamples(kind: SystemUsageKind): number[] {
  const offset = kind === "cpu" ? 0 : 1.35;
  const baseline = kind === "cpu" ? 0.28 : 0.57;
  return Array.from({ length: 60 }, (_, index) => {
    const wave = Math.sin(index * 0.31 + offset) * 0.12;
    const detail = Math.sin(index * 0.83 + offset) * 0.045;
    return Math.max(0.05, Math.min(0.95, baseline + wave + detail));
  });
}

/** Pixel-column preview matching the native CPU/RAM history graph. */
export function SystemUsageIcon({ kind }: { kind: SystemUsageKind }) {
  const samples = systemUsageSamples(kind);
  return (
    <svg
      class="system-usage-icon"
      viewBox="0 0 60 60"
      aria-hidden="true"
      focusable="false"
      data-kind={kind}
      shape-rendering="crispEdges"
    >
      <rect class="system-usage-background" x="0" y="0" width="60" height="60" />
      {samples.map((sample, index) => {
        const height = Math.max(1, Math.floor(sample * 60));
        return <rect class="system-usage-bar" key={index} x={index} y={60 - height} width="1" height={height} />;
      })}
    </svg>
  );
}

export function ItemTypeIcon({ type, fallback }: { type: string; fallback: string }) {
  const kind = mediaControlKindForType(type);
  if (kind) return <MediaControlIcon kind={kind} />;
  if (type === "cpu" || type === "memory") return <SystemUsageIcon kind={type} />;
  return <>{fallback}</>;
}
