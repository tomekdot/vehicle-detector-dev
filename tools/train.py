from __future__ import annotations

import json
from pathlib import Path

import joblib
import numpy as np
import pandas as pd
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import accuracy_score, classification_report
from sklearn.model_selection import StratifiedKFold, cross_val_score
from sklearn.preprocessing import LabelEncoder
from sklearn.utils.class_weight import compute_sample_weight

try:
    from xgboost import XGBClassifier

    HAS_XGB = True
except ImportError:
    HAS_XGB = False
    print("[warn] xgboost not installed, falling back to RandomForest")


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

WINDOW_SIZE = 20
STEP_SIZE = 5
MIN_SPEED = 2.0
ONLY_MANUAL = True

NUMERIC_COLUMNS = [
    "speed_kmh",
    "gear",
    "rpm",
    "gas",
    "steer",
    "side_speed",
    "wheels_contact",
    "avg_slip",
    "wet_wheels",
    "active_effects",
]
BOOLEAN_COLUMNS = ["brake", "ground", "is_loading"]
MOTION_STATES = [
    "Idle",
    "Accelerating",
    "Braking",
    "Cruising",
    "Straight",
    "Steer Left",
    "Steer Right",
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

    missing_columns = [column for column in ["run_id", "elapsed_sec", "label", "source"] if column not in frame.columns]
    if missing_columns:
        raise ValueError(f"Missing expected columns: {missing_columns}")

    return frame


def preprocess(frame: pd.DataFrame) -> pd.DataFrame:
    if frame.empty:
        return frame

    frame = frame.copy()
    original_count = len(frame)

    if ONLY_MANUAL:
        frame = frame[frame["source"] == "Manual selection"].copy()
        print(f"[filter] Manual selection: {len(frame)}/{original_count} rows")

    frame = frame[frame["label"].notna() & (frame["label"] != "")].copy()
    frame = frame.sort_values(["run_id", "elapsed_sec"]).reset_index(drop=True)

    for column in NUMERIC_COLUMNS:
        if column in frame.columns:
            frame[column] = pd.to_numeric(frame[column], errors="coerce").fillna(0.0)

    for column in BOOLEAN_COLUMNS:
        if column in frame.columns:
            frame[column] = frame[column].fillna(False).astype(bool).astype(int)

    if "motion" in frame.columns:
        frame["motion"] = frame["motion"].fillna("Unknown").astype(str)
    else:
        frame["motion"] = "Unknown"

    return frame


def window_features(chunk: pd.DataFrame) -> dict[str, float]:
    features: dict[str, float] = {}

    speed = chunk["speed_kmh"].to_numpy(dtype=float)
    rpm = chunk["rpm"].to_numpy(dtype=float)
    gear = chunk["gear"].to_numpy(dtype=float)
    gas = chunk["gas"].to_numpy(dtype=float)
    steer = chunk["steer"].to_numpy(dtype=float)
    side_speed = chunk["side_speed"].to_numpy(dtype=float)
    slip = chunk["avg_slip"].to_numpy(dtype=float)
    brake = chunk["brake"].to_numpy(dtype=float)
    ground = chunk["ground"].to_numpy(dtype=float)
    wheels = chunk["wheels_contact"].to_numpy(dtype=float)
    wet_wheels = chunk["wet_wheels"].to_numpy(dtype=float)
    active_effects = chunk["active_effects"].to_numpy(dtype=float)
    motion = chunk["motion"].astype(str)

    features["speed_mean"] = float(np.mean(speed))
    features["speed_max"] = float(np.max(speed))
    features["speed_std"] = float(np.std(speed))
    features["speed_range"] = float(np.max(speed) - np.min(speed))
    features["speed_start"] = float(speed[0])
    features["speed_end"] = float(speed[-1])

    dspeed = np.diff(speed)
    features["accel_mean"] = float(np.mean(dspeed)) if len(dspeed) else 0.0
    features["accel_max"] = float(np.max(np.abs(dspeed))) if len(dspeed) else 0.0
    features["accel_std"] = float(np.std(dspeed)) if len(dspeed) else 0.0

    features["rpm_mean"] = float(np.mean(rpm))
    features["rpm_max"] = float(np.max(rpm))
    features["rpm_std"] = float(np.std(rpm))
    features["rpm_start"] = float(rpm[0])
    features["rpm_end"] = float(rpm[-1])

    nonzero_speed = speed[speed > 1.0]
    nonzero_rpm = rpm[speed > 1.0]
    features["rpm_per_speed"] = float(np.mean(nonzero_rpm / nonzero_speed)) if len(nonzero_speed) else 0.0

    features["gear_mean"] = float(np.mean(gear))
    features["gear_max"] = float(np.max(gear))
    features["gas_mean"] = float(np.mean(gas))
    features["gas_std"] = float(np.std(gas))
    features["gas_max"] = float(np.max(gas))
    features["full_throttle_ratio"] = float(np.mean(gas > 0.95))

    features["slip_mean"] = float(np.mean(slip))
    features["slip_max"] = float(np.max(slip))
    features["slip_std"] = float(np.std(slip))
    features["side_mean"] = float(np.mean(np.abs(side_speed)))
    features["side_max"] = float(np.max(np.abs(side_speed)))
    features["steer_std"] = float(np.std(steer))
    features["steer_abs_mean"] = float(np.mean(np.abs(steer)))

    features["brake_ratio"] = float(np.mean(brake))
    features["ground_ratio"] = float(np.mean(ground))
    features["wheels_mean"] = float(np.mean(wheels))
    features["wheels_min"] = float(np.min(wheels))
    features["wet_wheels_mean"] = float(np.mean(wet_wheels))
    features["active_effects_mean"] = float(np.mean(active_effects))

    motion_counts = motion.value_counts(normalize=True)
    for state in MOTION_STATES:
        key = f"motion_{state.lower().replace(' ', '_')}"
        features[key] = float(motion_counts.get(state, 0.0))

    return features


def build_dataset(frame: pd.DataFrame):
    x_rows: list[dict[str, float]] = []
    y_rows: list[str] = []

    for _, run_frame in frame.groupby("run_id", sort=True):
        run_frame = run_frame.sort_values("elapsed_sec").reset_index(drop=True)
        if len(run_frame) < WINDOW_SIZE:
            continue

        for start in range(0, len(run_frame) - WINDOW_SIZE + 1, STEP_SIZE):
            chunk = run_frame.iloc[start : start + WINDOW_SIZE]

            avg_abs_speed = float(np.mean(np.abs(chunk["speed_kmh"].to_numpy(dtype=float))))
            idle_ratio = float((chunk["motion"] == "Idle").mean()) if "motion" in chunk.columns else 0.0
            if avg_abs_speed < MIN_SPEED and idle_ratio >= 0.8:
                continue

            label_counts = chunk["label"].value_counts()
            if label_counts.empty:
                continue

            label = str(label_counts.idxmax())
            label_share = float(label_counts.iloc[0]) / float(len(chunk))
            if label_share < 0.8:
                continue

            x_rows.append(window_features(chunk))
            y_rows.append(label)

    x_frame = pd.DataFrame(x_rows).fillna(0.0)
    y_series = pd.Series(y_rows, name="label")
    print(f"[dataset] {len(x_frame)} windows, {y_series.nunique()} classes: {sorted(y_series.unique())}")
    return x_frame, y_series


def train_model(x_frame: pd.DataFrame, y_series: pd.Series):
    label_encoder = LabelEncoder()
    y_encoded = label_encoder.fit_transform(y_series)
    sample_weights = compute_sample_weight(class_weight="balanced", y=y_encoded)

    if HAS_XGB:
        model = XGBClassifier(
            n_estimators=300,
            max_depth=6,
            learning_rate=0.05,
            subsample=0.8,
            colsample_bytree=0.8,
            objective="multi:softprob",
            eval_metric="mlogloss",
            tree_method="hist",
            random_state=42,
            n_jobs=-1,
        )
    else:
        model = RandomForestClassifier(
            n_estimators=400,
            max_depth=None,
            min_samples_leaf=2,
            class_weight="balanced_subsample",
            random_state=42,
            n_jobs=-1,
        )

    min_class_count = int(pd.Series(y_encoded).value_counts().min())
    if min_class_count >= 2:
        n_splits = min(5, min_class_count)
        if n_splits >= 2:
            cv = StratifiedKFold(n_splits=n_splits, shuffle=True, random_state=42)
            scores = cross_val_score(model, x_frame, y_encoded, cv=cv, scoring="accuracy")
            print(f"[cv] accuracy: {scores.mean():.3f} ± {scores.std():.3f}")

    model.fit(x_frame, y_encoded, sample_weight=sample_weights)

    predictions = model.predict(x_frame)
    print("\n[train set report]")
    print(
        classification_report(
            y_encoded,
            predictions,
            labels=list(range(len(label_encoder.classes_))),
            target_names=list(label_encoder.classes_),
            zero_division=0,
        )
    )

    if hasattr(model, "feature_importances_"):
        importance = pd.Series(model.feature_importances_, index=x_frame.columns)
        print("\n[top 15 features]")
        print(importance.sort_values(ascending=False).head(15).to_string())

    return model, label_encoder


def save_model(model, label_encoder, feature_cols: list[str], model_path: Path) -> None:
    model_path.parent.mkdir(parents=True, exist_ok=True)
    artifact = {
        "model": model,
        "label_encoder": label_encoder,
        "classes": list(label_encoder.classes_),
        "feature_cols": feature_cols,
        "features": feature_cols,
        "window_size": WINDOW_SIZE,
        "step_size": STEP_SIZE,
        "schema_version": 1,
        "training_mode": "windowed",
        "manual_only": ONLY_MANUAL,
    }
    joblib.dump(artifact, model_path)
    print(f"\n[saved] {model_path}")


def main() -> int:
    base_dir = Path(__file__).resolve().parent
    data_dir = base_dir.parent.parent.parent / "PluginStorage" / "vehicle-detector" / "mp4-vehicle-detector"
    train_path = data_dir / "samples_train.jsonl"
    validation_path = data_dir / "samples_validation.jsonl"
    model_path = base_dir / "vehicle_detector_model.pkl"

    print("Loading data...")
    try:
        train_frame = preprocess(load_jsonl(train_path))
        validation_frame = preprocess(load_jsonl(validation_path))
    except FileNotFoundError as error:
        print(f"Error: missing JSONL file. Place samples in {data_dir}. {error}")
        return 1

    if train_frame.empty:
        print(f"Error: no usable training rows found in {train_path.name}")
        return 1
    if validation_frame.empty:
        print(f"Error: no usable validation rows found in {validation_path.name}")
        return 1

    x_train, y_train = build_dataset(train_frame)
    x_validation, y_validation = build_dataset(validation_frame)

    if x_train.empty:
        print(f"Error: no usable training windows found in {train_path.name}")
        return 1
    if x_validation.empty:
        print(f"Error: no usable validation windows found in {validation_path.name}")
        return 1

    print(f"Training windows: {len(x_train)} | Validation windows: {len(x_validation)}")

    model, label_encoder = train_model(x_train, y_train)

    validation_encoded = label_encoder.transform(y_validation)
    validation_predictions = model.predict(x_validation)
    accuracy = accuracy_score(validation_encoded, validation_predictions)

    print(f"Validation accuracy: {accuracy * 100:.2f}%")
    print("\nValidation report:")
    print(
        classification_report(
            validation_encoded,
            validation_predictions,
            labels=list(range(len(label_encoder.classes_))),
            target_names=list(label_encoder.classes_),
            zero_division=0,
        )
    )

    save_model(model, label_encoder, list(x_train.columns), model_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
