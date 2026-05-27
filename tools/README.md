# 🤖 Vehicle Detector Tools

Python training and inference utilities for the Openplanet vehicle detector plugin.

## ✨ Contents

- `train.py` - trains the windowed vehicle classifier from exported JSONL samples
- `server.py` - serves live TCP inference on `127.0.0.1:9000`
- `requirements.txt` - Python dependencies for training and serving
- `LICENSE` - MIT license for the tooling bundle

## 🚀 Quick start

1. Install dependencies.

   ```bash
   pip install -r requirements.txt
   ```

2. Train the model.

   ```bash
   python train.py
   ```

   The trainer builds sliding windows from `run_id` and `elapsed_sec`, filters to `Manual selection` sources, and falls back to RandomForest when `xgboost` is unavailable.

3. Start the inference server.

   ```bash
   python server.py
   ```

## 🗂️ Data location

- Training and validation JSONL samples live in `PluginStorage/vehicle-detector/mp4-vehicle-detector/`.
- The generated model file `vehicle_detector_model.pkl` is written next to `train.py` and `server.py`.

## 👤 Contact

- Author: `tomekdot`
- GitHub: `tomekdot`
- Issues and pull requests are welcome

## 📦 Packaging (optional)

You can create a single-file Windows executable using PyInstaller so users don't need Python installed.

1. Install PyInstaller:

```powershell
python -m pip install pyinstaller
```

2. From this folder (`Plugins/vehicle-detector-dev/tools`) run:

```powershell
.build_exe.bat
```

This will produce `dist/vehicle-detector-server.exe`.

Use `start_server.bat` to launch the server or run the exe directly.
