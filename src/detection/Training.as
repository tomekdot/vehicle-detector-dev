// ============================================================================
// MP4 Vehicle Detector
// ============================================================================
// Split module for Plugins/vehicle-detector. Openplanet compiles all .as files
// in this plugin directory together.
// ============================================================================

// Section: Training Capture Lifecycle
// ============================================================================

/** Starts a training capture session. */
void StartTrainingCapture(const string &in reason) {
    g_TrainingCaptureActive = true;
    g_TrainingCaptureStartMs = Time::Now;
    g_TrainingCaptureEndMs = 0;
    g_TrainingRunId += 1;
    g_LastTrainingSampleMs = 0;
    g_TrainingMotionLabel = "Unknown";
    g_TelemetryGuessVehicle = "Unknown";
    g_TelemetryGuessReason = reason;
    g_TelemetryGuessUpdatedAtMs = Time::Now;
    AddTelemetryLine("Training capture started: " + reason);
}

/** Handles the training hotkeys. Win+M or Ctrl+M pauses/resumes; M stops. */
void HandleTrainingHotkeys() {
    bool haveCtrl = UI::IsKeyDown(UI::Key::LeftCtrl) || UI::IsKeyDown(UI::Key::RightCtrl);
    bool haveWin = UI::IsKeyDown(UI::Key::LeftSuper) || UI::IsKeyDown(UI::Key::RightSuper);
    bool haveMenuDown = UI::IsKeyDown(UI::Key::Menu);

    // Prevent accidental Windows key presses from triggering any other action
    if (!haveCtrl && !haveWin && !haveMenuDown) {
        if (UI::IsKeyPressed(UI::Key::LeftSuper) || UI::IsKeyPressed(UI::Key::RightSuper)) {
            return;
        }
    }

    // Combo: Win+M, Ctrl+M or Menu+M toggles pause/resume/start
    if ((haveCtrl || haveWin || haveMenuDown) && UI::IsKeyPressed(UI::Key::M)) {
        if (!g_TrainingCaptureArmed) {
            StartTrainingSession();
        } else if (g_TrainingCapturePaused) {
            ResumeTrainingSession();
        } else {
            PauseTrainingSession();
        }
        return;
    }

    // Single Menu key toggles pause/resume/start without any combination
    if (UI::IsKeyPressed(UI::Key::Menu)) {
        if (!g_TrainingCaptureArmed) {
            StartTrainingSession();
        } else if (g_TrainingCapturePaused) {
            ResumeTrainingSession();
        } else {
            PauseTrainingSession();
        }
        return;
    }

    // Standalone M key (no modifier) stops training
    if (UI::IsKeyPressed(UI::Key::M)) {
        StopTrainingSession();
        return;
    }

    // Standalone Super key press without any modifier — swallow it
    if (UI::IsKeyPressed(UI::Key::LeftSuper) || UI::IsKeyPressed(UI::Key::RightSuper)) {
        StopTrainingSession();
        return;
    }
}

/** Arms training so continuous capture can run until paused or stopped. */
void StartTrainingSession() {
    g_TrainingCaptureArmed = true;
    g_TrainingCapturePaused = false;
    if (!g_TrainingCaptureActive) {
        StartTrainingCapture("Manual start");
    }
    AddTelemetryLine("Training armed");
}

/** Pauses the current training session without clearing the selected vehicle. */
void PauseTrainingSession() {
    g_TrainingCapturePaused = true;
    ResetTrainingCapture();
    AddTelemetryLine("Training paused");
}

/** Resumes a paused training session. */
void ResumeTrainingSession() {
    g_TrainingCaptureArmed = true;
    g_TrainingCapturePaused = false;
    if (!g_TrainingCaptureActive) {
        StartTrainingCapture("Manual resume");
    }
    AddTelemetryLine("Training resumed");
}

/** Stops the current training session and clears any lock. */
void StopTrainingSession() {
    g_TrainingCaptureArmed = false;
    g_TrainingCapturePaused = false;
    ResetTrainingCapture();
    ClearTrainingVehicleLock();
    AddTelemetryLine("Training stopped");
}

/** Stops the current training capture session. */
void ResetTrainingCapture() {
    g_TrainingCaptureActive = false;
    g_TrainingCaptureEndMs = Time::Now;
    g_LastTrainingSampleMs = 0;
    g_TrainingMotionLabel = "Unknown";
}

/** Clears any locked training label so auto-detection can pick a new one. */
void ClearTrainingVehicleLock() {
    g_TrainingLockedVehicle = "";
    g_TrainingLockedSource = "";
}

/** Locks the current vehicle as the active training label until manually changed. */
void LockTrainingVehicleForCurrentRun() {
    if (g_SelectedTrainingVehicle.Length > 0) {
        ClearTrainingVehicleLock();
        return;
    }

    if (g_CurrentVehicle.Length == 0 || g_CurrentVehicle == "Unknown") return;
    if (g_TrainingLockedVehicle == g_CurrentVehicle) return;

    g_TrainingLockedVehicle = g_CurrentVehicle;
    g_TrainingLockedSource = g_CurrentSource;
    AddTelemetryLine("Training vehicle locked: " + ToPrettyVehicleName(g_TrainingLockedVehicle));
}

/** Returns a simple, human-readable motion label for the current driving state. */
string GetTrainingMotionLabel(CSceneVehicleVisState@ state, float speedKmh) {
    if (state is null) return "Unknown";
    if (speedKmh < 1.5f) return "Idle";
    if (state.InputIsBraking) return "Braking";
    if (state.InputSteer <= -TRAINING_STEER_THRESHOLD) return "Steer Left";
    if (state.InputSteer >= TRAINING_STEER_THRESHOLD) return "Steer Right";
    if (state.InputGasPedal >= TRAINING_GAS_THRESHOLD) return "Accelerating";
    if (Math::Abs(state.InputSteer) < 0.15f) return "Straight";
    return "Cruising";
}

/** Keeps a continuous training capture alive and rotates short motion segments. */
void EnsureContinuousTrainingCapture(CSceneVehicleVisState@ state, float speedKmh) {
    if (!S_EnableTrainingExport || state is null) return;
    if (!g_TrainingCaptureArmed || g_TrainingCapturePaused) return;

    LockTrainingVehicleForCurrentRun();

    string motionLabel = GetTrainingMotionLabel(state, speedKmh);
    bool segmentOldEnough = Time::Now - g_TrainingCaptureStartMs >= TRAINING_CONTINUOUS_MIN_SEGMENT_MS;
    bool needsNewSegment = !g_TrainingCaptureActive
        || (g_TrainingMotionLabel != motionLabel && segmentOldEnough)
        || Time::Now - g_TrainingCaptureStartMs >= TRAINING_CONTINUOUS_SEGMENT_MS;

    if (!needsNewSegment) return;

    g_TrainingCaptureActive = true;
    g_TrainingCaptureStartMs = Time::Now;
    g_TrainingCaptureEndMs = 0;
    g_TrainingRunId += 1;
    g_LastTrainingSampleMs = 0;
    g_TrainingMotionLabel = motionLabel;
    AddTelemetryLine("Training segment: " + motionLabel);
}


// ============================================================================
// Section: Training Sample Export
// ============================================================================

/**
 * Returns true when a label is trusted enough to be exported.
 * Trusted = non-empty, not Unknown, and created from Manual selection.
 */
bool IsTrustedTrainingLabel(const string &in labelVehicle, const string &in labelSource) {
    if (labelVehicle.Length == 0) return false;
    if (labelVehicle == "Unknown") return false;
    if (labelSource != "Manual selection") return false;
    return true;
}

/**
 * Ensures a connected localhost socket for training export. Reuses the
 * global `g_TrainingSocket` and throttles reconnect attempts.
 */
Net::Socket@ EnsureTrainingSocket() {
    if (!S_EnableTrainingExport) return null;

    // Reuse ready socket
    if (g_TrainingSocket !is null && g_TrainingSocket.IsReady()) return g_TrainingSocket;

    // Throttle reconnect attempts
    if (Time::Now - g_LastTrainingConnectAttemptMs < TRAINING_SOCKET_RETRY_MS) return g_TrainingSocket;
    g_LastTrainingConnectAttemptMs = Time::Now;

    try {
        @g_TrainingSocket = Net::Socket();
        g_TrainingSocket.Connect("127.0.0.1", int(S_TrainingExportPort));
    } catch {
        @g_TrainingSocket = null;
    }

    return g_TrainingSocket;
}

/**
 * Streams a single JSONL training sample to localhost. Only trusted
 * labels are exported so the dataset is not polluted by weak guesses.
 */
void ExportTrainingSample(CSceneVehicleVisState@ state, float speedKmh, uint captureStartMs) {
    if (state is null) return;
    if (Time::Now - g_LastTrainingSampleMs < TRAINING_SAMPLE_INTERVAL_MS) return;
    g_LastTrainingSampleMs = Time::Now;

    string labelVehicle = GetTrainingVehicleForRun();
    string labelSource = GetTrainingVehicleSourceForRun();
    if (!IsTrustedTrainingLabel(labelVehicle, labelSource)) return;

    string split = GetDatasetSplitForRun();
    string payload = BuildTrainingSampleJson(state, speedKmh, captureStartMs, split, labelVehicle, labelSource, g_TrainingMotionLabel);

    if (S_SaveTrainingSamplesToDisk) {
        AppendDatasetSample(split, payload, labelVehicle);
    }

    auto socket = EnsureTrainingSocket();
    if (socket is null || !socket.IsReady()) return;

    socket.WriteRaw(payload);
}


// ============================================================================
// Section: Training Labels
// ============================================================================

/** Returns the current split name for the active run. */
string GetDatasetSplitForRun() {
    if (S_ValidationEveryNRuns <= 1) return "train";
    return (g_TrainingRunId % S_ValidationEveryNRuns == 0) ? "validation" : "train";
}

/** Returns the vehicle used as the active training label for the current run. */
string GetTrainingVehicleForRun() {
    if (g_SelectedTrainingVehicle.Length > 0) {
        return g_SelectedTrainingVehicle;
    }

    if (g_TrainingLockedVehicle.Length > 0) {
        return g_TrainingLockedVehicle;
    }

    return g_CurrentVehicle;
}

/** Returns the source string associated with the active training label. */
string GetTrainingVehicleSourceForRun() {
    if (g_SelectedTrainingVehicle.Length > 0) {
        return "Manual selection";
    }

    if (g_TrainingLockedSource.Length > 0) {
        return g_TrainingLockedSource;
    }

    return g_CurrentSource;
}

/** Maps numbered shortcuts to the supported vehicle keys. */
string GetTrainingVehicleKeyByIndex(uint index) {
    switch (index) {
        case 1: return "StadiumCar";
        case 2: return "CanyonCar";
        case 3: return "ValleyCar";
        case 4: return "LagoonCar";
        case 5: return "IslandCar";
        case 6: return "BayCar";
        case 7: return "CoastCar";
        case 8: return "DesertCar";
        case 9: return "SnowCar";
        case 10: return "RallyCar";
        case 11: return "TrafficCar";
    }

    return "";
}

/** Applies the manual training selection from a numbered shortcut. */
void SelectTrainingVehicleByIndex(uint index) {
    if (index == g_SelectedTrainingVehicleIndex) {
        if (index == 0 || g_SelectedTrainingVehicle == GetTrainingVehicleKeyByIndex(index)) {
            return;
        }
    }

    if (index == 0) {
        if (g_SelectedTrainingVehicle.Length == 0 && g_SelectedTrainingVehicleIndex == 0) return;
        g_SelectedTrainingVehicle = "";
        g_SelectedTrainingVehicleIndex = 0;
        ClearTrainingVehicleLock();
        AddTelemetryLine("Training vehicle selection reset to auto");
        print("[Vehicle Detector] Training vehicle selection reset to auto");
        return;
    }

    string vehicle = GetTrainingVehicleKeyByIndex(index);
    if (vehicle.Length == 0) return;

    g_SelectedTrainingVehicle = vehicle;
    g_SelectedTrainingVehicleIndex = index;
    ClearTrainingVehicleLock();
    if (g_TrainingCaptureActive || g_TrainingCaptureArmed) {
        AddTelemetryLine("Training vehicle selection updated while armed");
    }
    AddTelemetryLine("Training vehicle selected: " + ToPrettyVehicleName(vehicle));
    print("[Vehicle Detector] Training vehicle selected: " + vehicle + " (#" + tostring(index) + ")");
}


// ============================================================================
// Section: Dataset Storage
// ============================================================================

/** Returns the absolute path to the local dataset root folder. */
string GetDatasetRootDir() {
    string dir = "";

    try {
        dir = IO::FromStorageFolder(DATASET_STORAGE_FOLDER);
    } catch {
        dir = "";
    }

    if (dir.Length == 0) return "";

    if (!IO::FolderExists(dir)) {
        try {
            IO::CreateFolder(dir, true);
        } catch {
        }
    }

    return dir;
}

/** Returns the local JSONL file path for the requested split. */
string GetDatasetSamplesPath(const string &in split) {
    string dir = GetDatasetRootDir();
    if (dir.Length == 0) return "";
    return dir + "/samples_" + split + ".jsonl";
}


// ============================================================================
// Section: Python Training Schema
// ============================================================================

/** Builds a single JSONL record for the current training sample. */
string BuildTrainingSampleJson(CSceneVehicleVisState@ state, float speedKmh, uint captureStartMs, const string &in split, const string &in labelVehicle, const string &in labelSource, const string &in motionLabel) {
    float elapsedSec = float(Time::Now - captureStartMs) / 1000.0f;
    string payload = "{";
    payload += "\"type\":\"sample\"";
    payload += ",\"schema_name\":\"" + JsonEscape(TRAINING_SCHEMA_NAME) + "\"";
    payload += ",\"schema_version\":" + tostring(TRAINING_SCHEMA_VERSION);
    payload += ",\"split\":\"" + JsonEscape(split) + "\"";
    payload += ",\"run_id\":" + g_TrainingRunId;
    payload += ",\"elapsed_sec\":" + Text::Format("%.3f", elapsedSec);
    payload += ",\"label\":\"" + JsonEscape(labelVehicle) + "\"";
    payload += ",\"display_name\":\"" + JsonEscape(ToPrettyVehicleName(labelVehicle)) + "\"";
    payload += ",\"source\":\"" + JsonEscape(labelSource) + "\"";
    payload += ",\"motion\":\"" + JsonEscape(motionLabel) + "\"";
    payload += ",\"raw_value\":\"" + JsonEscape(g_CurrentRawValue) + "\"";
    payload += ",\"texture_path\":\"" + JsonEscape(GetVehicleTexturePath(labelVehicle)) + "\"";
    payload += ",\"speed_kmh\":" + Text::Format("%.3f", speedKmh);
    payload += ",\"gear\":" + Text::Format("%d", state.CurGear);
    payload += ",\"rpm\":" + Text::Format("%.3f", state.RPM);
    payload += ",\"gas\":" + Text::Format("%.3f", state.InputGasPedal);
    payload += ",\"steer\":" + Text::Format("%.3f", state.InputSteer);
    payload += ",\"side_speed\":" + Text::Format("%.3f", state.SideSpeed);
    payload += ",\"brake\":" + string(state.InputIsBraking ? "true" : "false");
    payload += ",\"ground\":" + string(state.IsGroundContact ? "true" : "false");
    payload += ",\"wheels_contact\":" + Text::Format("%d", GetWheelContactCount(state));
    payload += ",\"avg_slip\":" + Text::Format("%.3f", GetAverageWheelSlip(state));
    payload += ",\"wet_wheels\":" + Text::Format("%d", GetWetWheelCount(state));
    payload += ",\"active_effects\":" + Text::Format("%d", state.ActiveEffects);
    payload += ",\"is_loading\":false";
    payload += "}\n";
    return payload;
}


// ============================================================================
// Section: Dataset Manifest
// ============================================================================

/** Appends a single sample to the local JSONL dataset and refreshes the manifest. */
void AppendDatasetSample(const string &in split, const string &in payload, const string &in labelVehicle) {
    string path = GetDatasetSamplesPath(split);
    if (path.Length == 0 || payload.Length == 0) return;

    try {
        if (!IO::FileExists(path)) {
            IO::File initFile(path, IO::FileMode::Write);
            initFile.Write("");
            initFile.Close();
        }

        IO::File file(path, IO::FileMode::Append);
        file.Write(payload);
        file.Close();

        if (split == "validation") {
            g_ValidationDatasetSamples += 1;
        } else {
            g_TrainDatasetSamples += 1;
        }
        g_TotalDatasetSamples += 1;

        string labelKey = split + "|" + labelVehicle;
        uint labelCount = 0;
        if (g_DatasetSampleCounts.Exists(labelKey)) {
            try {
                labelCount = uint(g_DatasetSampleCounts[labelKey]);
            } catch {
                labelCount = 0;
            }
        }
        g_DatasetSampleCounts[labelKey] = labelCount + 1;
        g_LastDatasetWriteError = "";
        WriteDatasetManifest();
    } catch {
        g_LastDatasetWriteError = "Failed to write sample to: " + path;
    }
}

/** Writes a small manifest describing the current dataset snapshot. */
void WriteDatasetManifest() {
    string dir = GetDatasetRootDir();
    if (dir.Length == 0) return;

    Json::Value root = Json::Object();
    root["schema_name"] = TRAINING_SCHEMA_NAME;
    root["schema_version"] = int(TRAINING_SCHEMA_VERSION);
    root["feature_columns"] = TRAINING_FEATURE_COLUMNS;
    root["updated_at_ms"] = int64(Time::Now);
    root["run_id"] = g_TrainingRunId;
    root["validation_every_n_runs"] = int(S_ValidationEveryNRuns);
    root["save_to_disk"] = S_SaveTrainingSamplesToDisk;
    root["socket_enabled"] = S_EnableTrainingExport;
    root["train_samples"] = int(g_TrainDatasetSamples);
    root["validation_samples"] = int(g_ValidationDatasetSamples);
    root["total_samples"] = int(g_TotalDatasetSamples);

    Json::Value counts = Json::Object();
    array<string> keys = g_DatasetSampleCounts.GetKeys();
    for (uint i = 0; i < keys.Length; i++) {
        string key = keys[i];
        try {
            counts[key] = int(uint(g_DatasetSampleCounts[key]));
        } catch {
            counts[key] = 0;
        }
    }
    root["label_counts"] = counts;

    Json::ToFile(dir + "/dataset_manifest.json", root, true);
}