import importlib.util, json
from pathlib import Path
spec= importlib.util.spec_from_file_location('server', 'Plugins/vehicle-detector-dev/tools/server.py')
mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
base=Path('Plugins/vehicle-detector-dev/tools').resolve()
model, classes, feature_names, window_size = mod.load_model(base)
val = Path('PluginStorage/vehicle-detector/mp4-vehicle-detector/samples_validation.jsonl')
rows=[]
with val.open('r', encoding='utf-8') as f:
    for line in f:
        if not line.strip():
            continue
        obj = json.loads(line)
        if obj.get('source')!='Manual selection':
            continue
        rows.append(obj)
        if len(rows) >= (window_size if window_size>0 else 1):
            break
if not rows:
    print('no rows')
else:
    vec = mod.build_feature_vector(rows, feature_names)
    pred = int(model.predict([vec])[0])
    probs = model.predict_proba([vec])[0]
    conf = float(probs[pred])
    results_dir = base / 'results'
    results_dir.mkdir(exist_ok=True)
    latest = {
        'timestamp': int(__import__('time').time()),
        'label': classes[pred],
        'confidence': conf,
        'using_warm': len(rows) < window_size,
        'speed_kmh': float(rows[-1].get('speed_kmh',0.0)),
        'run_id': rows[-1].get('run_id')
    }
    (results_dir / 'latest_detection.json').write_text(json.dumps(latest), encoding='utf-8')
    print('wrote', results_dir / 'latest_detection.json')
