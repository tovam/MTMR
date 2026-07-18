import { useEffect, useState } from "preact/hooks";
import type {
  ConfigDocument,
  Diagnostic,
  EditorTab,
  EventRecord,
  ItemConfig,
  SaveState,
  SimulationContext,
} from "../types";
import { CodeEditor } from "./CodeEditor";
import { Diagnostics } from "./Diagnostics";

interface WorkspacePanelsProps {
  tab: EditorTab;
  document: ConfigDocument;
  source: string;
  diagnostics: Diagnostic[];
  events: EventRecord[];
  simulation: SimulationContext;
  simulationResult: string;
  selectedItem?: ItemConfig;
  saveState: SaveState;
  editingLocked?: boolean;
  onTab(tab: EditorTab): void;
  onSource(source: string): void;
  onDocument(document: ConfigDocument): void;
  onSimulation(context: SimulationContext): void;
  onSimulateAction(itemID?: string, trigger?: string): void;
}

const TABS: Array<{ id: EditorTab; label: string }> = [
  { id: "form", label: "Formulaire" },
  { id: "json", label: "JSON" },
  { id: "simulation", label: "Simulation" },
  { id: "events", label: "Événements" },
];

function FormPanel({
  document,
  diagnostics,
  onDocument,
  editingLocked,
}: Pick<WorkspacePanelsProps, "document" | "diagnostics" | "onDocument" | "editingLocked">) {
  const counts = document.items.reduce<Record<string, number>>((result, item) => {
    const align = String(item.align ?? "left");
    result[align] = (result[align] ?? 0) + 1;
    return result;
  }, {});
  return (
    <div class="form-layout">
      {editingLocked && (
        <div class="draft-lock-banner" role="alert">
          Le brouillon JSON est invalide. Corrigez-le dans l’onglet JSON ou utilisez Annuler avant de modifier la barre visuellement.
        </div>
      )}
      <section class="content-card">
        <div class="card-heading">
          <div>
            <span class="eyebrow">Document</span>
            <h3>Configuration générale</h3>
          </div>
          <span class="count-pill">v{document.formatVersion}</span>
        </div>
        <label class="property-field">
          <span class="field-label">Notes</span>
          <textarea
            rows={4}
            placeholder="Notes sur cette configuration…"
            disabled={editingLocked}
            value={document.notes ?? ""}
            onInput={(event) => onDocument({ ...document, notes: event.currentTarget.value || undefined })}
          />
        </label>
        <div class="stats-grid">
          <div><strong>{document.items.length}</strong><span>éléments</span></div>
          <div><strong>{counts.left ?? 0}</strong><span>à gauche</span></div>
          <div><strong>{counts.center ?? 0}</strong><span>au centre</span></div>
          <div><strong>{counts.right ?? 0}</strong><span>à droite</span></div>
        </div>
      </section>
      <section class="content-card">
        <div class="card-heading">
          <div>
            <span class="eyebrow">Validation</span>
            <h3>Diagnostics</h3>
          </div>
          <span class={`count-pill ${diagnostics.some((entry) => entry.severity === "error") ? "count-error" : ""}`}>
            {diagnostics.length}
          </span>
        </div>
        <Diagnostics diagnostics={diagnostics} />
      </section>
      <section class="content-card full-width">
        <div class="card-heading">
          <div>
            <span class="eyebrow">Ordre source</span>
            <h3>Éléments</h3>
          </div>
        </div>
        <div class="item-table" role="table" aria-label="Éléments configurés">
          {document.items.map((item, index) => (
            <div class="item-row" role="row" key={item.id}>
              <span class="row-index">{String(index + 1).padStart(2, "0")}</span>
              <strong>{typeof item.title === "string" && item.title ? item.title : item.type}</strong>
              <code>{item.type}</code>
              <span>{item.align ?? "left"}</span>
              <span class={item.enabled === false ? "status-disabled" : "status-enabled"}>
                {item.enabled === false ? "désactivé" : "actif"}
              </span>
            </div>
          ))}
          {document.items.length === 0 && <div class="empty-state compact">La barre est vide.</div>}
        </div>
      </section>
    </div>
  );
}

function SimulationPanel({
  simulation,
  simulationResult,
  selectedItem,
  onSimulation,
  onSimulateAction,
}: Pick<WorkspacePanelsProps, "simulation" | "simulationResult" | "selectedItem" | "onSimulation" | "onSimulateAction">) {
  const [draft, setDraft] = useState(simulation);
  const [trigger, setTrigger] = useState("singleTap");
  useEffect(() => setDraft(simulation), [simulation]);
  return (
    <div class="simulation-grid">
      <section class="content-card">
        <div class="card-heading">
          <div>
            <span class="eyebrow">Contexte fictif</span>
            <h3>État de la barre</h3>
          </div>
          <span class="safe-badge">Sans effet système</span>
        </div>
        <label class="property-field">
          <span class="field-label">Application active</span>
          <input value={draft.application} onInput={(event) => setDraft({ ...draft, application: event.currentTarget.value })} />
        </label>
        <label class="property-field">
          <span class="field-label">Batterie · {draft.battery}%</span>
          <input type="range" min="0" max="100" value={draft.battery} onInput={(event) => setDraft({ ...draft, battery: Number(event.currentTarget.value) })} />
        </label>
        <label class="property-field">
          <span class="field-label">Heure</span>
          <input type="time" value={draft.time} onInput={(event) => setDraft({ ...draft, time: event.currentTarget.value })} />
        </label>
        <div class="inline-fields">
          <label class="property-field">
            <span class="field-label">Thème</span>
            <select value={draft.theme} onChange={(event) => setDraft({ ...draft, theme: event.currentTarget.value as "dark" | "light" })}>
              <option value="dark">Sombre</option>
              <option value="light">Clair</option>
            </select>
          </label>
          <label class="property-field">
            <span class="field-label">Réseau</span>
            <span class="switch-row">
              <input type="checkbox" checked={draft.networkConnected} onChange={(event) => setDraft({ ...draft, networkConnected: event.currentTarget.checked })} />
              <span>{draft.networkConnected ? "Connecté" : "Déconnecté"}</span>
            </span>
          </label>
        </div>
        <button class="primary-button" onClick={() => onSimulation(draft)}>Appliquer le contexte simulé</button>
      </section>
      <section class="content-card">
        <div class="card-heading">
          <div>
            <span class="eyebrow">Action sélectionnée</span>
            <h3>{selectedItem?.title ? String(selectedItem.title) : selectedItem?.type ?? "Aucun élément"}</h3>
          </div>
        </div>
        <label class="property-field">
          <span class="field-label">Déclencheur</span>
          <select value={trigger} onChange={(event) => setTrigger(event.currentTarget.value)}>
            {["singleTap", "doubleTap", "tripleTap", "longTap"].map((value) => <option value={value}>{value}</option>)}
          </select>
        </label>
        <button class="secondary-button" disabled={!selectedItem} onClick={() => onSimulateAction(selectedItem?.id, trigger)}>
          Simuler, sans exécuter
        </button>
        <div class="simulation-result">
          <span class="eyebrow">Résultat descriptif</span>
          <p>{simulationResult}</p>
        </div>
        <p class="security-note">MMTMR n’exécute ici ni frappe, ni URL, ni AppleScript, ni script shell.</p>
      </section>
    </div>
  );
}

function EventsPanel({ events }: { events: EventRecord[] }) {
  return (
    <div class="events-panel">
      <div class="events-header">
        <span>{events.length} événement{events.length > 1 ? "s" : ""}</span>
        <span>Les plus récents en premier</span>
      </div>
      {events.length === 0 ? <div class="empty-state">Aucun événement reçu.</div> : (
        <div class="event-list">
          {events.map((event) => (
            <div class="event-row" key={event.id}>
              <time>{new Date(event.time).toLocaleTimeString("fr-FR")}</time>
              <code>{event.type}</code>
              <span>{event.detail}</span>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

export function WorkspacePanels(props: WorkspacePanelsProps) {
  return (
    <section class="editor-panels">
      <div class="tabbar" role="tablist" aria-label="Modes d’édition">
        {TABS.map((tab) => (
          <button
            role="tab"
            aria-selected={props.tab === tab.id}
            class={props.tab === tab.id ? "is-active" : ""}
            onClick={() => props.onTab(tab.id)}
            key={tab.id}
          >
            {tab.label}
            {tab.id === "json" && props.diagnostics.some((entry) => entry.severity === "error") && <span class="tab-error">!</span>}
            {tab.id === "events" && props.events.length > 0 && <span class="tab-count">{Math.min(props.events.length, 99)}</span>}
          </button>
        ))}
        <span class={`save-chip save-${props.saveState}`}>{saveLabel(props.saveState)}</span>
      </div>
      <div class="tab-content scroll-region" data-testid="active-panel" role="tabpanel">
        {props.tab === "form" && <FormPanel document={props.document} diagnostics={props.diagnostics} editingLocked={props.editingLocked} onDocument={props.onDocument} />}
        {props.tab === "json" && (
          <div class="json-panel">
            <CodeEditor value={props.source} onChange={props.onSource} />
            {props.diagnostics.length > 0 && (
              <div class="json-diagnostic-strip">
                <Diagnostics diagnostics={props.diagnostics} />
              </div>
            )}
          </div>
        )}
        {props.tab === "simulation" && (
          <SimulationPanel
            simulation={props.simulation}
            simulationResult={props.simulationResult}
            selectedItem={props.selectedItem}
            onSimulation={props.onSimulation}
            onSimulateAction={props.onSimulateAction}
          />
        )}
        {props.tab === "events" && <EventsPanel events={props.events} />}
      </div>
    </section>
  );
}

function saveLabel(state: SaveState): string {
  switch (state) {
    case "dirty": return "Modifications locales";
    case "validating": return "Validation…";
    case "saving": return "Enregistrement…";
    case "saved": return "Enregistré";
    case "conflict": return "Conflit de révision";
    case "error": return "À corriger";
    default: return "Prêt";
  }
}
