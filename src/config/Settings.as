// ============================================================================
// MP4 Vehicle Detector
// ============================================================================
// Split module for Plugins/vehicle-detector. Openplanet compiles all .as files
// in this plugin directory together.
// ============================================================================

// Section: Settings
// ============================================================================

[Setting category="General" name="Show Window"]
bool S_ShowWindow = true;

[Setting category="General" name="Show HUD Overlay"]
bool S_ShowHudOverlay = true;

[Setting category="HUD" name="Show Detection Window"]
bool S_ShowDetectionWindow = true;

[Setting category="Telemetry" name="Continuous Training Capture"]
bool S_ContinuousTrainingCapture = true;

[Setting category="General" name="Log Vehicle Changes"]
bool S_LogVehicleChanges = true;

[Setting category="General" name="Scan Manialink Labels"]
bool S_ScanManialinkLabels = true;

[Setting category="Debug" name="Show Telemetry Panel"]
bool S_ShowTelemetryPanel = true;

[Setting category="Debug" name="Log Detection Details"]
bool S_LogDetectionDetails = false;

[Setting category="Telemetry" name="Enable 0-100 Timing"]
bool S_EnableZeroToHundredTiming = true;

[Setting category="Telemetry" name="Export Training Samples"]
bool S_EnableTrainingExport = true;

[Setting category="Telemetry" name="Save Training Samples to Disk"]
bool S_SaveTrainingSamplesToDisk = true;

[Setting category="Telemetry" name="Validation Every N Runs" min=2 max=20]
uint S_ValidationEveryNRuns = 5;

[Setting category="Telemetry" name="Training Export Port"]
uint S_TrainingExportPort = 9000;

// ---------------------------------------------------------------------------
// Surface overlay — per-wheel ground contact material display
// ---------------------------------------------------------------------------

[Setting category="Surfaces" name="Show Surface Overlay"]
bool S_ShowSurfaces = true;

[Setting category="Surfaces" name="Overlay X (0-1)" min=0 max=1]
float S_SurfaceX = 0.82;

[Setting category="Surfaces" name="Overlay Y (0-1)" min=0 max=1]
float S_SurfaceY = 0.70;

[Setting category="Surfaces" name="Overlay Width" min=100 max=500]
int S_SurfaceWidth = 200;

[Setting category="Surfaces" name="Overlay Height" min=60 max=400]
int S_SurfaceHeight = 130;

[Setting category="Surfaces" name="Font Size" min=8 max=32]
float S_SurfaceFontSize = 11.0f;

[Setting category="Surfaces" name="Show Raw Material IDs"]
bool S_SurfaceRaw = false;


// ============================================================================
// Section: Training Export Constants
// ============================================================================

const string TRAINING_SCHEMA_NAME = "mp4_vehicle_detector_sample";
const string TRAINING_FEATURE_COLUMNS = "speed_kmh,gear,rpm,gas,steer,side_speed,brake,ground,wheels_contact,avg_slip,wet_wheels,active_effects,is_loading";
const uint TRAINING_SCHEMA_VERSION = 1;
const uint TRAINING_SUPPORTED_VEHICLE_COUNT = 11;
const uint TRAINING_SAMPLE_INTERVAL_MS = 100;
const uint TRAINING_SOCKET_RETRY_MS = 2000;
const uint TRAINING_CONTINUOUS_SEGMENT_MS = 8000;
const uint TRAINING_CONTINUOUS_MIN_SEGMENT_MS = 1500;
const float TRAINING_CAPTURE_WINDOW_SEC = 5.0f;
const float TRAINING_CAPTURE_TIMEOUT_SEC = 15.0f;
const float TRAINING_IMPACT_SPEED_DROP_KMH = 18.0f;
const float TRAINING_RESUME_MIN_ELAPSED_SEC = 0.5f;
const float TRAINING_RESUME_SPEED_KMH = 6.0f;
const float TRAINING_RESUME_GAS = 0.35f;
const float TRAINING_STEER_THRESHOLD = 0.35f;
const float TRAINING_GAS_THRESHOLD = 0.35f;
const string DATASET_STORAGE_FOLDER = "mp4-vehicle-detector";
