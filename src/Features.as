// ============================================================================
// MP4 Vehicle Detector Clean
// ============================================================================
// Split module for Plugins/vehicle-detector. Openplanet compiles all .as files
// in this plugin directory together.
// ============================================================================

// Section: VehicleState Feature Extraction
// ============================================================================

/** Counts how many wheels are on the ground. */
uint GetWheelContactCount(CSceneVehicleVisState@ state) {
    if (state is null) return 0;
    uint count = 0;
    if (state.FLGroundContact) count++;
    if (state.FRGroundContact) count++;
    if (state.RLGroundContact) count++;
    if (state.RRGroundContact) count++;
    return count;
}

/** Returns the average slip coefficient across all wheels. */
float GetAverageWheelSlip(CSceneVehicleVisState@ state) {
    if (state is null) return 0.0f;
    return (state.FLSlipCoef + state.FRSlipCoef + state.RLSlipCoef + state.RRSlipCoef) / 4.0f;
}

/** Counts how many wheels are marked wet. */
uint GetWetWheelCount(CSceneVehicleVisState@ state) {
    if (state is null) return 0;
    uint count = 0;
    if (state.FLIsWet) count++;
    if (state.FRIsWet) count++;
    if (state.RLIsWet) count++;
    if (state.RRIsWet) count++;
    return count;
}
