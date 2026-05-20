from __future__ import annotations

import json
import socket
from pathlib import Path

import joblib


HOST = "127.0.0.1"
PORT = 9000


def load_model(base_dir: Path):
    model_path = base_dir / "vehicle_detector_model.pkl"
    try:
        model_data = joblib.load(model_path)
    except FileNotFoundError:
        print("Error: vehicle_detector_model.pkl not found. Run train.py first.")
        raise SystemExit(1)

    return model_data["model"], model_data["classes"], model_data["features"]


def build_feature_vector(payload: dict, feature_names: list[str]) -> list[float]:
    feature_map = {
        "speed_kmh": float(payload.get("speed_kmh", 0.0)),
        "gear": int(payload.get("gear", 0)),
        "rpm": float(payload.get("rpm", 0.0)),
        "gas": float(payload.get("gas", 0.0)),
        "steer": float(payload.get("steer", 0.0)),
        "side_speed": float(payload.get("side_speed", 0.0)),
        "brake": 1.0 if payload.get("brake", False) else 0.0,
        "ground": 1.0 if payload.get("ground", False) else 0.0,
        "wheels_contact": float(payload.get("wheels_contact", 0)),
        "avg_slip": float(payload.get("avg_slip", 0.0)),
        "wet_wheels": float(payload.get("wet_wheels", 0)),
        "active_effects": float(payload.get("active_effects", 0)),
    }

    return [feature_map[name] for name in feature_names]


def main() -> int:
    base_dir = Path(__file__).resolve().parent
    model, classes, feature_names = load_model(base_dir)

    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind((HOST, PORT))
    server.listen(1)

    print(f"Model loaded. Listening on {HOST}:{PORT}...")

    conn, addr = server.accept()
    print(f"Connected: {addr}")

    buffer = ""
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
                    feature_vector = build_feature_vector(payload, feature_names)
                    prediction_idx = int(model.predict([feature_vector])[0])
                    probabilities = model.predict_proba([feature_vector])[0]
                    confidence = float(probabilities[prediction_idx]) * 100.0
                    predicted_vehicle = classes[prediction_idx]
                    speed_value = float(payload.get("speed_kmh", 0.0))
                    print(
                        f"Detected: {predicted_vehicle:<12} | Confidence: {confidence:5.1f}% | Speed: {speed_value:5.1f} km/h",
                        end="\r",
                    )
                except Exception:
                    continue
    finally:
        conn.close()
        server.close()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
