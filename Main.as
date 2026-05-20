// ============================================================================
// MP4 Vehicle Detector Clean
// ============================================================================
// Detects the current MP4 vehicle from multiple sources (AsyncModelName,
// Manialink labels, RootMap.CollectionName, ForceModelId) and provides
// 0-100 km/h acceleration timing with telemetry-based vehicle guessing.
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

