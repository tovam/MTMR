import { useCallback, useEffect, useMemo, useRef, useState } from "preact/hooks";
import { ApiError, api, connectEvents, diagnosticsFromError } from "./api";
import {
  EMPTY_DOCUMENT,
  cloneDocument,
  createID,
  findItem,
  flattenItems,
  isRecord,
  parseSource,
  stableSource,
} from "./model";
import type {
  ConfigDocument,
  ConnectionState,
  Diagnostic,
  EventRecord,
  HistoryState,
  JsonObject,
  JsonSchema,
  SaveState,
  ServerStatus,
  SimulationContext,
  SocketEvent,
} from "./types";

const MAX_HISTORY = 100;
const MAX_EVENTS = 250;

const DEFAULT_STATUS: ServerStatus = {
  version: "—",
  port: 8787,
  configPath: "~/.mtmr.json",
  revision: 0,
  valid: false,
};

const DEFAULT_SIMULATION: SimulationContext = {
  application: "Finder",
  battery: 72,
  networkConnected: true,
  theme: "dark",
  time: "12:34",
};

function eventDetail(type: string, payload: unknown): string {
  if (type === "server.error" && isRecord(payload) && typeof payload.code === "string" && payload.code.startsWith("input.")) {
    const message = typeof payload.message === "string"
      ? payload.message.replace(/[\u0000-\u001f\u007f]/gu, " ").slice(0, 220)
      : "Autorisation système requise.";
    return `${payload.code}: ${message}`;
  }
  if (type === "runtime.snapshot") return "Aperçu natif actualisé.";
  if (type === "config.changed") return "Configuration actualisée.";
  if (type === "config.invalid") return "Configuration invalide.";
  if (type === "simulation.changed") return "Contexte visuel actualisé, sans effet système.";
  return payload === undefined ? "" : "Événement reçu sans contenu affiché.";
}

function mergeSimulationContext(base: SimulationContext, candidate: JsonObject): SimulationContext {
  const next = { ...base };
  if (typeof candidate.application === "string") next.application = candidate.application;
  if (typeof candidate.battery === "number" && Number.isFinite(candidate.battery)) {
    next.battery = Math.max(0, Math.min(100, Math.round(candidate.battery)));
  }
  if (typeof candidate.networkConnected === "boolean") next.networkConnected = candidate.networkConnected;
  if (candidate.theme === "dark" || candidate.theme === "light") next.theme = candidate.theme;
  if (typeof candidate.time === "string") {
    const clock = candidate.time.match(/(?:T|^)(\d{2}:\d{2})/u)?.[1];
    next.time = clock ?? candidate.time;
  }
  if (typeof candidate.inputAccess === "boolean") next.inputAccess = candidate.inputAccess;
  return next;
}

function mergeRuntimeSnapshot(current: JsonObject | undefined, incoming: JsonObject): JsonObject {
  const next: JsonObject = { ...(current ?? {}), ...incoming };
  if (!Array.isArray(incoming.items)) return next;
  const previousByID = new Map<string, JsonObject>();
  if (Array.isArray(current?.items)) {
    current.items.forEach((candidate) => {
      if (isRecord(candidate) && typeof candidate.id === "string") previousByID.set(candidate.id, candidate);
    });
  }
  next.items = incoming.items.map((candidate) => {
    if (!isRecord(candidate) || typeof candidate.id !== "string") return candidate;
    const merged: JsonObject = { ...(previousByID.get(candidate.id) ?? {}), ...candidate };
    for (const nullableField of ["renderedImage", "title"]) {
      if (Object.prototype.hasOwnProperty.call(candidate, nullableField) && candidate[nullableField] === null) {
        delete merged[nullableField];
      }
    }
    return merged;
  });
  return next;
}

export function useEditorState() {
  const [status, setStatus] = useState<ServerStatus>(DEFAULT_STATUS);
  const [schema, setSchema] = useState<JsonSchema>();
  const [history, setHistory] = useState<HistoryState>({
    past: [],
    present: cloneDocument(EMPTY_DOCUMENT),
    future: [],
  });
  const [rawSource, setRawSourceState] = useState(stableSource(EMPTY_DOCUMENT));
  const [serverSource, setServerSource] = useState("");
  const [revision, setRevision] = useState(0);
  const [diagnostics, setDiagnostics] = useState<Diagnostic[]>([]);
  const [connection, setConnection] = useState<ConnectionState>("connecting");
  const [saveState, setSaveState] = useState<SaveState>("idle");
  const [selectedID, setSelectedID] = useState<string>();
  const [events, setEvents] = useState<EventRecord[]>([]);
  const [runtimeContext, setRuntimeContext] = useState<SimulationContext>(DEFAULT_SIMULATION);
  const [simulationOverride, setSimulationOverride] = useState<SimulationContext>();
  const [simulationResult, setSimulationResult] = useState("Aucune action décrite.");
  const [runtimeSnapshot, setRuntimeSnapshot] = useState<JsonObject>();
  const [initialized, setInitialized] = useState(false);
  const [sessionReady, setSessionReady] = useState(false);
  const dirtyRef = useRef(false);
  const revisionRef = useRef(revision);
  const sourceRef = useRef(rawSource);
  const serverSourceRef = useRef(serverSource);
  const saveSequence = useRef(0);
  const saveInFlightRef = useRef(false);
  const pendingSaveRef = useRef(false);
  const saveRef = useRef<(source?: string) => Promise<void>>(async () => {});
  const runtimeContextRef = useRef<SimulationContext>(DEFAULT_SIMULATION);
  const simulation = simulationOverride ?? runtimeContext;

  useEffect(() => { revisionRef.current = revision; }, [revision]);
  useEffect(() => { sourceRef.current = rawSource; }, [rawSource]);

  const appendEvent = useCallback((type: string, detail = "", time = new Date().toISOString()) => {
    setEvents((current) => {
      const first = current[0];
      const closeInTime = first && Math.abs(new Date(time).getTime() - new Date(first.time).getTime()) < 5_000;
      if (first?.type === type && first.detail === detail && closeInTime) {
        return [{ ...first, time, count: (first.count ?? 1) + 1 }, ...current.slice(1)];
      }
      return [{ id: createID("event"), type, detail, time, count: 1 }, ...current].slice(0, MAX_EVENTS);
    });
  }, []);

  const acceptEnvelope = useCallback((envelope: {
    source: string;
    document?: ConfigDocument;
    revision: number;
    diagnostics?: Diagnostic[];
    valid: boolean;
  }, resetHistory = true) => {
    const parsed = envelope.document ? { document: envelope.document, diagnostics: envelope.diagnostics ?? [] } : parseSource(envelope.source);
    const document = parsed.document;
    saveSequence.current += 1;
    setRawSourceState(envelope.source);
    setServerSource(envelope.source);
    sourceRef.current = envelope.source;
    serverSourceRef.current = envelope.source;
    setRevision(envelope.revision);
    revisionRef.current = envelope.revision;
    setDiagnostics(envelope.diagnostics ?? parsed.diagnostics);
    setStatus((current) => ({ ...current, revision: envelope.revision, valid: envelope.valid }));
    dirtyRef.current = false;
    setSaveState(envelope.valid ? "saved" : "error");
    if (document) {
      setHistory((current) => resetHistory
        ? { past: [], present: cloneDocument(document), future: [] }
        : { ...current, present: cloneDocument(document) });
      setSelectedID((current) => findItem(document, current)?.id ?? flattenItems(document.items)[0]?.id);
    }
  }, []);

  const loadConfig = useCallback(async (reason = "config.loaded", discardDraft = false) => {
    const requestSequence = saveSequence.current;
    if (!discardDraft && dirtyRef.current) return;
    try {
      const envelope = await api.config();

      // A WebSocket notification and its follow-up GET race with normal typing.
      // Never let an asynchronous response replace a draft created while that
      // request was in flight. Keep the new revision so a save becomes an
      // explicit conflict instead of silently overwriting external work.
      if (saveSequence.current !== requestSequence || (!discardDraft && dirtyRef.current)) {
        if (envelope.revision > revisionRef.current) {
          setServerSource(envelope.source);
          serverSourceRef.current = envelope.source;
          setStatus((current) => ({ ...current, revision: envelope.revision, valid: envelope.valid }));
          dirtyRef.current = sourceRef.current !== envelope.source;
          // Keep the draft's base revision while it differs from the external
          // source. A manual save must use that older If-Match and receive 409;
          // adopting the new revision here would silently overwrite the file.
          if (!dirtyRef.current) {
            setRevision(envelope.revision);
            revisionRef.current = envelope.revision;
          }
          setSaveState(dirtyRef.current ? "conflict" : "saved");
          if (dirtyRef.current) {
            setDiagnostics((current) => [{
              severity: "warning",
              message: "La configuration a changé ailleurs. Rechargez-la ou conservez votre brouillon avant d’enregistrer.",
              code: "revision-conflict",
            }, ...current.filter((entry) => entry.code !== "revision-conflict")]);
          }
        }
        return;
      }
      if (envelope.revision < revisionRef.current) return;
      acceptEnvelope(envelope);
      appendEvent(reason, `révision ${envelope.revision}`);
    } catch (error) {
      setDiagnostics(diagnosticsFromError(error));
      setSaveState("error");
      appendEvent("client.error", error instanceof Error ? error.message : String(error));
    }
  }, [acceptEnvelope, appendEvent]);

  useEffect(() => {
    let active = true;
    void (async () => {
      try {
        await api.session();
        if (!active) return;
      } catch (error) {
        if (!active) return;
        setDiagnostics(diagnosticsFromError(error));
        setSaveState("error");
        setConnection("disconnected");
        appendEvent("server.session.error", error instanceof Error ? error.message : String(error));
        setInitialized(true);
        return;
      }

      const [statusResult, schemaResult, configResult] = await Promise.allSettled([api.status(), api.schema(), api.config()]);
      if (!active) return;
      if (statusResult.status === "fulfilled") setStatus(statusResult.value);
      else appendEvent("server.status.error", String(statusResult.reason));
      if (schemaResult.status === "fulfilled") setSchema(schemaResult.value);
      else appendEvent("server.schema.error", String(schemaResult.reason));
      if (configResult.status === "fulfilled") {
        acceptEnvelope(configResult.value);
        appendEvent("config.loaded", `révision ${configResult.value.revision}`);
      } else {
        setDiagnostics(diagnosticsFromError(configResult.reason));
        setSaveState("error");
      }
      setSessionReady(true);
      setInitialized(true);
    })();
    return () => { active = false; };
  }, [acceptEnvelope, appendEvent]);

  useEffect(() => {
    if (!sessionReady) return;
    const controller = connectEvents(
      (event: SocketEvent) => {
        const payload = event.payload;
        appendEvent(event.type, eventDetail(event.type, payload), event.timestamp);
        if (event.type === "runtime.snapshot" && isRecord(payload)) {
          setRuntimeSnapshot((current) => mergeRuntimeSnapshot(current, payload));
          if (isRecord(payload.context)) {
            setRuntimeContext((current) => {
              const next = mergeSimulationContext(current, payload.context as JsonObject);
              runtimeContextRef.current = next;
              return next;
            });
          }
          return;
        }
        if (event.type === "simulation.changed" && isRecord(payload)) {
          if (payload.kind === "context" && isRecord(payload.context)) {
            setSimulationOverride((current) => mergeSimulationContext(current ?? runtimeContextRef.current, payload.context as JsonObject));
          } else if (payload.kind === "action" && typeof payload.description === "string") {
            setSimulationResult(payload.description);
          }
          return;
        }
        if (!["config.changed", "config.invalid"].includes(event.type)) return;
        if (saveInFlightRef.current) return;
        const incomingRevision = event.revision;
        if (incomingRevision !== undefined && incomingRevision <= revisionRef.current) return;
        if (dirtyRef.current) {
          if (incomingRevision !== revisionRef.current) {
            setSaveState("conflict");
            setDiagnostics((current) => [{
              severity: "warning",
              message: "La configuration a changé ailleurs. Rechargez-la ou conservez votre brouillon avant d’enregistrer.",
              code: "revision-conflict",
            }, ...current.filter((entry) => entry.code !== "revision-conflict")]);
          }
          return;
        }
        void loadConfig(event.type);
      },
      (connected) => setConnection(connected ? "connected" : "disconnected"),
    );
    return () => controller.close();
  }, [appendEvent, loadConfig, sessionReady]);

  const commitDocument = useCallback((document: ConfigDocument, eventType = "draft.changed") => {
    if (!parseSource(sourceRef.current).document) {
      setSaveState("error");
      appendEvent("draft.blocked", "Corrigez ou annulez d’abord le brouillon JSON invalide.");
      return;
    }
    const next = cloneDocument(document);
    const source = stableSource(next);
    const local = parseSource(source);
    saveSequence.current += 1;
    setHistory((current) => ({
      past: [...current.past, cloneDocument(current.present)].slice(-MAX_HISTORY),
      present: next,
      future: [],
    }));
    setRawSourceState(source);
    sourceRef.current = source;
    setDiagnostics(local.diagnostics);
    dirtyRef.current = source !== serverSourceRef.current;
    setSaveState(source === serverSourceRef.current ? "saved" : "dirty");
    appendEvent(eventType);
  }, [appendEvent]);

  const updateDocument = useCallback((recipe: (draft: ConfigDocument) => void, eventType?: string) => {
    const next = cloneDocument(history.present);
    recipe(next);
    commitDocument(next, eventType);
  }, [commitDocument, history.present]);

  const setRawSource = useCallback((source: string) => {
    saveSequence.current += 1;
    setRawSourceState(source);
    sourceRef.current = source;
    const parsed = parseSource(source);
    setDiagnostics(parsed.diagnostics);
    dirtyRef.current = source !== serverSourceRef.current;
    setSaveState(parsed.document ? (source === serverSourceRef.current ? "saved" : "dirty") : "error");
    if (parsed.document) {
      setHistory((current) => {
        if (stableSource(current.present) === stableSource(parsed.document!)) return current;
        return {
          past: [...current.past, cloneDocument(current.present)].slice(-MAX_HISTORY),
          present: cloneDocument(parsed.document!),
          future: [],
        };
      });
      setSelectedID((current) => findItem(parsed.document!, current)?.id ?? flattenItems(parsed.document!.items)[0]?.id);
    }
  }, []);

  const save = useCallback(async (requestedSource?: string) => {
    if (saveInFlightRef.current) {
      pendingSaveRef.current = true;
      return;
    }
    const source = requestedSource ?? sourceRef.current;
    const sequence = saveSequence.current;
    const local = parseSource(source);
    if (!local.document) {
      setDiagnostics(local.diagnostics);
      setSaveState("error");
      return;
    }
    saveInFlightRef.current = true;
    setSaveState("validating");
    try {
      const validation = await api.validate(source);
      if (sequence !== saveSequence.current || sourceRef.current !== source) return;
      setDiagnostics(validation.diagnostics ?? []);
      if (!validation.valid) {
        setSaveState("error");
        return;
      }
      setSaveState("saving");
      const envelope = await api.save(source, revisionRef.current);
      if (sequence === saveSequence.current && sourceRef.current === source) {
        acceptEnvelope(envelope, false);
        appendEvent("config.saved", `révision ${envelope.revision}`);
      } else {
        if (envelope.revision >= revisionRef.current) {
          setServerSource(envelope.source);
          serverSourceRef.current = envelope.source;
          setRevision(envelope.revision);
          revisionRef.current = envelope.revision;
          setStatus((current) => ({ ...current, revision: envelope.revision, valid: envelope.valid }));
        }
        dirtyRef.current = sourceRef.current !== serverSourceRef.current;
        setSaveState(dirtyRef.current ? "dirty" : "saved");
        appendEvent("config.saved", `révision ${envelope.revision} · brouillon plus récent conservé`);
      }
    } catch (error) {
      if (sequence === saveSequence.current && sourceRef.current === source) {
        setDiagnostics(diagnosticsFromError(error));
        setSaveState(error instanceof ApiError && error.status === 409 ? "conflict" : "error");
        appendEvent("config.save.error", error instanceof Error ? error.message : String(error));
      }
    } finally {
      saveInFlightRef.current = false;
      if (pendingSaveRef.current) {
        pendingSaveRef.current = false;
        queueMicrotask(() => void saveRef.current(sourceRef.current));
      }
    }
  }, [acceptEnvelope, appendEvent]);
  saveRef.current = save;

  useEffect(() => {
    if (!initialized || saveState !== "dirty") return;
    const parsed = parseSource(rawSource);
    if (!parsed.document || parsed.diagnostics.some((entry) => entry.severity === "error")) return;
    const timer = window.setTimeout(() => void save(rawSource), 600);
    return () => window.clearTimeout(timer);
  }, [initialized, rawSource, save, saveState]);

  const undo = useCallback(() => {
    setHistory((current) => {
      const previous = current.past.at(-1);
      if (!previous) return current;
      const next = {
        past: current.past.slice(0, -1),
        present: cloneDocument(previous),
        future: [cloneDocument(current.present), ...current.future].slice(0, MAX_HISTORY),
      };
      const source = stableSource(next.present);
      saveSequence.current += 1;
      setRawSourceState(source);
      sourceRef.current = source;
      dirtyRef.current = source !== serverSourceRef.current;
      setSaveState(source === serverSourceRef.current ? "saved" : "dirty");
      setDiagnostics([]);
      return next;
    });
  }, []);

  const redo = useCallback(() => {
    setHistory((current) => {
      const [following, ...rest] = current.future;
      if (!following) return current;
      const next = {
        past: [...current.past, cloneDocument(current.present)].slice(-MAX_HISTORY),
        present: cloneDocument(following),
        future: rest,
      };
      const source = stableSource(next.present);
      saveSequence.current += 1;
      setRawSourceState(source);
      sourceRef.current = source;
      dirtyRef.current = source !== serverSourceRef.current;
      setSaveState(source === serverSourceRef.current ? "saved" : "dirty");
      setDiagnostics([]);
      return next;
    });
  }, []);

  const updateSimulation = useCallback(async (context: SimulationContext) => {
    setSimulationOverride(context);
    try {
      const response = await api.setSimulationContext(context);
      setSimulationOverride(mergeSimulationContext(context, response.context ?? context));
      appendEvent("simulation.changed", "Contexte visuel personnalisé.");
    } catch (error) {
      appendEvent("simulation.error", error instanceof Error ? error.message : String(error));
    }
  }, [appendEvent]);

  const simulateAction = useCallback(async (itemID: string | undefined, trigger = "singleTap") => {
    const item = findItem(history.present, itemID);
    const action = item?.actions?.find((candidate) => candidate.trigger === trigger) ?? item?.actions?.[0];
    try {
      const response = await api.simulateAction({ itemID, trigger, action });
      setSimulationResult(response.description || "Action décrite, sans exécution.");
      appendEvent("simulation.action", "Action décrite, sans exécution.");
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      setSimulationResult(message);
      appendEvent("simulation.error", message);
    }
  }, [appendEvent, history.present]);

  const beginSimulation = useCallback(() => {
    setSimulationOverride((current) => current ?? runtimeContextRef.current);
    appendEvent("simulation.local", "Contexte visuel personnalisé.");
  }, [appendEvent]);

  const resetSimulation = useCallback(() => {
    setSimulationOverride(undefined);
    setSimulationResult("Aucune action décrite.");
    appendEvent("simulation.local", "Retour au mode Direct.");
  }, [appendEvent]);

  const selectedItem = useMemo(
    () => findItem(history.present, selectedID),
    [history.present, selectedID],
  );
  const formLocked = useMemo(
    () => !parseSource(rawSource).document,
    [rawSource],
  );

  return {
    status,
    schema,
    document: history.present,
    rawSource,
    revision,
    diagnostics,
    connection,
    saveState,
    selectedID,
    selectedItem,
    events,
    simulation,
    simulationDirect: simulationOverride === undefined,
    simulationResult,
    runtimeSnapshot,
    formLocked,
    canUndo: history.past.length > 0,
    canRedo: history.future.length > 0,
    initialized,
    select: setSelectedID,
    commitDocument,
    updateDocument,
    setRawSource,
    save: () => save(),
    reload: () => loadConfig("config.reloaded", true),
    undo,
    redo,
    updateSimulation,
    beginSimulation,
    resetSimulation,
    simulateAction,
  };
}
