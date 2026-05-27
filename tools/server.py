from __future__ import annotations

import json
import socket
from collections import deque
from pathlib import Path
import time

import joblib
import numpy as np


HOST = "127.0.0.1"
PORT = 9000
WINDOW_STATES = [
    "Idle",
    "Accelerating",
    "Braking",
    "Cruising",
    "Straight",
    "Steer Left",
    "Steer Right",
]


def load_model(base_dir: Path):
    model_path = base_dir / "vehicle_detector_model.pkl"
    try:
        model_data = joblib.load(model_path)
    except FileNotFoundError:
        print("Error: vehicle_detector_model.pkl not found. Run train.py first.")
        raise SystemExit(1)

    model = model_data["model"]
    classes = model_data.get("classes")
    if classes is None:
        label_encoder = model_data.get("label_encoder")
        classes = list(label_encoder.classes_) if label_encoder is not None else []

    feature_names = model_data.get("feature_cols") or model_data.get("features")
    if feature_names is None:
        raise SystemExit("Error: model artifact is missing feature names.")

    window_size = int(model_data.get("window_size", 1))
    return model, classes, list(feature_names), window_size


def to_float(payload: dict, key: str, default: float = 0.0) -> float:
    try:
        return float(payload.get(key, default))
    except (TypeError, ValueError):
        return default


def to_int(payload: dict, key: str, default: int = 0) -> int:
    try:
        return int(float(payload.get(key, default)))
    except (TypeError, ValueError):
        return default


def window_feature_map(samples: list[dict]) -> dict[str, float]:
    speed = np.asarray([to_float(sample, "speed_kmh") for sample in samples], dtype=float)
    rpm = np.asarray([to_float(sample, "rpm") for sample in samples], dtype=float)
    gear = np.asarray([to_float(sample, "gear") for sample in samples], dtype=float)
    gas = np.asarray([to_float(sample, "gas") for sample in samples], dtype=float)
    steer = np.asarray([to_float(sample, "steer") for sample in samples], dtype=float)
    side_speed = np.asarray([to_float(sample, "side_speed") for sample in samples], dtype=float)
    slip = np.asarray([to_float(sample, "avg_slip") for sample in samples], dtype=float)
    brake = np.asarray([1.0 if sample.get("brake", False) else 0.0 for sample in samples], dtype=float)
    ground = np.asarray([1.0 if sample.get("ground", False) else 0.0 for sample in samples], dtype=float)
    wheels = np.asarray([to_float(sample, "wheels_contact") for sample in samples], dtype=float)
    wet_wheels = np.asarray([to_float(sample, "wet_wheels") for sample in samples], dtype=float)
    active_effects = np.asarray([to_float(sample, "active_effects") for sample in samples], dtype=float)
    motion = [str(sample.get("motion", "Unknown")) for sample in samples]

    feature_map = {
        "speed_mean": float(np.mean(speed)),
        "speed_max": float(np.max(speed)),
        "speed_std": float(np.std(speed)),
        "speed_range": float(np.max(speed) - np.min(speed)),
        "speed_start": float(speed[0]),
        "speed_end": float(speed[-1]),
    }

    dspeed = np.diff(speed)
    feature_map.update(
        {
            "accel_mean": float(np.mean(dspeed)) if len(dspeed) else 0.0,
            "accel_max": float(np.max(np.abs(dspeed))) if len(dspeed) else 0.0,
            "accel_std": float(np.std(dspeed)) if len(dspeed) else 0.0,
            "rpm_mean": float(np.mean(rpm)),
            "rpm_max": float(np.max(rpm)),
            "rpm_std": float(np.std(rpm)),
            "rpm_start": float(rpm[0]),
            "rpm_end": float(rpm[-1]),
        }
    )

    nonzero_speed = speed[speed > 1.0]
    nonzero_rpm = rpm[speed > 1.0]
    feature_map["rpm_per_speed"] = float(np.mean(nonzero_rpm / nonzero_speed)) if len(nonzero_speed) else 0.0

    feature_map.update(
        {
            "gear_mean": float(np.mean(gear)),
            "gear_max": float(np.max(gear)),
            "gas_mean": float(np.mean(gas)),
            "gas_std": float(np.std(gas)),
            "gas_max": float(np.max(gas)),
            "full_throttle_ratio": float(np.mean(gas > 0.95)),
            "slip_mean": float(np.mean(slip)),
            "slip_max": float(np.max(slip)),
            "slip_std": float(np.std(slip)),
            "side_mean": float(np.mean(np.abs(side_speed))),
            "side_max": float(np.max(np.abs(side_speed))),
            "steer_std": float(np.std(steer)),
            "steer_abs_mean": float(np.mean(np.abs(steer))),
            "brake_ratio": float(np.mean(brake)),
            "ground_ratio": float(np.mean(ground)),
            "wheels_mean": float(np.mean(wheels)),
            "wheels_min": float(np.min(wheels)),
            "wet_wheels_mean": float(np.mean(wet_wheels)),
            "active_effects_mean": float(np.mean(active_effects)),
        }
    )

    motion_counts = {state: 0.0 for state in WINDOW_STATES}
    for state in motion:
        if state in motion_counts:
            motion_counts[state] += 1.0
    for state in WINDOW_STATES:
        feature_map[f"motion_{state.lower().replace(' ', '_')}"] = motion_counts[state] / float(len(samples))

    return feature_map


def build_feature_vector(payloads: list[dict], feature_names: list[str]) -> list[float]:
    feature_map = window_feature_map(payloads)
    return [float(feature_map.get(name, 0.0)) for name in feature_names]


def build_single_frame_vector(payload: dict, feature_names: list[str]) -> list[float]:
    feature_map = {
        "speed_kmh": to_float(payload, "speed_kmh"),
        "gear": to_int(payload, "gear"),
        "rpm": to_float(payload, "rpm"),
        "gas": to_float(payload, "gas"),
        "steer": to_float(payload, "steer"),
        "side_speed": to_float(payload, "side_speed"),
        "brake": 1.0 if payload.get("brake", False) else 0.0,
        "ground": 1.0 if payload.get("ground", False) else 0.0,
        "wheels_contact": to_float(payload, "wheels_contact"),
        "avg_slip": to_float(payload, "avg_slip"),
        "wet_wheels": to_float(payload, "wet_wheels"),
        "active_effects": to_float(payload, "active_effects"),
    }

    return [float(feature_map.get(name, 0.0)) for name in feature_names]


def main() -> int:
    base_dir = Path(__file__).resolve().parent
    model, classes, feature_names, window_size = load_model(base_dir)
    # Warm-start: allow early predictions on a smaller initial window
    WARM_START = min(6, window_size) if window_size > 1 else 1
    # Confidence threshold (0..1) — below this treat as unknown for early predictions
    CONF_THRESHOLD = 0.60
    # Smoothing: require `SMOOTH_REQUIRED` repeated predictions within `SMOOTH_WINDOW`
    SMOOTH_WINDOW = 3
    SMOOTH_REQUIRED = 2

    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind((HOST, PORT))
    server.listen(1)

    print(f"Model loaded. Listening on {HOST}:{PORT}...")

    conn, addr = server.accept()
    print(f"Connected: {addr}")

    buffer = ""
    window_buffer: deque[dict] = deque(maxlen=window_size if window_size > 0 else 1)
    recent_preds: deque[str] = deque(maxlen=SMOOTH_WINDOW)
    current_run_id = None

    try:
        while True:
            data = conn.recv(4096)
            if not data:
                print("Connection closed.")
                break

            buffer += data.decode("utf-8", errors="replace")
            while "\n" in buffer:
                line, buffer = buffer.split("\n", 1)
                if not line.strip():
                    continue

                try:
                    payload = json.loads(line)
                except json.JSONDecodeError:
                    continue

                if payload.get("is_loading", False):
                    continue

                try:
                    run_id = payload.get("run_id")
                    if run_id != current_run_id:
                        current_run_id = run_id
                        window_buffer.clear()

                    speed_value = to_float(payload, "speed_kmh")

                    # Build a feature vector: if we have the full window, use it.
                    # Otherwise allow a warm-start prediction when we reached WARM_START frames.
                    if window_size <= 1:
                        feature_vector = build_single_frame_vector(payload, feature_names)
                        can_predict = True
                    else:
                        window_buffer.append(payload)
                        if len(window_buffer) >= window_size:
                            feature_vector = build_feature_vector(list(window_buffer), feature_names)
                            can_predict = True
                        elif len(window_buffer) >= WARM_START:
                            # warm-start: aggregate the smaller buffer and attempt a provisional prediction
                            feature_vector = build_feature_vector(list(window_buffer), feature_names)
                            can_predict = True
                        else:
                            can_predict = False

                    if not can_predict:
                        continue

                    prediction_idx = int(model.predict([feature_vector])[0])
                    probabilities = model.predict_proba([feature_vector])[0]
                    confidence = float(probabilities[prediction_idx])
                    predicted_vehicle = classes[prediction_idx]

                    # Early prediction gating: if using warm-start (buffer shorter than full), require confidence threshold
                    using_warm = len(window_buffer) < window_size
                    display_label = predicted_vehicle
                    if using_warm and confidence < CONF_THRESHOLD:
                        display_label = "unknown"

                    # Smoothing: accumulate recent non-unknown predictions and require agreement
                    recent_preds.append(display_label)
                    stable_label = display_label
                    # Check if the last SMOOTH_REQUIRED entries are equal and not 'unknown'
                    if len(recent_preds) >= SMOOTH_REQUIRED:
                        tail = list(recent_preds)[-SMOOTH_REQUIRED:]
                        if all(x == tail[0] and x != "unknown" for x in tail):
                            stable_label = tail[0]
                        else:
                            stable_label = "..."

                    out_msg = f"Detected: {stable_label:<12} | Confidence: {confidence*100:5.1f}% | Speed: {speed_value:5.1f} km/h"
                    print(out_msg, end="\r")

                    # Persist latest detection for UI/plugins to consume if desired
                    try:
                        results_dir = base_dir / "results"
                        results_dir.mkdir(exist_ok=True)
                        latest = {
                            "timestamp": int(time.time()),
                            "label": stable_label,
                            "confidence": float(confidence),
                            "using_warm": bool(using_warm),
                            "speed_kmh": float(speed_value),
                            "run_id": current_run_id,
                        }
                        (results_dir / "latest_detection.json").write_text(json.dumps(latest), encoding="utf-8")
                        # Also write to shared PluginStorage so the in-game plugin can read it
                        try:
                            storage_path = base_dir.parent.parent.parent / "PluginStorage" / "vehicle-detector" / "mp4-vehicle-detector"
                            storage_path.mkdir(parents=True, exist_ok=True)
                            (storage_path / "latest_detection.json").write_text(json.dumps(latest), encoding="utf-8")
                        except Exception:
                            pass
                    except Exception:
                        # non-fatal
                        pass
                except Exception:
                    continue
    finally:
        conn.close()
        server.close()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
