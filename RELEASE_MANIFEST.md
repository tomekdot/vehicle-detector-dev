# Vehicle Detector Release Manifest

This file lists the repository contents that should be published together for the public GitHub release.

## Plugin source

- `Plugins/vehicle-detector/info.toml`
- `Plugins/vehicle-detector/README.md`
- `Plugins/vehicle-detector/LICENSE`
- `Plugins/vehicle-detector/Main.as`
- `Plugins/vehicle-detector/Settings.as`
- `Plugins/vehicle-detector/State.as`
- `Plugins/vehicle-detector/UI.as`
- `Plugins/vehicle-detector/Detection.as`
- `Plugins/vehicle-detector/Vehicles.as`
- `Plugins/vehicle-detector/Telemetry.as`
- `Plugins/vehicle-detector/Training.as`
- `Plugins/vehicle-detector/Features.as`
- `Plugins/vehicle-detector/Utils.as`

## Training and inference bundle

- `Plugins/vehicle-detector/tools/README.md`
- `Plugins/vehicle-detector/tools/LICENSE`
- `Plugins/vehicle-detector/tools/train.py`
- `Plugins/vehicle-detector/tools/server.py`
- `Plugins/vehicle-detector/tools/requirements.txt`
- `Plugins/vehicle-detector/tools/.gitignore`
- `PluginStorage/vehicle-detector/mp4-vehicle-detector-clean/dataset_manifest.json`
- `PluginStorage/vehicle-detector/mp4-vehicle-detector-clean/samples_train.jsonl`
- `PluginStorage/vehicle-detector/mp4-vehicle-detector-clean/samples_validation.jsonl`

## Generated files that should stay untracked

- `PluginStorage/vehicle-detector/mp4-vehicle-detector-clean/__pycache__/`
- `PluginStorage/vehicle-detector/mp4-vehicle-detector-clean/vehicle_detector_model.pkl`
