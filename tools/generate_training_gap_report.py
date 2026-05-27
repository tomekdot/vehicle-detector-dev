from __future__ import annotations

import json
from collections import Counter
from pathlib import Path


BASE_DIR = Path(__file__).resolve().parent
DATA_DIR = BASE_DIR.parent.parent.parent / "PluginStorage" / "vehicle-detector" / "mp4-vehicle-detector"
TRAIN_FILE = DATA_DIR / "samples_train.jsonl"
VALIDATION_FILE = DATA_DIR / "samples_validation.jsonl"
CLASSIFICATION_REPORT = BASE_DIR / "results" / "classification_report.txt"
OUTPUT_FILE = BASE_DIR / "results" / "training_gap_report.txt"

VEHICLE_CLASSES = [
    "BayCar",
    "LagoonCar",
    "IslandCar",
    "ValleyCar",
    "SnowCar",
    "RallyCar",
    "DesertCar",
    "CoastCar",
    "CanyonCar",
    "StadiumCar",
    "TrafficCar",
]

VALIDATION_TARGET = 300
TRAIN_TARGET = 1000


def load_label_counts(path: Path) -> Counter[str]:
    counts: Counter[str] = Counter()
    with path.open("r", encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            sample = json.loads(line)
            label = sample.get("label")
            if label:
                counts[str(label)] += 1
    return counts


def format_gap(count: int, target: int) -> str:
    return str(max(0, target - count))


def read_report_summary() -> list[str]:
    if not CLASSIFICATION_REPORT.exists():
        return ["Latest offline validation summary is unavailable."]

    lines = CLASSIFICATION_REPORT.read_text(encoding="utf-8").splitlines()
    summary: list[str] = []
    for line in lines:
        stripped = line.strip()
        if not stripped:
            continue
        if stripped.startswith(("BayCar", "CanyonCar", "CoastCar", "DesertCar", "IslandCar", "LagoonCar", "RallyCar", "SnowCar", "ValleyCar")):
            summary.append(stripped)
    return summary or ["Validation report exists, but no class rows were parsed."]


def build_report() -> str:
    train_counts = load_label_counts(TRAIN_FILE)
    validation_counts = load_label_counts(VALIDATION_FILE)
    validation_summary = read_report_summary()

    lines: list[str] = []
    lines.append("Vehicle Detector Training Gap Report")
    lines.append("")
    lines.append("Date: 2026-05-27")
    lines.append("")
    lines.append("Source")
    lines.append(
        "This report is generated automatically in Python from the current training "
        "and validation JSONL datasets, plus the latest offline validation report."
    )
    lines.append("")
    lines.append("Purpose")
    lines.append(
        "Identify which vehicle classes are under-trained, how much data is currently "
        "available, and how much more data is needed to make validation more reliable "
        "and reduce class confusion."
    )
    lines.append("")
    lines.append("Offline Validation Snapshot")
    for row in validation_summary:
        lines.append(f"- {row}")
    lines.append("")
    lines.append("Current Dataset Coverage")
    lines.append("Class        Train   Validation   Gap to 300 val   Gap to 1000 train")
    for vehicle in VEHICLE_CLASSES:
        train_count = train_counts.get(vehicle, 0)
        validation_count = validation_counts.get(vehicle, 0)
        val_gap = format_gap(validation_count, VALIDATION_TARGET)
        train_gap = format_gap(train_count, TRAIN_TARGET)
        lines.append(
            f"{vehicle:<12} {train_count:>6}   {validation_count:>10}   {val_gap:>14}   {train_gap:>16}"
        )

    lines.append("")
    lines.append("Most Important Gaps")
    ranked = sorted(
        VEHICLE_CLASSES,
        key=lambda vehicle: (
            -(max(0, VALIDATION_TARGET - validation_counts.get(vehicle, 0))),
            -(max(0, TRAIN_TARGET - train_counts.get(vehicle, 0))),
            vehicle,
        ),
    )
    for index, vehicle in enumerate(ranked[:6], start=1):
        train_count = train_counts.get(vehicle, 0)
        validation_count = validation_counts.get(vehicle, 0)
        lines.append(
            f"{index}. {vehicle} - train={train_count}, validation={validation_count}, "
            f"train gap={max(0, TRAIN_TARGET - train_count)}, validation gap={max(0, VALIDATION_TARGET - validation_count)}"
        )

    lines.append("")
    lines.append("Practical Conclusion")
    lines.append(
        "The first retraining priority should be the classes with the largest validation "
        "and training gaps. BayCar does not need priority collection because it already "
        "dominates the dataset."
    )
    lines.append("")
    lines.append("Collection Recommendations")
    lines.append("- Record samples in Manual selection mode.")
    lines.append("- Capture runs at different speeds, not only from standstill.")
    lines.append("- For each missing class, record several separate runs so different conditions are included in both training and validation.")
    lines.append("- Avoid letting BayCar dominate new samples.")

    return "\n".join(lines) + "\n"


def main() -> None:
    OUTPUT_FILE.write_text(build_report(), encoding="utf-8")
    print(f"Wrote {OUTPUT_FILE}")


if __name__ == "__main__":
    main()