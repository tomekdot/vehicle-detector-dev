import json
from pathlib import Path
from collections import Counter
import joblib
import numpy as np
from sklearn.metrics import classification_report, confusion_matrix
import matplotlib.pyplot as plt
import seaborn as sns

BASE_DIR = Path(__file__).resolve().parent
MODEL_PATH = BASE_DIR / "vehicle_detector_model.pkl"
DATA_DIR = BASE_DIR.parent.parent.parent / "PluginStorage" / "vehicle-detector" / "mp4-vehicle-detector"
VALIDATION_FILE = DATA_DIR / "samples_validation.jsonl"
RESULTS_DIR = BASE_DIR / "results"
RESULTS_DIR.mkdir(exist_ok=True)

STEP_SIZE = 5

# load artifact
artifact = joblib.load(MODEL_PATH)
model = artifact["model"]
le = artifact.get("label_encoder")
feature_names = artifact.get("feature_cols")
WINDOW_SIZE = artifact.get("window_size", 20)

print(f"Loaded model: {MODEL_PATH}\nwindow_size={WINDOW_SIZE} features={len(feature_names)}")

# import server helper for feature vector builder if available
try:
    import importlib.util
    spec = importlib.util.spec_from_file_location('vehicle_server', BASE_DIR / 'server.py')
    server = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(server)
    build_feature_vector = server.build_feature_vector
except Exception:
    # fallback: implement local builder (minimal, matches train.py's aggregations)
    def build_feature_vector(payloads, feature_names):
        # simple aggregates used during training: mean, max, std for numeric fields
        arr = []
        # numeric keys to aggregate (in feature_names order assume prefixes)
        # We'll compute a broad set: speed_mean, speed_max, speed_std, rpm_mean, rpm_max, rpm_std, gas_mean, gas_max, gas_std
        speeds = [p.get('speed', 0.0) for p in payloads]
        rpms = [p.get('rpm', 0.0) for p in payloads]
        gas = [p.get('gas', 0.0) for p in payloads]
        def stats(x):
            a = np.array(x, dtype=float)
            return a.mean(), a.max(), a.std()
        vec = []
        for group in (speeds, rpms, gas):
            m, M, s = stats(group)
            vec += [m, M, s]
        # pad/trim to feature length
        if len(vec) < len(feature_names):
            vec += [0.0] * (len(feature_names) - len(vec))
        return vec[:len(feature_names)]

# load validation samples (only Manual selection)
rows = []
with VALIDATION_FILE.open('r', encoding='utf-8') as f:
    for line in f:
        if not line.strip():
            continue
        obj = json.loads(line)
        if obj.get('source') != 'Manual selection':
            continue
        rows.append(obj)

print(f"Loaded {len(rows)} manual-selected validation frames from {VALIDATION_FILE}")

# group by run_id and build sliding windows
by_run = {}
for r in rows:
    run = r.get('run_id') or r.get('session') or 'unknown'
    by_run.setdefault(run, []).append(r)

X = []
y = []
for run, frames in by_run.items():
    for i in range(0, max(1, len(frames) - WINDOW_SIZE + 1), STEP_SIZE):
        window = frames[i:i+WINDOW_SIZE]
        if len(window) < WINDOW_SIZE:
            continue
        labels = [w.get('label') for w in window]
        if not labels:
            continue
        lbl = Counter(labels).most_common(1)[0][0]
        vec = build_feature_vector(window, feature_names)
        X.append(vec)
        y.append(lbl)

print(f"Built {len(X)} validation windows")

if not X:
    raise SystemExit('No validation windows built; check data and filters')

X = np.array(X)

# Encode labels
if le is not None:
    y_true = le.transform(y)
    classes = list(le.classes_)
else:
    # fit a local encoder
    unique = sorted(set(y))
    classes = unique
    mapping = {c:i for i,c in enumerate(unique)}
    y_true = np.array([mapping[c] for c in y])

# predict
y_pred = model.predict(X)
# if model predicts encoded labels, ensure comparison type
if hasattr(y_pred[0], 'dtype'):
    pass

# if y_pred are strings but y_true numeric, align
try:
    # try to decode if necessary
    if le is not None and y_pred.dtype.kind in 'iu':
        pass
except Exception:
    pass

report = classification_report(y_true, y_pred, target_names=classes, zero_division=0)
cm = confusion_matrix(y_true, y_pred)

# save text report
REPORT_TXT = RESULTS_DIR / 'classification_report.txt'
with REPORT_TXT.open('w', encoding='utf-8') as handle:
    handle.write(report)

# save confusion matrix plot
plt.figure(figsize=(10,8))
sns.heatmap(cm, annot=True, fmt='d', cmap='Blues', xticklabels=classes, yticklabels=classes)
plt.ylabel('True')
plt.xlabel('Predicted')
plt.title('Confusion Matrix')
plt.tight_layout()
plt.savefig(RESULTS_DIR / 'confusion_matrix.png')
plt.close()

# save per-window CSV
import csv
CSV_PATH = RESULTS_DIR / 'predictions.csv'
with CSV_PATH.open('w', newline='', encoding='utf-8') as csvf:
    writer = csv.writer(csvf)
    writer.writerow(['index','true_label','pred_label'])
    for i, (t,p) in enumerate(zip(y_true, y_pred)):
        writer.writerow([i, classes[int(t)], classes[int(p)]])

print('Saved report:', REPORT_TXT)
print('Saved confusion matrix:', RESULTS_DIR / 'confusion_matrix.png')
print('Saved predictions CSV:', CSV_PATH)
print('\nSummary:\n')
print(report)
