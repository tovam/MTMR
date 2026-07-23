import { useEffect, useRef, useState } from "preact/hooks";
import type {
  ConfigDocument,
  JsonObject,
  TouchBarCalibrationProfile,
  TouchBarCalibrationState,
} from "../types";

const DEFAULT_POINTS_PER_MILLIMETER = 4.27;
const GUIDE_WIDTH_MILLIMETERS = 30;

interface TouchBarCalibrationProps {
  document: ConfigDocument;
  runtimeSnapshot?: JsonObject;
  editingLocked?: boolean;
  onPreview(request: {
    active: boolean;
    centerOffset?: number;
    pointsPerMillimeter?: number;
  }): Promise<TouchBarCalibrationState | undefined>;
  onSave(document: ConfigDocument): Promise<void>;
}

function calibrationState(snapshot?: JsonObject): TouchBarCalibrationState | undefined {
  const candidate = snapshot?.touchBarLayout;
  if (!candidate || typeof candidate !== "object" || Array.isArray(candidate)) return undefined;
  const state = candidate as JsonObject;
  if (
    typeof state.active !== "boolean"
    || typeof state.hardwareModel !== "string"
    || (state.centerReference !== "touchBar" && state.centerReference !== "chassis")
    || typeof state.centerOffset !== "number"
    || typeof state.pointsPerMillimeter !== "number"
    || typeof state.guideWidthMillimeters !== "number"
    || typeof state.calibrated !== "boolean"
  ) return undefined;
  return state as TouchBarCalibrationState;
}

function rounded(value: number, precision = 2): number {
  const multiplier = 10 ** precision;
  return Math.round(value * multiplier) / multiplier;
}

export function TouchBarCalibration(props: TouchBarCalibrationProps) {
  const runtime = calibrationState(props.runtimeSnapshot);
  const hardwareModel = runtime?.hardwareModel || "default";
  const storedProfile = props.document.touchBarLayout?.calibrations?.[hardwareModel]
    ?? props.document.touchBarLayout?.calibrations?.default;
  const initialProfile: TouchBarCalibrationProfile = storedProfile ?? {
    centerOffset: runtime?.centerOffset ?? 0,
    pointsPerMillimeter: runtime?.pointsPerMillimeter ?? DEFAULT_POINTS_PER_MILLIMETER,
  };
  const [active, setActive] = useState(runtime?.active ?? false);
  const [centerOffset, setCenterOffset] = useState(initialProfile.centerOffset);
  const [pointsPerMillimeter, setPointsPerMillimeter] = useState(
    initialProfile.pointsPerMillimeter,
  );
  const activeRef = useRef(active);
  const previewTimer = useRef<number>();

  useEffect(() => {
    activeRef.current = active;
  }, [active]);

  useEffect(() => {
    if (active) return;
    setCenterOffset(storedProfile?.centerOffset ?? runtime?.centerOffset ?? 0);
    setPointsPerMillimeter(
      storedProfile?.pointsPerMillimeter
        ?? runtime?.pointsPerMillimeter
        ?? DEFAULT_POINTS_PER_MILLIMETER,
    );
  }, [
    active,
    hardwareModel,
    runtime?.centerOffset,
    runtime?.pointsPerMillimeter,
    storedProfile?.centerOffset,
    storedProfile?.pointsPerMillimeter,
  ]);

  useEffect(() => () => {
    if (previewTimer.current !== undefined) window.clearTimeout(previewTimer.current);
    if (activeRef.current) void props.onPreview({ active: false });
  }, [props.onPreview]);

  const sendPreview = (
    nextOffset: number,
    nextPointsPerMillimeter = pointsPerMillimeter,
    immediate = false,
  ) => {
    if (previewTimer.current !== undefined) window.clearTimeout(previewTimer.current);
    const request = () => void props.onPreview({
      active: true,
      centerOffset: nextOffset,
      pointsPerMillimeter: nextPointsPerMillimeter,
    });
    if (immediate) request();
    else previewTimer.current = window.setTimeout(request, 45);
  };

  const moveTo = (value: number, immediate = false) => {
    const next = rounded(Math.max(-300, Math.min(300, value)), 1);
    setCenterOffset(next);
    sendPreview(next, pointsPerMillimeter, immediate);
  };

  const begin = async () => {
    if (props.editingLocked) return;
    setActive(true);
    activeRef.current = true;
    await props.onPreview({
      active: true,
      centerOffset,
      pointsPerMillimeter,
    });
  };

  const cancel = async () => {
    if (previewTimer.current !== undefined) window.clearTimeout(previewTimer.current);
    const original = storedProfile ?? initialProfile;
    setCenterOffset(original.centerOffset);
    setPointsPerMillimeter(original.pointsPerMillimeter);
    setActive(false);
    activeRef.current = false;
    await props.onPreview({ active: false });
  };

  const save = async () => {
    if (props.editingLocked) return;
    if (previewTimer.current !== undefined) window.clearTimeout(previewTimer.current);
    await props.onPreview({
      active: true,
      centerOffset,
      pointsPerMillimeter,
    });
    const calibrations = {
      ...(props.document.touchBarLayout?.calibrations ?? {}),
      [hardwareModel]: {
        centerOffset: rounded(centerOffset, 1),
        pointsPerMillimeter: rounded(pointsPerMillimeter, 3),
      },
    };
    await props.onSave({
      ...props.document,
      touchBarLayout: {
        centerReference: "chassis",
        calibrations,
      },
    });
    setActive(false);
    activeRef.current = false;
    await props.onPreview({ active: false });
  };

  const guideWidthPoints = GUIDE_WIDTH_MILLIMETERS * pointsPerMillimeter;

  return (
    <section class={`content-card full-width calibration-card ${active ? "is-calibrating" : ""}`}>
      <div class="calibration-heading">
        <div>
          <span class="eyebrow">Position physique</span>
          <h3>Centre du châssis</h3>
          <p>
            Alignez la ligne rouge sous le milieu du texte « MacBook Pro ». La zone rouge
            mesure 3 cm, soit 1,5 cm de chaque côté.
          </p>
        </div>
        <div class="calibration-profile">
          <span>{hardwareModel === "default" ? "Profil générique" : hardwareModel}</span>
          <strong>
            {storedProfile ? "Calibré" : runtime?.calibrated ? "Calibré" : "À calibrer"}
          </strong>
        </div>
      </div>

      <div class="calibration-ruler" aria-label="Aperçu du repère de calibration">
        <span
          class="calibration-guide-band"
          style={{
            width: `${Math.min(55, Math.max(18, guideWidthPoints / 5))}%`,
            transform: `translateX(calc(-50% + ${centerOffset / 5}px))`,
          }}
        >
          <i class="calibration-guide-edge calibration-guide-edge-left" />
          <i class="calibration-guide-center" />
          <i class="calibration-guide-edge calibration-guide-edge-right" />
        </span>
      </div>

      {!active ? (
        <div class="calibration-idle">
          <div>
            <span>Décalage enregistré</span>
            <strong>{storedProfile?.centerOffset.toFixed(1) ?? "0.0"} pt</strong>
          </div>
          <button
            type="button"
            class="primary-button"
            disabled={props.editingLocked}
            onClick={begin}
          >
            {storedProfile ? "Recalibrer ce Mac" : "Calibrer ce Mac"}
          </button>
        </div>
      ) : (
        <div class="calibration-controls">
          <div class="calibration-nudges" aria-label="Déplacement fin du centre">
            <button type="button" onClick={() => moveTo(centerOffset - 10, true)}>−10</button>
            <button type="button" onClick={() => moveTo(centerOffset - 1, true)}>−1</button>
            <label>
              <span>Décalage</span>
              <input
                type="number"
                min="-300"
                max="300"
                step="0.5"
                value={centerOffset}
                onInput={(event) => moveTo(Number(event.currentTarget.value))}
              />
              <small>pt</small>
            </label>
            <button type="button" onClick={() => moveTo(centerOffset + 1, true)}>+1</button>
            <button type="button" onClick={() => moveTo(centerOffset + 10, true)}>+10</button>
          </div>
          <input
            class="calibration-slider"
            aria-label="Décalage du centre physique"
            type="range"
            min="-180"
            max="180"
            step="0.5"
            value={centerOffset}
            onInput={(event) => moveTo(Number(event.currentTarget.value))}
          />
          <div class="calibration-scale">
            <span>Repère physique : 30 mm</span>
            <span>{guideWidthPoints.toFixed(1)} pt sur cette dalle</span>
          </div>
          <div class="calibration-actions">
            <button type="button" class="secondary-button" onClick={cancel}>Annuler</button>
            <button type="button" class="primary-button" onClick={save}>
              Enregistrer ce centre
            </button>
          </div>
        </div>
      )}
    </section>
  );
}
