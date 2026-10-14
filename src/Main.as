// ============================================================================
// MP4 Vehicle Detector
// ============================================================================
// Detects which vehicle the player ACTUALLY drives on MP4, from the sources
// the game really exposes (Pursuit Manialink label, ForceModelId,
// SettingsPlayerModelId, titlepack VehicleIdentId), and provides 0-100 km/h
// acceleration timing with telemetry-based vehicle guessing.
//
// The map's own VehicleName is deliberately NOT used to identify the car —
// only as the weakest, explicitly-labelled expectation. Deriving the vehicle
// from the map/collection name produced confidently wrong answers.
// ============================================================================

// File map:
// - Settings.as: plugin settings and training export constants
// - State.as: shared runtime state
// - UI.as: menu and window rendering
// - Detection.as: MP4 vehicle detection pipeline
// - Vehicles.as: vehicle normalization and thumbnails
// - Telemetry.as: acceleration run logic and telemetry fallback
// - Training.as: capture, labels, JSONL export, dataset manifest, socket stream
// - Features.as: VehicleState feature extraction for model inputs
// - Utils.as: JSON, telemetry buffer, and small formatting helpers

// Section: Lifecycle
// ============================================================================

/** Main loop — runs every frame, delegates to UpdateDetector. */
void Main() {
    while (true) {
        HandleTrainingHotkeys();
        UpdateDetector();
        yield();
    }
}
