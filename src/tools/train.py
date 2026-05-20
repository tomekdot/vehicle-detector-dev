from __future__ import annotations

import json
from pathlib import Path

import joblib
import pandas as pd
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import accuracy_score, classification_report


VEHICLE_CLASSES = [
    "StadiumCar",
    "CanyonCar",
    "ValleyCar",
    "LagoonCar",
    "IslandCar",
    "BayCar",
    "CoastCar",
    "DesertCar",
    "SnowCar",
    "RallyCar",
    "TrafficCar",
]
CLASS_TO_IDX = {name: idx for idx, name in enumerate(VEHICLE_CLASSES)}

FEATURES = [
    "speed_kmh",
    "gear",
    "rpm",
    "gas",
    "steer",
    "side_speed",
    "brake",
    "ground",
    "wheels_contact",
    "avg_slip",
    "wet_wheels",
    "active_effects",
]


def load_jsonl(path: Path) -> pd.DataFrame:
    records: list[dict] = []
    with path.open("r", encoding="utf-8") as handle:
        for line in handle:
            if line.strip():
                records.append(json.loads(line))

    frame = pd.DataFrame(records)
    if frame.empty:
        return frame

    frame["label_idx"] = frame["label"].map(CLASS_TO_IDX)
    frame = frame.dropna(subset=["label_idx"])
    frame["label_idx"] = frame["label_idx"].astype(int)

    missing_features = [column for column in FEATURES if column not in frame.columns]
    if missing_features:
        raise ValueError(f"Missing expected feature columns: {missing_features}")

    return frame


def main() -> int:
    base_dir = Path(__file__).resolve().parent
    data_dir = base_dir.parent.parent / "PluginStorage" / "vehicle-detector" / "mp4-vehicle-detector-clean"
    train_path = data_dir / "samples_train.jsonl"
    validation_path = data_dir / "samples_validation.jsonl"
    model_path = base_dir / "vehicle_detector_model.pkl"

    print("Loading data...")
    try:
        train_df = load_jsonl(train_path)
        validation_df = load_jsonl(validation_path)
    except FileNotFoundError as error:
        print(f"Error: missing JSONL file. Place samples in {data_dir}. {error}")
        return 1

    if train_df.empty:
        print(f"Error: no usable training rows found in {train_path.name}")
        return 1
    if validation_df.empty:
        print(f"Error: no usable validation rows found in {validation_path.name}")
        return 1

    x_train = train_df[FEATURES]
    y_train = train_df["label_idx"]
    x_validation = validation_df[FEATURES]
    y_validation = validation_df["label_idx"]

    print(f"Training rows: {len(x_train)} | Validation rows: {len(x_validation)}")

    model = RandomForestClassifier(
        n_estimators=100,
        max_depth=12,
        random_state=42,
        n_jobs=-1,
    )

    print("Training model...")
    model.fit(x_train, y_train)

    predictions = model.predict(x_validation)
    accuracy = accuracy_score(y_validation, predictions)

    print(f"Validation accuracy: {accuracy * 100:.2f}%")
    print("\nClassification report:")
    print(
        classification_report(
            y_validation,
            predictions,
            labels=list(range(len(VEHICLE_CLASSES))),
            target_names=VEHICLE_CLASSES,
            zero_division=0,
        )
    )

    joblib.dump(
        {
            "model": model,
            "classes": VEHICLE_CLASSES,
            "features": FEATURES,
        },
        model_path,
    )
    print(f"Saved model to {model_path.name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
