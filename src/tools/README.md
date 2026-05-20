# 🤖 Vehicle Detector Tools

Python training and inference utilities for the Openplanet vehicle detector plugin.

## ✨ Contents

- `train.py` - trains the RandomForest model from exported JSONL samples
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

3. Start the inference server.

   ```bash
   python server.py
   ```

## 🗂️ Data location

- Training and validation JSONL samples live in `PluginStorage/vehicle-detector/mp4-vehicle-detector-clean/`.
- The generated model file `vehicle_detector_model.pkl` is written next to `train.py` and `server.py`.

## 👤 Contact

- Author: `tomekdot`
- GitHub: `tomekdot`
- Issues and pull requests are welcome
