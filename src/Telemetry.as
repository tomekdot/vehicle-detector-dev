// ============================================================================
// MP4 Vehicle Detector
// ============================================================================
// Split module for Plugins/vehicle-detector. Openplanet compiles all .as files
// in this plugin directory together.
// ============================================================================

// Section: Telemetry / Acceleration Timing
// ============================================================================

/**
 * Runs every frame when 0-100 timing is enabled. Manages the acceleration
 * run lifecycle:
 *   - Starts when: standing still, on ground, full throttle, no brake
 *   - Resets on: brake, airtime, or 15 s timeout
 *   - Completes when: speed reaches 100 km/h
 * On completion, updates best/last times and triggers a vehicle guess.
 */
void UpdateAccelerationTelemetry() {
#if !MP4
    return;
#else
    auto state = VehicleState::ViewingPlayerState();
    if (state is null) {
        ResetTrainingCapture();
        ResetAccelerationRun();
        g_LastSpeedKmh = -1.0f;
        return;
    }

    float speedKmh = state.FrontSpeed * 3.6f;
    float previousSpeedKmh = g_LastSpeedKmh;
    g_LastSpeedKmh = speedKmh;

    if (S_EnableTrainingExport) {
        bool useContinuousTraining = g_TrainingCaptureArmed && !g_TrainingCapturePaused;
        if (useContinuousTraining || S_ContinuousTrainingCapture) {
            EnsureContinuousTrainingCapture(state, speedKmh);
            if (g_TrainingCaptureActive) {
                ExportTrainingSample(state, speedKmh, g_TrainingCaptureStartMs);
            }
        } else {
            bool impactDetected = false;
            if (previousSpeedKmh >= 0.0f) {
                float speedDropKmh = previousSpeedKmh - speedKmh;
                if (speedDropKmh >= TRAINING_IMPACT_SPEED_DROP_KMH && state.IsGroundContact) {
                    impactDetected = true;
                }
            }

            if (!g_TrainingCaptureActive && impactDetected) {
                StartTrainingCapture("Sudden speed drop detected");
                LockTrainingVehicleForCurrentRun();
            }

            if (g_TrainingCaptureActive) {
                float elapsedCaptureSec = float(Time::Now - g_TrainingCaptureStartMs) / 1000.0f;
                bool drivingResumed = elapsedCaptureSec > TRAINING_RESUME_MIN_ELAPSED_SEC
                    && speedKmh > TRAINING_RESUME_SPEED_KMH
                    && state.InputGasPedal > TRAINING_RESUME_GAS;
                if (drivingResumed) {
                    ResetTrainingCapture();
                    AddTelemetryLine("Training capture stopped: driving resumed");
                } else {
                    if (elapsedCaptureSec <= TRAINING_CAPTURE_WINDOW_SEC) {
                        ExportTrainingSample(state, speedKmh, g_TrainingCaptureStartMs);
                    }

                    if (elapsedCaptureSec > TRAINING_CAPTURE_TIMEOUT_SEC) {
                        ResetTrainingCapture();
                        AddTelemetryLine("Training capture timeout");
                    }
                }
            }
        }
    }

    if (!S_EnableZeroToHundredTiming) return;

    bool canStart = state.IsGroundContact && !state.InputIsBraking && state.InputGasPedal > 0.85f;

    // --- Not running: check if we can start ---
    if (!g_RunActive) {
        bool nearStandstill = speedKmh <= 1.5f;
        if (nearStandstill && canStart) {
            g_RunActive = true;
            g_RunCompleted = false;
            g_RunStartMs = Time::Now;
            g_RunEndMs = 0;
            g_TrainingRunId += 1;
            g_LastTrainingSampleMs = 0;
            g_TelemetryGuessVehicle = "Unknown";
            g_TelemetryGuessReason = "Warmup: waiting 5 s";
            g_TelemetryGuessUpdatedAtMs = Time::Now;
            AddTelemetryLine("0-100 run started");
        }
        return;
    }

    // --- Running: check abort conditions ---
    if (state.InputIsBraking || !state.IsGroundContact) {
        ResetAccelerationRun();
        AddTelemetryLine("0-100 run reset due to brake/air");
        return;
    }

    // --- Running: check completion (100 km/h reached) ---
    if (speedKmh >= 100.0f) {
        g_RunActive = false;
        g_RunCompleted = true;
        g_RunEndMs = Time::Now;
        g_LastZeroToHundredSec = float(g_RunEndMs - g_RunStartMs) / 1000.0f;
        if (g_BestZeroToHundredSec < 0.0f || g_LastZeroToHundredSec < g_BestZeroToHundredSec) {
            g_BestZeroToHundredSec = g_LastZeroToHundredSec;
        }
        AddTelemetryLine("0-100 run completed: " + Text::Format("%.2f s", g_LastZeroToHundredSec));
        return;
    }

    // --- Running: check timeout (15 s) ---
    if (Time::Now - g_RunStartMs > 15000) {
        ResetAccelerationRun();
        AddTelemetryLine("0-100 run timeout");
    }
#endif
}

/** Resets the acceleration run state to idle. */
void ResetAccelerationRun() {
    g_RunActive = false;
    g_RunCompleted = false;
    g_RunStartMs = 0;
    g_RunEndMs = 0;
    g_LastTrainingSampleMs = 0;
}



/**
 * If the primary detection failed or is unreliable (Unknown, raw-only,
 * or RootMap fallback), overwrites the result with the telemetry guess.
 * This gives a second chance to identify the vehicle from acceleration.
 */
void ApplyTelemetryFallback(const string &in vehicle, const string &in displayName, const string &in source, const string &in rawValue,
    string &out outVehicle, string &out outDisplayName, string &out outSource, string &out outRawValue, bool &out didOverride) {
    outVehicle = vehicle;
    outDisplayName = displayName;
    outSource = source;
    outRawValue = rawValue;
    didOverride = false;

    if (g_TelemetryGuessVehicle == "Unknown" || g_TelemetryGuessVehicle.Length == 0) return;

    // Only override when primary detection is weak
    bool shouldOverride = false;
    if (vehicle == "Unknown") {
        shouldOverride = true;
    } else if (source == "RootMap.CollectionName") {
        shouldOverride = true;
    } else if (source.EndsWith("(raw)")) {
        shouldOverride = true;
    }

    if (!shouldOverride) return;

    AddTelemetryLine("Telemetry fallback applied: " + g_TelemetryGuessVehicle);
    outVehicle = g_TelemetryGuessVehicle;
    outDisplayName = ToPrettyVehicleName(g_TelemetryGuessVehicle);
    outSource = "Telemetry 0-100";
    outRawValue = g_TelemetryGuessReason;
    didOverride = true;
}


