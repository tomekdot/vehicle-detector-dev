# 🚗 Vehicle Detector

Openplanet plugin for ManiaPlanet 4: identifies the vehicle you are **actually driving**, measures 0-100 km/h runs, and exports labelled telemetry samples for an offline classifier.

Requires the **VehicleState** plugin (declared in `info.toml`).

---

## ⚠️ Read this first: what the number in the window means

The plugin has **two independent systems**, and mixing them up is the single easiest way to be misled by it:

| | Vehicle readout | ML model |
|---|---|---|
| Source | the game itself | `tools/server.py` + `train.py` |
| Accuracy | authoritative | **currently poor** |
| Shown as | `Driven vehicle:` | `Model guess:` |

**The ML model is not trustworthy yet.** Its stored classification report scores macro-F1 = 0.23 across 9 classes, most of them 0.00. The game readout is the ground truth; the model is a research component.

If the two ever disagree, **the game readout is correct.**

---

## 🔍 Vehicle detection

Sources are tried strongest-evidence first. The first one that resolves wins:

1. **Pursuit Manialink label** — the server pushes the model name to the client UI
2. **`ForceModelId`** — per-player model forced by the server (`CTmRaceRulesPlayer`)
3. **`SettingsPlayerModelId`** — model forced through the script API
4. **Titlepack `VehicleIdentId`** — title-wide vehicle (CarSelector / VehicleUnlock)
5. **Map `VehicleName`** — what the map *expects*; shown as `guess - not forced`

Each result carries a **trust label** shown next to the source:

- `confirmed` — the game reports this model directly
- `title-wide` — from the titlepack
- `guess - not forced` — derived from the map declaration, nothing was forced
- `forced, not in registry` — a real forced id that is not a known vehicle (hex is shown)
- `measured 0-100` — inferred from an acceleration run

### The map name is NOT a detection source

Earlier versions resolved the car from `RootMap.CollectionName` — i.e. they guessed from the **map title**. A map called "...Lagoon..." reported LagoonCar regardless of what you drove. That produced confident wrong answers, and the source was removed. The map's `VehicleName` is now only an expectation, shown separately and never presented as a detection.

### Live model scoring

Because the game readout is ground truth, every fresh model prediction is compared against it while you drive (`src/detection/ModelScore.as`):

```
Model check: AGREES (streak 12)
Model health: unreliable (63%)
Model said Stadium Car, you drive Bay Car.
```

The tally resets when you switch cars — accuracy is per-vehicle, so mixing classes would produce a meaningless average. No verdict is issued below `Min Samples for Verdict` (default 25), because a handful of lucky frames is not evidence.

---

## 📊 0-100 km/h timing

A run starts from a standstill on full throttle with no brake, aborts on brake or airtime, and completes at 100 km/h. Best time of the session is kept.

---

## 🧪 Training data

Samples are JSONL with a stable schema:

- `schema_name`: `mp4_vehicle_detector_sample`
- `schema_version`: `1`
- `feature_columns`: see `dataset_manifest.json`

Each record carries `label`, `source` (which detection produced the label), and `motion`.

### Labels are automatic by default

With nothing selected in the dropdown, the label comes from the game readout — **drive around and samples are labelled without clicking anything**. A manual selection still overrides it, and the label is locked for the duration of a capture segment so a mid-run car swap cannot mislabel already-recorded samples.

### Current dataset state

| Label | Samples |
|---|---|
| TrafficCar | 2484 |
| BayCar | 1014 |
| StadiumCar | 616 |

**4114 samples total** (3308 train / 806 validation), and **all of them carry `source: "Manual selection"`** — they predate automatic labelling, so every one was picked by hand from the dropdown.

Two problems, both of which matter more than the raw count:

**`TrafficCar` is the largest class and it should not be.** It is an environment vehicle that does not appear in normal play, so it can only be collected in the editor. Its 2484 samples are the single biggest distortion in the dataset, and `train.py` weights them like any other class. It is still listed in `VEHICLE_CLASSES`, so it drags macro-F1 down at every training run.

**Eight classes have zero data:** CanyonCar, ValleyCar, LagoonCar, IslandCar, CoastCar, DesertCar, SnowCar, RallyCar. This is the actual bottleneck — the model cannot learn a class it has never seen.

Note that `TrafficCar` samples are collected in the editor, where no server forces a model, so their labels come from the weakest sources. See [Improving the model](#-improving-the-model) for why this needs addressing before retraining.

---

## 🚀 Usage

1. Install Python dependencies: `pip install -r tools/requirements.txt`
2. Train (optional, only needed if you want the ML guess): `python tools/train.py`
3. Start the inference server: `python tools/server.py` (listens on `127.0.0.1:9000`)
4. Enable the plugin in Openplanet

**The model server is optional.** Detection, 0-100 timing, and training capture all work without it. When it is stopped, the plugin shows `Model: not running` rather than displaying a stale result.

Stale results are never shown as the detected car: a result older than 10 seconds is ignored and reported as stale, because the file persists after the server stops.

---

## 🗂️ Project layout

```
src/
├── Main.as                    entry point
├── config/
│   ├── Settings.as            settings + export constants
│   └── State.as               shared runtime state
├── detection/
│   ├── Detection.as           source pipeline (trust order)
│   ├── Vehicles.as            name normalisation + thumbnails
│   ├── ModelScore.as          live model-vs-reality scoring
│   ├── Telemetry.as           acceleration timing + fallback
│   ├── Training.as            capture lifecycle + dataset export
│   └── Features.as            feature extraction helpers
├── ui/
│   └── UI.as                  menu, HUD, windows
└── utils/
    └── Utils.as               JSON + formatting helpers

tools/
├── train.py                   offline training
├── server.py                  TCP inference server
├── evaluate.py                offline evaluation
└── generate_training_gap_report.py
```

Data lands in `PluginStorage/vehicle-detector-dev/mp4-vehicle-detector/`.

> **Note:** `IO::FromStorageFolder()` resolves against the **running plugin's folder name**. The bundled tools therefore write to *both* `vehicle-detector-dev` and `vehicle-detector`, so the plugin finds the file whichever build you load.

---

## 🔧 Improving the model

The bottleneck is data coverage, and the current numbers show two separate problems.

**1. `TrafficCar` distorts every training run.** It is the largest class (2484) and cannot appear in normal play — it is an editor-only environment vehicle. It is still in `VEHICLE_CLASSES`, so the model is forced to predict a class it will never meet on a server. Remove it from the list in `tools/train.py` before retraining. This is a one-line change and it is the highest-value fix available.

**2. Eight classes have zero data:** CanyonCar, ValleyCar, LagoonCar, IslandCar, CoastCar, DesertCar, SnowCar, RallyCar. A classifier cannot learn a class it has never seen, so no amount of tuning helps until these are collected.

### Collecting the missing classes

Labels are automatic, so driving each car for a few minutes is enough — no dropdown clicking needed. `train.py` already applies `class_weight="balanced_subsample"` and `compute_sample_weight("balanced")`, so **you do not need equal counts per class**; a few hundred samples of a rare car carries the same weight as a thousand of a common one.

At `WINDOW_SIZE=20` and `STEP_SIZE=5`, a 30-second run yields roughly 80–100 windows. Fifteen minutes per car is comfortably sufficient.

### Where to collect

| Where | Label source | Quality |
|---|---|---|
| Pursuit / any server | `ForceModelId` | `confirmed` — best |
| Solo, editor, races | titlepack / map | `title-wide` / `Map expectation` — weaker |

Detection does **not** work in the main menu or ManiaSelect: there is no `playground` there, so no source resolves. Collect in-game.

### Then retrain and check the live verdict

Read the `Model health:` line in the HUD rather than trusting the offline report alone — it is measured against the car you are actually driving. Until it moves off `not enough data`, the number in the report is not evidence the model works.

---

## 🐛 Troubleshooting

| Symptom | Cause |
|---|---|
| Plugin does not load | `VehicleState` missing — it is a hard dependency |
| `Driven vehicle: Unknown` in-game | No source resolved; check `Openplanet.log` for `Pursuit label` / `ForceModelId` telemetry |
| `Model: not running` | `tools/server.py` is not running — this does not affect detection |
| `Model: stale (... old)` | Server stopped; its last result is being ignored on purpose |
| Reads a different car than you drive | A title-wide force is active; a title re-enter or map reload is needed to apply a change |

Enable **Debug → Log Detection Details** to dump the full source-by-source trace to `Openplanet.log`.

---

## ⚖️ License

MIT — see `LICENSE`.

## 👤 Contact

- Author: `tomekdot`
- Team: `vitalism-creative`
- Discord: `@tomekdot`
