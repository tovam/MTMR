import { useEffect, useState } from "preact/hooks";
import { itemEditorName } from "../model";
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
  simulationDirect: boolean;
  simulationResult: string;
  selectedItem?: ItemConfig;
  saveState: SaveState;
  editingLocked?: boolean;
  onTab(tab: EditorTab): void;
  onSource(source: string): void;
  onDocument(document: ConfigDocument): void;
  onSelectItem(id: string): void;
  onSimulation(context: SimulationContext): void;
  onBeginSimulation(): void;
  onResetSimulation(): void;
  onSimulateAction(itemID?: string, trigger?: string): void;
}

const TABS: Array<{ id: EditorTab; label: string }> = [
  { id: "form", label: "Formulaire" },
  { id: "json", label: "JSON" },
  { id: "simulation", label: "Aperçu" },
  { id: "events", label: "Journal" },
];

function FormPanel({
  document,
  diagnostics,
  onDocument,
  onSelectItem,
  editingLocked,
}: Pick<WorkspacePanelsProps, "document" | "diagnostics" | "onDocument" | "onSelectItem" | "editingLocked">) {
  return (
    <div class="form-layout simplified-form">
      {editingLocked && (
        <div class="draft-lock-banner" role="alert">
          Le brouillon JSON est invalide. Corrigez-le dans l’onglet JSON ou utilisez Annuler avant de modifier la barre visuellement.
        </div>
      )}
      <section class="content-card full-width document-summary">
        <div class="document-summary-heading">
          <div><span class="eyebrow">Document</span><h3>Configuration</h3></div>
          <div class="document-facts">
            <span>format v{document.formatVersion}</span>
            <span>{document.items.length} élément{document.items.length > 1 ? "s" : ""}</span>
          </div>
        </div>
        <label class="property-field document-notes">
          <span class="field-label">Note générale <small>facultative</small></span>
          <textarea
            rows={2}
            placeholder="Notes sur cette configuration…"
            disabled={editingLocked}
            value={document.notes ?? ""}
            onInput={(event) => onDocument({ ...document, notes: event.currentTarget.value || undefined })}
          />
        </label>
      </section>
      <section class="content-card full-width">
        <div class="card-heading">
          <div>
            <span class="eyebrow">Barre</span>
            <h3>Ordre des éléments</h3>
          </div>
          <span class="section-subtitle">Cliquez une ligne pour l’ouvrir dans l’inspecteur.</span>
        </div>
        <div class="item-table" role="table" aria-label="Éléments configurés">
          {document.items.map((item, index) => (
            <button
              type="button"
              class="item-row"
              role="row"
              key={item.id}
              onClick={() => onSelectItem(item.id)}
              disabled={editingLocked}
              title={`Inspecter ${itemEditorName(item)}`}
            >
              <span class="row-index">{String(index + 1).padStart(2, "0")}</span>
              <strong>{itemEditorName(item)}</strong>
              <code>{item.type}</code>
              <span>{item.align ?? "left"}</span>
              <span class={item.enabled === false ? "status-disabled" : "status-enabled"}>
                {item.enabled === false ? "désactivé" : "actif"}
              </span>
            </button>
          ))}
          {document.items.length === 0 && <div class="empty-state compact">La barre est vide.</div>}
        </div>
      </section>
      {diagnostics.length > 0 && (
        <section class="content-card full-width">
          <div class="card-heading">
            <div><span class="eyebrow">Validation</span><h3>À vérifier</h3></div>
            <span class={`count-pill ${diagnostics.some((entry) => entry.severity === "error") ? "count-error" : ""}`}>{diagnostics.length}</span>
          </div>
          <Diagnostics diagnostics={diagnostics} />
        </section>
      )}
    </div>
  );
}

function SimulationPanel({
  simulation,
  simulationDirect,
  simulationResult,
  selectedItem,
  onSimulation,
  onBeginSimulation,
  onResetSimulation,
  onSimulateAction,
}: Pick<WorkspacePanelsProps, "simulation" | "simulationDirect" | "simulationResult" | "selectedItem" | "onSimulation" | "onBeginSimulation" | "onResetSimulation" | "onSimulateAction">) {
  const [draft, setDraft] = useState(simulation);
  const [trigger, setTrigger] = useState("singleTap");
  useEffect(() => setDraft(simulation), [simulation]);
  return (
    <div class="simulation-grid preview-mode-panel">
      <section class="content-card preview-mode-intro full-width">
        <div>
          <span class="eyebrow">Aperçu visuel</span>
          <h3>{simulationDirect ? "Mode Direct" : "Contexte personnalisé"}</h3>
          <p>
            {simulationDirect
              ? "La barre reflète les valeurs envoyées par MMTMR. Cliquer un élément ne déclenche jamais son action sur le Mac."
              : "Vous testez uniquement l’apparence avec des valeurs locales. La configuration et le système restent inchangés."}
          </p>
        </div>
        <div class="mode-segment" aria-label="Mode d’aperçu">
          <button type="button" class={simulationDirect ? "is-active" : ""} aria-pressed={simulationDirect} onClick={onResetSimulation}>Direct</button>
          <button type="button" class={!simulationDirect ? "is-active" : ""} aria-pressed={!simulationDirect} onClick={onBeginSimulation}>Personnalisé</button>
        </div>
      </section>
      <section class="content-card">
        <div class="card-heading">
          <div>
            <span class="eyebrow">Valeurs affichées</span>
            <h3>{simulationDirect ? "Contexte reçu" : "Contexte de test"}</h3>
          </div>
          <span class="safe-badge">Visuel uniquement</span>
        </div>
        <label class="property-field">
          <span class="field-label">Application active</span>
          <input disabled={simulationDirect} value={draft.application} onInput={(event) => setDraft({ ...draft, application: event.currentTarget.value })} />
        </label>
        <label class="property-field">
          <span class="field-label">Batterie · {draft.battery}%</span>
          <input disabled={simulationDirect} type="range" min="0" max="100" value={draft.battery} onInput={(event) => setDraft({ ...draft, battery: Number(event.currentTarget.value) })} />
        </label>
        <label class="property-field">
          <span class="field-label">Heure</span>
          <input disabled={simulationDirect} type="time" value={draft.time} onInput={(event) => setDraft({ ...draft, time: event.currentTarget.value })} />
        </label>
        <div class="inline-fields">
          <label class="property-field">
            <span class="field-label">Thème</span>
            <select disabled={simulationDirect} value={draft.theme} onChange={(event) => setDraft({ ...draft, theme: event.currentTarget.value as "dark" | "light" })}>
              <option value="dark">Sombre</option>
              <option value="light">Clair</option>
            </select>
          </label>
          <label class="property-field">
            <span class="field-label">Réseau</span>
            <span class="switch-row">
              <input disabled={simulationDirect} type="checkbox" checked={draft.networkConnected} onChange={(event) => setDraft({ ...draft, networkConnected: event.currentTarget.checked })} />
              <span>{draft.networkConnected ? "Connecté" : "Déconnecté"}</span>
            </span>
          </label>
        </div>
        {simulationDirect ? (
          <button class="secondary-button" onClick={onBeginSimulation}>Créer un contexte personnalisé</button>
        ) : (
          <div class="simulation-buttons">
            <button class="primary-button" onClick={() => onSimulation(draft)}>Appliquer à l’aperçu</button>
            <button class="secondary-button" onClick={onResetSimulation}>Revenir au Direct</button>
          </div>
        )}
      </section>
      <section class="content-card">
        <div class="card-heading">
          <div>
            <span class="eyebrow">Test sans exécution</span>
            <h3>{selectedItem ? itemEditorName(selectedItem) : "Aucun élément"}</h3>
          </div>
        </div>
        <label class="property-field">
          <span class="field-label">Déclencheur</span>
          <select value={trigger} onChange={(event) => setTrigger(event.currentTarget.value)}>
            {["singleTap", "doubleTap", "tripleTap", "longTap"].map((value) => <option value={value}>{value}</option>)}
          </select>
        </label>
        <button class="secondary-button" disabled={!selectedItem} onClick={() => onSimulateAction(selectedItem?.id, trigger)}>
          Décrire l’action
        </button>
        <div class="simulation-result">
          <span class="eyebrow">Résultat descriptif</span>
          <p>{simulationResult}</p>
        </div>
        <p class="security-note">Ce bouton explique ce qui se passerait. Il n’exécute ni frappe, ni URL, ni AppleScript, ni script shell.</p>
      </section>
    </div>
  );
}

type EventCategory = "all" | "config" | "edit" | "preview" | "error";

function eventPresentation(event: EventRecord): { category: Exclude<EventCategory, "all">; label: string; detail: string; origin: string } {
  const revision = event.detail.match(/révision\s+\d+/iu)?.[0] ?? "";
  if (event.type.includes("error") || event.type === "config.invalid") {
    const inputMessage = event.type === "server.error" && event.detail.startsWith("input.") ? event.detail : undefined;
    return { category: "error", label: "Opération à vérifier", detail: inputMessage ?? "Le détail sensible est masqué. Consultez les diagnostics.", origin: "Reçu de MMTMR" };
  }
  if (event.type.startsWith("config.")) {
    const labels: Record<string, string> = {
      "config.loaded": "Configuration chargée",
      "config.saved": "Configuration enregistrée",
      "config.changed": "Configuration modifiée ailleurs",
    };
    return { category: "config", label: labels[event.type] ?? "Configuration actualisée", detail: revision, origin: event.type === "config.changed" ? "Reçu de MMTMR" : "Synchronisé avec MMTMR" };
  }
  if (event.type === "runtime.snapshot") {
    return { category: "preview", label: "Aperçu Direct actualisé", detail: "Géométrie et état visuel reçus.", origin: "Reçu de MMTMR" };
  }
  if (event.type.startsWith("simulation.")) {
    return { category: "preview", label: event.type === "simulation.action" ? "Action décrite" : "Contexte d’aperçu modifié", detail: "Aucun effet sur le Mac.", origin: ["simulation.action", "simulation.local"].includes(event.type) ? "Produit par l’éditeur" : "Synchronisé avec MMTMR" };
  }
  if (["item.", "document.", "draft."].some((prefix) => event.type.startsWith(prefix))) {
    return { category: "edit", label: "Brouillon modifié", detail: "Modification locale de l’éditeur.", origin: "Produit par l’éditeur" };
  }
  return { category: "edit", label: "Éditeur actualisé", detail: "Événement technique sans contenu affiché.", origin: "Produit par l’éditeur" };
}

function EventsPanel({ events }: { events: EventRecord[] }) {
  const [filter, setFilter] = useState<EventCategory>("all");
  const visibleEvents = events
    .map((event) => ({ event, presentation: eventPresentation(event) }))
    .filter(({ presentation }) => filter === "all" || presentation.category === filter);
  return (
    <div class="events-panel">
      <div class="events-intro">
        <div>
          <span class="eyebrow">Journal local</span>
          <h3>Ce que fait l’éditeur</h3>
          <p>Les événements répétitifs sont regroupés et les contenus de configuration, scripts et textes saisis ne sont jamais affichés ici.</p>
        </div>
        <span class="safe-badge">Lecture seule</span>
      </div>
      <div class="event-filters" aria-label="Filtrer le journal">
        {([
          ["all", "Tout"],
          ["config", "Configuration"],
          ["edit", "Édition"],
          ["preview", "Aperçu"],
          ["error", "Erreurs"],
        ] as Array<[EventCategory, string]>).map(([value, label]) => (
          <button type="button" class={filter === value ? "is-active" : ""} aria-pressed={filter === value} onClick={() => setFilter(value)} key={value}>{label}</button>
        ))}
      </div>
      {visibleEvents.length === 0 ? <div class="empty-state">Aucun événement dans cette catégorie.</div> : (
        <div class="event-list">
          {visibleEvents.map(({ event, presentation }) => (
            <div class={`event-row event-${presentation.category}`} key={event.id}>
              <time>{new Date(event.time).toLocaleTimeString("fr-FR", { hour: "2-digit", minute: "2-digit", second: "2-digit" })}</time>
              <span class="event-dot" aria-hidden="true" />
              <div>
                <strong>{presentation.label}</strong>
                {presentation.detail && <span>{presentation.detail}</span>}
                <small>{presentation.origin}</small>
              </div>
              {(event.count ?? 1) > 1 && <span class="event-count">×{event.count}</span>}
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
        {props.tab === "form" && (
          <FormPanel
            document={props.document}
            diagnostics={props.diagnostics}
            editingLocked={props.editingLocked}
            onDocument={props.onDocument}
            onSelectItem={props.onSelectItem}
          />
        )}
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
            simulationDirect={props.simulationDirect}
            simulationResult={props.simulationResult}
            selectedItem={props.selectedItem}
            onSimulation={props.onSimulation}
            onBeginSimulation={props.onBeginSimulation}
            onResetSimulation={props.onResetSimulation}
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
