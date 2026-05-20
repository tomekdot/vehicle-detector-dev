# 🤖 Vehicle Detector

Openplanet plugin for MP4 vehicle detection and training sample export.

This repository is prepared for public release on GitHub. The plugin code, the Python training script, and the TCP inference server are all covered by the same MIT license unless noted otherwise.

## ✨ Features

- Detects the active vehicle from `AsyncModelName`, Manialink labels, `RootMap.CollectionName`, and `ForceModelId`
- Tracks 0-100 km/h runs
- Captures telemetry-based training samples
- Supports continuous training segments with simple motion labels
- Exports JSONL samples for Python model training
- Stores a local dataset snapshot and manifest

## 📦 Release contents

- `Plugins/vehicle-detector` - Openplanet plugin source
- `Plugins/vehicle-detector/tools` - Python training and inference tools
- `PluginStorage/vehicle-detector/mp4-vehicle-detector-clean` - training data and generated artifacts

## 🧪 Training output

Samples are written with a stable schema:

- `schema_name`: `mp4_vehicle_detector_sample`
- `schema_version`: `1`
- `feature_columns`: see `dataset_manifest.json`

The local dataset is stored in the Openplanet storage folder under:

- `mp4-vehicle-detector`

## 🚀 Usage

1. Install Python dependencies from `Plugins/vehicle-detector/tools/requirements.txt`.
2. Run `train.py` to build `vehicle_detector_model.pkl` from the collected samples.
3. Run `server.py` to start the local inference server on `127.0.0.1:9000`.
4. Keep `Plugins/vehicle-detector` enabled in Openplanet so it can keep exporting telemetry.

## 🗂️ Project layout

- `Main.as` - plugin entry point
- `Settings.as` - settings and export constants
- `State.as` - runtime state
- `UI.as` - overlay and window rendering
- `Detection.as` - MP4 vehicle detection
- `Vehicles.as` - name normalization and textures
- `Telemetry.as` - acceleration timing and fallback logic
- `Training.as` - training capture and dataset export
- `Features.as` - feature extraction helpers
- `Utils.as` - small shared utilities

## ⚖️ License

- MIT - see `LICENSE`

## 👤 Contact

- Author: `tomekdot`
- Team: 'vitalism-creative'
- Discord: `@tomekdot'
