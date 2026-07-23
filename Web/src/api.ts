import type {
  ConfigEnvelope,
  ApplicationCatalog,
  Diagnostic,
  JsonObject,
  JsonSchema,
  ServerStatus,
  SimulationContext,
  SocketEvent,
  TouchBarCalibrationState,
  ValidationEnvelope,
} from "./types";

export class ApiError extends Error {
  constructor(
    message: string,
    readonly status: number,
    readonly payload?: unknown,
  ) {
    super(message);
  }
}

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const response = await fetch(path, {
    credentials: "same-origin",
    cache: "no-store",
    ...init,
    headers: {
      Accept: "application/json",
      ...(init?.body ? { "Content-Type": "application/json" } : {}),
      ...init?.headers,
    },
  });
  const contentType = response.headers.get("content-type") ?? "";
  const payload = contentType.includes("json") ? await response.json() : await response.text();
  if (!response.ok) {
    const detail = typeof payload === "object" && payload && "message" in payload
      ? String((payload as { message: unknown }).message)
      : response.statusText;
    throw new ApiError(detail || `Erreur HTTP ${response.status}`, response.status, payload);
  }
  return payload as T;
}

export const api = {
  session: () => request<{ ok: true }>("/api/v1/session"),
  status: () => request<ServerStatus>("/api/v1/status"),
  schema: () => request<JsonSchema>("/api/v1/schema"),
  config: () => request<ConfigEnvelope>("/api/v1/config"),
  applications: () => request<ApplicationCatalog>("/api/v1/applications"),
  validate: (source: string) =>
    request<ValidationEnvelope>("/api/v1/validate", {
      method: "POST",
      body: JSON.stringify({ source }),
    }),
  save: (source: string, revision: number) =>
    request<ConfigEnvelope>("/api/v1/config", {
      method: "PUT",
      headers: { "If-Match": `"${revision}"` },
      body: JSON.stringify({ source }),
    }),
  setSimulationContext: (context: SimulationContext) =>
    request<{ context: SimulationContext }>("/api/v1/preview/context", {
      method: "POST",
      body: JSON.stringify(context),
    }),
  simulateAction: (body: { itemID?: string; trigger?: string; action?: JsonObject }) =>
    request<{ executed: false; description: string; event?: SocketEvent }>("/api/v1/preview/action", {
      method: "POST",
      body: JSON.stringify(body),
    }),
  setTouchBarCalibration: (body: {
    active: boolean;
    centerOffset?: number;
    pointsPerMillimeter?: number;
  }) =>
    request<{ state: TouchBarCalibrationState }>("/api/v1/touchbar/calibration", {
      method: "POST",
      body: JSON.stringify(body),
    }),
};

export function diagnosticsFromError(error: unknown): Diagnostic[] {
  if (error instanceof ApiError && error.payload && typeof error.payload === "object") {
    const values = (error.payload as { diagnostics?: unknown }).diagnostics;
    if (Array.isArray(values)) return values as Diagnostic[];
  }
  return [{
    severity: "error",
    message: error instanceof Error ? error.message : "Erreur inconnue",
  }];
}

export interface SocketController {
  close(): void;
}

export function connectEvents(
  onEvent: (event: SocketEvent) => void,
  onState: (connected: boolean) => void,
): SocketController {
  let socket: WebSocket | undefined;
  let retryTimer: number | undefined;
  let retryDelay = 750;
  let closed = false;

  const connect = () => {
    if (closed) return;
    const protocol = window.location.protocol === "https:" ? "wss:" : "ws:";
    const url = `${protocol}//${window.location.host}/api/v1/events`;
    socket = new WebSocket(url);
    socket.addEventListener("open", () => {
      retryDelay = 750;
      onState(true);
    });
    socket.addEventListener("message", (message) => {
      try {
        const event = JSON.parse(String(message.data)) as SocketEvent;
        if (event && typeof event.type === "string") onEvent(event);
      } catch {
        onEvent({ type: "client.invalid-event", payload: String(message.data), timestamp: new Date().toISOString() });
      }
    });
    socket.addEventListener("close", () => {
      onState(false);
      if (!closed) {
        retryTimer = window.setTimeout(connect, retryDelay);
        retryDelay = Math.min(Math.round(retryDelay * 1.7), 15_000);
      }
    });
    socket.addEventListener("error", () => socket?.close());
  };

  connect();
  return {
    close() {
      closed = true;
      if (retryTimer !== undefined) window.clearTimeout(retryTimer);
      socket?.close();
    },
  };
}
