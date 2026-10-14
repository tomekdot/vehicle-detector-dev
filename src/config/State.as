// ============================================================================
// MP4 Vehicle Detector
// ============================================================================
// Split module for Plugins/vehicle-detector. Openplanet compiles all .as files
// in this plugin directory together.
// ============================================================================

// Section: Global State
// ============================================================================

// --- Current vehicle identity (updated every frame by SetCurrentVehicle) ---
string g_CurrentVehicle = "Unknown";       // Normalized key, e.g. "StadiumCar"
string g_CurrentDisplayName = "Unknown";   // Pretty name for UI, e.g. "Stadium Car"
string g_CurrentSource = "No data";        // Which detection source succeeded
string g_CurrentTrust = "";                // How far the current source can be trusted
string g_CurrentRawValue = "";             // Raw text before normalization

// --- Expected vehicle (map declares it) — compare against what is driven ---
string g_MapVehicle = "";                 // CGameCtnChallenge.VehicleName, "" when unassigned
string g_LastLoggedVehicle = "";           // Previous vehicle, used for change logging

// --- Live model-vs-reality scoring ---
// The game readout (ForceModelId / Pursuit label / title ident) is ground truth,
// so every fresh model prediction is scored against it while driving. This
// measures real accuracy instead of quoting a stale offline report.
int64 g_ModelCorrect = 0;                  // predictions matching the game readout
int64 g_ModelWrong = 0;
int64 g_ModelTotal = 0;
string g_ModelLastVerdict = "";            // human-readable last comparison
uint g_ModelLastScoredMs = 0;              // when the last prediction was scored
int64 g_ModelLastScoredStamp = -1;         // file timestamp already scored (dedupe key)
float g_ModelLastConfidence = 0.0f;
bool g_ModelAgreeing = false;              // last prediction matched the game
int g_ModelStreak = 0;                     // consecutive agreements (negative = wrong)

// --- Vehicle thumbnail cache ---
string g_LastTexturePath = "";
UI::Texture@ g_LastTexture = null;

// --- Telemetry ring-buffer (max 64 lines) ---
array<string> g_CurrentTelemetry;
uint g_LastTelemetryUpdate = 0;

// --- 0-100 km/h acceleration run state ---
bool g_RunActive = false;          // True while a timed run is in progress
bool g_RunCompleted = false;       // True after a run finishes (before next reset)
uint g_RunStartMs = 0;             // Timestamp when the run started
uint g_RunEndMs = 0;               // Timestamp when 100 km/h was reached
float g_BestZeroToHundredSec = -1.0f;   // Best (lowest) 0-100 time this session
float g_LastZeroToHundredSec = -1.0f;    // Most recent completed 0-100 time
string g_TelemetryGuessVehicle = "Unknown";
string g_TelemetryGuessReason = "";
uint g_TelemetryGuessUpdatedAtMs = 0;

// --- Training capture trigger state ---
bool g_TrainingCaptureActive = false;
bool g_TrainingCaptureArmed = false;
bool g_TrainingCapturePaused = false;
uint g_TrainingCaptureStartMs = 0;
uint g_TrainingCaptureEndMs = 0;
string g_TrainingMotionLabel = "Unknown";
string g_TrainingLockedVehicle = "";
string g_TrainingLockedSource = "";
float g_LastSpeedKmh = -1.0f;

// --- Manual training label selection ---
string g_SelectedTrainingVehicle = "";   // Empty means auto-detect is used
uint g_SelectedTrainingVehicleIndex = 0;

// --- Optional localhost stream for training samples ---
Net::Socket@ g_TrainingSocket = null;
uint g_LastTrainingConnectAttemptMs = 0;
uint g_LastTrainingSampleMs = 0;
uint g_TrainingRunId = 0;

// --- Local dataset export ---
dictionary@ g_DatasetSampleCounts = dictionary();
uint g_TotalDatasetSamples = 0;
uint g_TrainDatasetSamples = 0;
uint g_ValidationDatasetSamples = 0;
string g_LastDatasetWriteError = "";
