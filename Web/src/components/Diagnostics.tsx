import type { Diagnostic } from "../types";

export function Diagnostics({ diagnostics }: { diagnostics: Diagnostic[] }) {
  if (diagnostics.length === 0) {
    return <div class="empty-state compact">Aucun diagnostic.</div>;
  }
  return (
    <div class="diagnostics" role="list" aria-label="Diagnostics">
      {diagnostics.map((entry, index) => (
        <div class={`diagnostic diagnostic-${entry.severity === "information" ? "info" : entry.severity}`} role="listitem" key={`${entry.path}-${entry.message}-${index}`}>
          <span class="diagnostic-symbol" aria-hidden="true">
            {entry.severity === "error" ? (
              <svg viewBox="0 0 12 12" width="10" height="10" focusable="false">
                <path d="M2.25 2.25 9.75 9.75M9.75 2.25 2.25 9.75" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" />
              </svg>
            ) : entry.severity === "warning" ? "!" : "i"}
          </span>
          <div>
            <div>{entry.message}</div>
            {(entry.path || entry.line) && (
              <div class="diagnostic-location">
                {entry.path ?? "$"}{entry.line ? ` · ligne ${entry.line}${entry.column ? `:${entry.column}` : ""}` : ""}
              </div>
            )}
          </div>
        </div>
      ))}
    </div>
  );
}
