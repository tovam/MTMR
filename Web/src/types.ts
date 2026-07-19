export type JsonPrimitive = string | number | boolean | null;
export type JsonValue = JsonPrimitive | JsonObject | JsonValue[];
export interface JsonObject {
  [key: string]: JsonValue | undefined;
}

export type Alignment = "left" | "center" | "right";
export type DiagnosticSeverity = "error" | "warning" | "info" | "information";

export interface ActionConfig extends JsonObject {
  trigger: string;
  action: string;
}

export interface PinnedApplicationConfig extends JsonObject {
  bundleIdentifier: string;
  path?: string;
  label?: string;
}

export interface ItemConfig extends JsonObject {
  id: string;
  type: string;
  editorName?: string;
  align?: Alignment;
  title?: string;
  notes?: string;
  enabled?: boolean;
  actions?: ActionConfig[];
  items?: ItemConfig[];
  applications?: PinnedApplicationConfig[];
}

export interface ConfigDocument extends JsonObject {
  $schema?: string;
  formatVersion: number;
  notes?: string;
  items: ItemConfig[];
}

export interface Diagnostic {
  severity: DiagnosticSeverity;
  message: string;
  path?: string;
  line?: number;
  column?: number;
  code?: string;
}

export interface ServerStatus {
  version: string;
  port: number;
  configPath: string;
  revision: number;
  valid: boolean;
  serverURL?: string;
}

export interface ConfigEnvelope {
  source: string;
  document?: ConfigDocument;
  revision: number;
  diagnostics: Diagnostic[];
  valid: boolean;
}

export interface ApplicationDescriptor {
  bundleIdentifier: string;
  name: string;
  path: string;
  icon?: string;
  installed: boolean;
  running: boolean;
  frontmost: boolean;
}

export interface ApplicationCatalog {
  applications: ApplicationDescriptor[];
  generatedAt: string;
}

export interface ValidationEnvelope {
  valid: boolean;
  document?: ConfigDocument;
  diagnostics: Diagnostic[];
}

export interface JsonSchema extends JsonObject {
  $id?: string;
  $ref?: string;
  title?: string;
  description?: string;
  type?: string | string[];
  properties?: Record<string, JsonSchema>;
  required?: string[];
  items?: JsonSchema;
  enum?: JsonValue[];
  const?: JsonValue;
  default?: JsonValue;
  oneOf?: JsonSchema[];
  anyOf?: JsonSchema[];
  allOf?: JsonSchema[];
  $defs?: Record<string, JsonSchema>;
  definitions?: Record<string, JsonSchema>;
  minimum?: number;
  maximum?: number;
  minLength?: number;
  maxLength?: number;
  readOnly?: boolean;
  examples?: JsonValue[];
}

export interface SocketEvent<T = JsonValue> {
  type: string;
  revision?: number;
  payload?: T;
  timestamp: string;
}

export type ConnectionState = "connecting" | "connected" | "disconnected";
export type SaveState = "idle" | "dirty" | "validating" | "saving" | "saved" | "error" | "conflict";
export type EditorTab = "form" | "json" | "simulation" | "events";

export interface SimulationContext extends JsonObject {
  application: string;
  battery: number;
  networkConnected: boolean;
  theme: "dark" | "light";
  time: string;
  inputAccess?: boolean;
}

export interface EventRecord {
  id: string;
  time: string;
  type: string;
  detail: string;
  count?: number;
}

export interface RuntimeItemGeometry extends JsonObject {
  id: string;
  x?: number;
  width?: number;
  height?: number;
  align?: Alignment;
  visible?: boolean;
  title?: string;
  renderedImage?: string;
  kind?: string;
}

export interface HistoryState {
  past: ConfigDocument[];
  present: ConfigDocument;
  future: ConfigDocument[];
}
