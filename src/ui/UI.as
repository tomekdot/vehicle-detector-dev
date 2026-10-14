// ============================================================================
// MP4 Vehicle Detector - UI & Rendering
// ============================================================================
// UI module for the Vehicle Detector plugin. 
// Openplanet compiles all .as files in this plugin directory together.
// ============================================================================

// ----------------------------------------------------------------------------
// Section: External Detection State & Actions
// ----------------------------------------------------------------------------

// External detection state (updated from server's latest_detection.json)
string g_ExternalDetectedLabel = "";
float g_ExternalDetectedConfidence = 0.0f;
bool g_ExternalDetectionStale = true;      // file missing, or older than the freshness window
int64 g_ExternalDetectedAgeSec = 0;
int64 g_ExternalFileStamp = -1;            // timestamp field of the file, as a dedupe key
uint64 g_LastDetectionCheckMs = 0;

/**
 * Reads a string field from a Json::Value, or returns "" when the key is
 * missing or is not a string. The explicit type check matters: Json::Value's
 * implicit `string()` conversion THROWS "Json value is not a string!" on a
 * numeric/boolean field, which used to crash the render loop every frame.
 */
string ReadJsonString(Json::Value@ parent, const string &in key) {
    if (parent is null) return "";
    Json::Value@ field = parent.Get(key);
    if (field is null) return "";
    if (field.GetType() != Json::Type::String) return "";
    return string(field);
}

/**
 * Reads a numeric field from a Json::Value, or returns `fallback` when the
 * key is missing or is not a number. Booleans are rejected on purpose — a
 * bool leaking into a confidence/speed field means the file is not what we
 * expect and the value should not be silently coerced to 0/1.
 */
float ReadJsonFloat(Json::Value@ parent, const string &in key, float fallback) {
    if (parent is null) return fallback;
    Json::Value@ field = parent.Get(key);
    if (field is null) return fallback;
    if (field.GetType() != Json::Type::Number) return fallback;
    return float(field);
}

/** Renders an age in seconds compactly: "45 s", "12 min", "135 days". */
string FormatAge(int64 ageSec) {
    if (ageSec < 60) return Text::Format("%d s", int(ageSec));
    if (ageSec < 3600) return Text::Format("%d min", int(ageSec / 60));
    if (ageSec < 86400) return Text::Format("%d h", int(ageSec / 3600));
    return Text::Format("%d days", int(ageSec / 86400));
}

/**
 * Reads the latest external model detection from the JSON file on disk.
 * Every field is type-checked: the server may be mid-write, or the file may
 * come from an older/newer format, and a malformed file must never take the
 * render loop down with it.
 *
 * Freshness is checked too. The file persists after the server stops, so
 * without this a months-old result is displayed as the current car.
 */
void UpdateLatestExternalDetection() {
    g_ExternalDetectedLabel = "";
    g_ExternalDetectedConfidence = 0.0f;
    g_ExternalDetectionStale = true;
    g_ExternalDetectedAgeSec = 0;
    g_ExternalFileStamp = -1;

    string path = IO::FromStorageFolder("mp4-vehicle-detector/latest_detection.json");
    if (!IO::FileExists(path)) return;

    Json::Value@ val = Json::FromFile(path);
    if (val is null) return;

    // "timestamp" is POSIX seconds written by server.py (time.time()), so it
    // compares directly against Time::Stamp — same epoch, both seconds.
    // Time::Stamp is a PROPERTY (declared `int64 get_Stamp()` in the reflection
    // DB), so it takes no parentheses; Time::Parse() would be wrong twice over
    // because it returns an Info struct, not a number.
    Json::Value@ tsField = val.Get("timestamp");
    if (tsField !is null && tsField.GetType() == Json::Type::Number) {
        int64 fileStamp = int64(tsField);
        g_ExternalFileStamp = fileStamp;
        int64 nowStamp = int64(Time::Stamp);
        g_ExternalDetectedAgeSec = nowStamp - fileStamp;
        if (g_ExternalDetectedAgeSec < 0) g_ExternalDetectedAgeSec = 0;
        if (g_ExternalDetectedAgeSec > int64(DETECTION_STALE_SECONDS)) return;
        g_ExternalDetectionStale = false;
    } else {
        // No usable timestamp — treat as untrusted rather than guessing.
        return;
    }

    g_ExternalDetectedLabel = ReadJsonString(val, "label");
    g_ExternalDetectedConfidence = ReadJsonFloat(val, "confidence", 0.0f);
    if (g_ExternalDetectedLabel.Length == 0) {
        g_ExternalDetectionStale = true;
        g_ExternalDetectedConfidence = 0.0f;
    }
}

/**
 * Accepts the active external detection and appends it to the dataset as a Manual sample.
 */
void AcceptExternalDetectionAsManual() {
    if (g_ExternalDetectedLabel.Length == 0) {
        AddTelemetryLine("No external detection available to accept.");
        return;
    }

    auto state = VehicleState::ViewingPlayerState();
    if (state is null) {
        AddTelemetryLine("No vehicle state available to capture sample.");
        return;
    }

    float speedKmh = state.FrontSpeed * 3.6f;
    uint captureStartMs = uint(Time::Now);
    string split = GetDatasetSplitForRun();
    string labelVehicle = g_ExternalDetectedLabel;
    string labelSource = "Manual selection";
    string motionLabel = g_TrainingMotionLabel;

    string payload = BuildTrainingSampleJson(state, speedKmh, captureStartMs, split, labelVehicle, labelSource, motionLabel);
    AppendDatasetSample(split, payload, labelVehicle);
    AddTelemetryLine("Accepted external detection as Manual selection: " + ToPrettyVehicleName(labelVehicle));
}


// ----------------------------------------------------------------------------
// Section: Menu & Basic UI Rendering
// ----------------------------------------------------------------------------

/**
 * Draws toggle items inside the Openplanet overlay menu.
 */
void RenderMenu() {
    if (UI::MenuItem(Icons::Car + " Vehicle Detector", "", S_ShowWindow)) {
        S_ShowWindow = !S_ShowWindow;
    }
    if (UI::MenuItem(Icons::Eye + " Show HUD Overlay", "", S_ShowHudOverlay)) {
        S_ShowHudOverlay = !S_ShowHudOverlay;
    }
    if (UI::MenuItem(Icons::Eye + " Show Detection Window", "", S_ShowDetectionWindow)) {
        S_ShowDetectionWindow = !S_ShowDetectionWindow;
    }
}

/**
 * Draws a compact always-visible HUD panel with live training and vehicle status.
 */
void RenderHudOverlay() {
#if !MP4
    return;
#else
    if (!S_ShowHudOverlay) return;

    const uint flags = UI::WindowFlags::NoSavedSettings | UI::WindowFlags::NoCollapse;
    UI::SetNextWindowSize(120, 0, UI::Cond::FirstUseEver);

    if (UI::Begin(Icons::Car + " Vehicle HUD", flags)) {
        // Update external detection file once per second
        if (Time::Now - g_LastDetectionCheckMs > 1000) {
            g_LastDetectionCheckMs = Time::Now;
            UpdateLatestExternalDetection();
            ScoreModelPrediction();
        }

        // Training control buttons
        if (!g_TrainingCaptureArmed) {
            if (UI::Button("Start training")) StartTrainingSession();
        } else if (g_TrainingCapturePaused) {
            if (UI::Button("Resume training")) ResumeTrainingSession();
            UI::SameLine();
            if (UI::Button("Stop")) StopTrainingSession();
        } else {
            if (UI::Button("Pause training")) PauseTrainingSession();
            UI::SameLine();
            if (UI::Button("Stop")) StopTrainingSession();
        }

        UI::Separator();

        // --- Detected vehicle: the primary readout, always first ---
        UI::Text("Driven vehicle:");
        UI::Text(g_CurrentDisplayName);
        UI::TextDisabled("Source: " + g_CurrentSource + (g_CurrentTrust.Length > 0 ? "  [" + g_CurrentTrust + "]" : ""));

        if (g_MapVehicle.Length > 0 && g_CurrentVehicle != "Unknown" && g_MapVehicle != g_CurrentVehicle) {
            UI::TextDisabled("Map expects " + ToPrettyVehicleName(g_MapVehicle) + ".");
        }

        UI::Separator();

        // Training status
        UI::TextDisabled("State: " + (g_TrainingCaptureArmed ? (g_TrainingCapturePaused ? "Paused" : "Running") : "Stopped"));
        UI::TextDisabled("Mode: " + (S_ContinuousTrainingCapture ? "Continuous" : "Impact triggered"));
        UI::TextDisabled("Motion: " + g_TrainingMotionLabel);

        if (g_TrainingCaptureActive) {
            float elapsedSec = float(Time::Now - g_TrainingCaptureStartMs) / 1000.0f;
            UI::TextDisabled("Segment: " + Text::Format("%.1f s", elapsedSec));
        } else {
            UI::TextDisabled("Waiting for data.");
        }

        // Vehicle label used for training samples
        if (g_SelectedTrainingVehicle.Length > 0) {
            UI::TextDisabled("Training label: " + ToPrettyVehicleName(g_SelectedTrainingVehicle) + " (manual)");
        } else if (g_TrainingLockedVehicle.Length > 0) {
            UI::TextDisabled("Training label: " + ToPrettyVehicleName(g_TrainingLockedVehicle) + " (locked)");
        } else {
            UI::TextDisabled("Training label: auto - follows detected car");
        }

        if (g_TrainingLockedVehicle.Length > 0 && g_CurrentVehicle != g_TrainingLockedVehicle) {
            UI::TextDisabled("Car changed in game; label stays locked.");
        }

        // Server-side model inference results (secondary — never the primary readout)
        if (g_ExternalDetectedLabel.Length > 0 && !g_ExternalDetectionStale) {
            UI::TextDisabled("Model guess: " + ToPrettyVehicleName(g_ExternalDetectedLabel) + " (" + Text::Format("%.0f%%", g_ExternalDetectedConfidence * 100.0f) + ")");
        } else if (g_ExternalDetectedAgeSec > int64(DETECTION_STALE_SECONDS)) {
            UI::TextDisabled("Model: stale (" + FormatAge(g_ExternalDetectedAgeSec) + " old)");
        } else {
            UI::TextDisabled("Model: not running");
        }

        // Live accuracy measured against the game readout, not an offline report.
        if (S_ScoreModelAccuracy) {
            if (g_ModelAgreeing) {
                UI::TextDisabled("Model check: AGREES (streak " + Text::Format("%d", g_ModelStreak) + ")");
            } else if (g_ModelTotal > 0) {
                UI::TextDisabled("Model check: disagrees (streak " + Text::Format("%d", g_ModelStreak) + ")");
            }
            UI::TextDisabled("Model health: " + GetModelHealthVerdict());
            if (g_ModelLastVerdict.Length > 0) {
                UI::TextWrapped(g_ModelLastVerdict);
            }
        }

        UI::Separator();

        // Dropdown selection for active training vehicle
        UI::SetNextItemWidth(UI::GetContentRegionAvail().x);
        if (UI::BeginCombo("##hud", g_SelectedTrainingVehicle.Length > 0 ? ToPrettyVehicleName(g_SelectedTrainingVehicle) : "Select the vehicle")) {
            if (UI::Selectable("Select the vehicle", g_SelectedTrainingVehicle.Length == 0)) {
                SelectTrainingVehicleByIndex(0);
            }
            for (uint i = 1; i <= TRAINING_SUPPORTED_VEHICLE_COUNT; i++) {
                string vehicleKey = GetTrainingVehicleKeyByIndex(i);
                if (vehicleKey.Length == 0) continue;
                if (UI::Selectable(ToPrettyVehicleName(vehicleKey), g_SelectedTrainingVehicle == vehicleKey)) {
                    SelectTrainingVehicleByIndex(i);
                }
            }
            UI::EndCombo();
        }

        if (UI::Button("Accept model guess")) {
            AcceptExternalDetectionAsManual();
        }
    }
    UI::End();
#endif
}

/**
 * Renders a larger detection window showing active vehicle, confidence, thumbnail, and config.
 */
void RenderDetectionWindow() {
#if !MP4
    return;
#else
    if (!S_ShowDetectionWindow) return;

    const uint flags = UI::WindowFlags::NoSavedSettings;
    UI::SetNextWindowSize(280, 300, UI::Cond::FirstUseEver);

    if (!UI::Begin(Icons::Car + " Detected Vehicle", S_ShowDetectionWindow, flags)) {
        UI::End();
        return;
    }

    // --- Primary readout: what the game reports, never the ML model ---
    UI::Text("Driven vehicle:");
    UI::Text(g_CurrentDisplayName);
    UI::TextDisabled("Source: " + g_CurrentSource + (g_CurrentTrust.Length > 0 ? "  [" + g_CurrentTrust + "]" : ""));
    if (g_CurrentRawValue.Length > 0) {
        UI::TextWrapped("Raw: " + g_CurrentRawValue);
    }

    if (g_MapVehicle.Length > 0 && g_CurrentVehicle != "Unknown" && g_MapVehicle != g_CurrentVehicle) {
        UI::TextWrapped("Map expects " + ToPrettyVehicleName(g_MapVehicle) + ".");
    }

    // --- Thumbnail of the detected car ---
    UI::Texture@ tex = GetVehicleTexture(g_CurrentVehicle);
    if (tex !is null) {
        UI::Image(tex, vec2(240, 130));
    } else {
        UI::TextDisabled("No thumbnail available.");
    }

    UI::Separator();

    // --- ML model, demoted to a secondary line with an explicit health note ---
    int64 modelAge = g_ExternalDetectedAgeSec;
    if (modelAge > int64(DETECTION_STALE_SECONDS)) {
        UI::TextDisabled("Model: stale (" + FormatAge(modelAge) + " old) - ignored.");
    } else if (g_ExternalDetectedLabel.Length == 0) {
        UI::TextDisabled("Model: not running.");
    } else {
        UI::TextDisabled("Model guess: " + ToPrettyVehicleName(g_ExternalDetectedLabel)
            + " (" + Text::Format("%.0f%%", g_ExternalDetectedConfidence * 100.0f) + ")");
        UI::TextDisabled("Model accuracy is low - the game readout above is authoritative.");
        if (UI::Button("Accept model guess as label")) {
            AcceptExternalDetectionAsManual();
        }
    }

    UI::Separator();
    if (UI::Button(S_EnableTrainingExport ? "Disable sample export" : "Enable sample export")) {
        S_EnableTrainingExport = !S_EnableTrainingExport;
    }

    UI::End();
#endif
}

/**
 * Main plugin telemetry window. Renders incompatibility notices on non-MP4 setups.
 */
void Render() {
#if !MP4
    // --- Incompatible build (Not Maniaplanet 4) ---
    if (!S_ShowWindow) return;
    if (UI::Begin(Icons::Car + " Vehicle Detector", S_ShowWindow)) {
        UI::Text("This plugin is designed for ManiaPlanet 4.");
    }
    UI::End();
    return;
#else
    // --- Full ManiaPlanet 4 execution panel ---
    RenderHudOverlay();
    RenderDetectionWindow();
    if (!S_ShowWindow) return;

    UI::SetNextWindowSize(500, 420, UI::Cond::FirstUseEver);
    if (!UI::Begin(Icons::Car + " Vehicle Detector", S_ShowWindow)) {
        UI::End();
        return;
    }

    // Active vehicle properties
    UI::Text("Current vehicle:");
    UI::Separator();
    UI::Text(g_CurrentDisplayName);
    UI::TextDisabled("Code: " + g_CurrentVehicle);
    UI::TextDisabled("Source: " + g_CurrentSource + (g_CurrentTrust.Length > 0 ? " (" + g_CurrentTrust + ")" : ""));
    if (g_CurrentRawValue.Length > 0) {
        UI::TextWrapped("Raw: " + g_CurrentRawValue);
    }

    // Warning when the map expects a different vehicle than the one detected.
    if (g_MapVehicle.Length > 0 && g_CurrentVehicle != "Unknown" && g_MapVehicle != g_CurrentVehicle) {
        UI::TextWrapped("Map expects " + ToPrettyVehicleName(g_MapVehicle) + " but you drive " + g_CurrentDisplayName + ".");
    }

    // Graphic render thumbnail
    UI::Separator();
    UI::Texture@ tex = GetVehicleTexture(g_CurrentVehicle);
    if (tex !is null) {
        UI::Image(tex, vec2(220, 120));
        string texPath = GetVehicleTexturePath(g_CurrentVehicle);
        if (texPath.Length > 0) UI::TextDisabled("Texture: " + texPath);
    } else {
        UI::TextDisabled("No thumbnail available for this entry.");
    }

    // Live telemetry properties (VehicleState)
    auto state = VehicleState::ViewingPlayerState();
    if (state !is null) {
        UI::Separator();
        UI::Text("VehicleState telemetry:");
        UI::Text("Speed: " + Text::Format("%.1f km/h", state.FrontSpeed * 3.6f));
        UI::Text("Gear: " + Text::Format("%d", state.CurGear));
        UI::Text("Gas: " + Text::Format("%.2f", state.InputGasPedal));
        UI::Text("Steer: " + Text::Format("%.2f", state.InputSteer));
        UI::Text("Brake: " + (state.InputIsBraking ? "yes" : "no"));
        UI::Text("Ground contact: " + (state.IsGroundContact ? "yes" : "no"));
        UI::Text("RPM: " + Text::Format("%.0f", state.RPM));
        UI::Text("Side speed: " + Text::Format("%.2f", state.SideSpeed));
        UI::Text("Wheel contact: " + Text::Format("%d", GetWheelContactCount(state)));
        UI::Text("Average slip: " + Text::Format("%.3f", GetAverageWheelSlip(state)));
        UI::Text("Wet wheels: " + Text::Format("%d", GetWetWheelCount(state)));
        UI::Text("Active effects: " + Text::Format("%d", state.ActiveEffects));
        UI::Text("Surface: " + GetSurfaceSummary());
    }

    // 0-100 km/h acceleration testing
    UI::Separator();
    UI::Text("0-100 km/h timings:");
    if (g_RunActive) {
        float elapsedSec = float(Time::Now - g_RunStartMs) / 1000.0f;
        UI::Text("Measurement in progress: " + Text::Format("%.2f s", elapsedSec));
    } else if (g_RunCompleted && g_LastZeroToHundredSec >= 0.0f) {
        UI::Text("Last time: " + Text::Format("%.2f s", g_LastZeroToHundredSec));
    } else {
        UI::TextDisabled("No completed measurement");
    }
    if (g_BestZeroToHundredSec >= 0.0f) {
        UI::Text("Best time: " + Text::Format("%.2f s", g_BestZeroToHundredSec));
    }

    // Session controls and ports
    UI::Separator();
    UI::Text("Training / Telemetry exports:");
    UI::TextDisabled("Trusted labels come from the game readout or Manual selection");
    UI::TextDisabled("The ML model is a guess only - low accuracy, shown as 'Model guess'");
    UI::TextDisabled("Training mode: " + (S_ContinuousTrainingCapture ? "Continuous segments" : "Impact-triggered captures"));
    UI::TextDisabled("Samples streamed to 127.0.0.1:" + S_TrainingExportPort);
    UI::TextDisabled("Hotkeys: Win+M, Menu or Ctrl+M pause/resume, M stop");
    UI::Text("Current training run: #" + Text::Format("%d", g_TrainingRunId));
    UI::Text("Network export status: " + (S_EnableTrainingExport ? "Enabled" : "Disabled"));

    if (!g_TrainingCaptureArmed) {
        if (UI::Button("Start training##main")) StartTrainingSession();
    } else if (g_TrainingCapturePaused) {
        if (UI::Button("Resume training##main")) ResumeTrainingSession();
        UI::SameLine();
        if (UI::Button("Stop training##main")) StopTrainingSession();
    } else {
        if (UI::Button("Pause training##main")) PauseTrainingSession();
        UI::SameLine();
        if (UI::Button("Stop training##main")) StopTrainingSession();
    }

    UI::TextDisabled("State: " + (g_TrainingCaptureArmed ? (g_TrainingCapturePaused ? "Paused" : "Running") : "Stopped"));
    if (g_TrainingCaptureActive) {
        float elapsedSec = float(Time::Now - g_TrainingCaptureStartMs) / 1000.0f;
        UI::Text("Current motion: " + g_TrainingMotionLabel);
        UI::Text("Segment time: " + Text::Format("%.2f s", elapsedSec));
    } else {
        UI::TextDisabled("Training capture waiting for vehicle state.");
    }

    // Local data storage diagnostics
    UI::Separator();
    UI::Text("Dataset Storage:");
    UI::Text("Local save: " + (S_SaveTrainingSamplesToDisk ? "Enabled" : "Disabled"));
    UI::Text("Split ratio: validation every " + tostring(S_ValidationEveryNRuns) + " runs");
    UI::Text("Current split: " + GetDatasetSplitForRun());
    UI::Text("Samples saved: " + tostring(g_TotalDatasetSamples) + " (train " + tostring(g_TrainDatasetSamples) + ", validation " + tostring(g_ValidationDatasetSamples) + ")");
    UI::TextDisabled("Train file: " + GetDatasetSamplesPath("train"));
    UI::TextDisabled("Validation file: " + GetDatasetSamplesPath("validation"));
    if (g_LastDatasetWriteError.Length > 0) {
        UI::Text("Last write error: " + g_LastDatasetWriteError);
    }

    // Dropdown config selection
    UI::Separator();
    UI::Text("Training Vehicle Selection:");
    if (UI::BeginCombo("Vehicle##trainingVehicle", g_SelectedTrainingVehicle.Length > 0 ? ToPrettyVehicleName(g_SelectedTrainingVehicle) : "Auto (Detection)")) {
        if (UI::Selectable("Auto (Detection)", g_SelectedTrainingVehicle.Length == 0)) {
            SelectTrainingVehicleByIndex(0);
        }
        for (uint i = 1; i <= TRAINING_SUPPORTED_VEHICLE_COUNT; i++) {
            string vehicleKey = GetTrainingVehicleKeyByIndex(i);
            if (vehicleKey.Length == 0) continue;

            if (UI::Selectable(tostring(i) + ". " + ToPrettyVehicleName(vehicleKey), g_SelectedTrainingVehicle == vehicleKey)) {
                SelectTrainingVehicleByIndex(i);
            }
        }
        UI::EndCombo();
    }

    // Per-wheel surface overlay
    RenderSurfaces();

    // Telemetry collapsible diagnostics
    if (S_ShowTelemetryPanel && UI::CollapsingHeader("Telemetry / Debug")) {
        UI::TextDisabled("Last update: " + tostring(g_LastTelemetryUpdate));
        if (g_CurrentTelemetry.Length == 0) {
            UI::TextDisabled("No telemetry data available.");
        } else {
            for (uint i = 0; i < g_CurrentTelemetry.Length; i++) {
                UI::TextWrapped(g_CurrentTelemetry[i]);
            }
        }
    }

    UI::End();
#endif
}

// ---------------------------------------------------------------------------
// Section: Per-wheel Surface Layout Overlay (Surface Overlay)
// ---------------------------------------------------------------------------

#if MP4
/**
 * Resolves the surface material ESurfId into its full, original, technical name.
 */
string SurfaceMaterialName(CAudioSourceSurface::ESurfId mat) {
    if (S_SurfaceRaw) return tostring(mat);
    switch (mat) {
        // --- Road surfaces ---
        case CAudioSourceSurface::ESurfId::Concrete:                  return "Concrete";
        case CAudioSourceSurface::ESurfId::Asphalt:                   return "Asphalt";
        case CAudioSourceSurface::ESurfId::Pavement:                  return "Pavement";
        case CAudioSourceSurface::ESurfId::WetAsphalt:                return "WetAsphalt";
        case CAudioSourceSurface::ESurfId::WetPavement:               return "WetPavement";
        case CAudioSourceSurface::ESurfId::PavementStair:             return "PavementStair";

        // --- Off-road terrain ---
        case CAudioSourceSurface::ESurfId::Grass:                     return "Grass";
        case CAudioSourceSurface::ESurfId::WetGrass:                  return "WetGrass";
        case CAudioSourceSurface::ESurfId::Forest:                    return "Forest";
        case CAudioSourceSurface::ESurfId::Wheat:                     return "Wheat";
        case CAudioSourceSurface::ESurfId::Dirt:                      return "Dirt";
        case CAudioSourceSurface::ESurfId::DirtRoad:                  return "DirtRoad";
        case CAudioSourceSurface::ESurfId::WetDirtRoad:               return "WetDirtRoad";
        case CAudioSourceSurface::ESurfId::Gravel:                    return "Gravel";
        case CAudioSourceSurface::ESurfId::Sand:                      return "Sand";
        case CAudioSourceSurface::ESurfId::Rock:                      return "Rock";
        case CAudioSourceSurface::ESurfId::Stone:                     return "Stone";
        case CAudioSourceSurface::ESurfId::Wood:                      return "Wood";
        case CAudioSourceSurface::ESurfId::Trunk:                     return "Trunk";
        case CAudioSourceSurface::ESurfId::SlidingWood:               return "SlidingWood";
        case CAudioSourceSurface::ESurfId::Snow:                      return "Snow";
        case CAudioSourceSurface::ESurfId::Water:                     return "Water";

        // --- Metal & Tech ---
        case CAudioSourceSurface::ESurfId::Metal:                     return "Metal";
        case CAudioSourceSurface::ESurfId::MetalFence:                return "MetalFence";
        case CAudioSourceSurface::ESurfId::ResonantMetal:             return "ResonantMetal";
        case CAudioSourceSurface::ESurfId::MetalTrans:                return "MetalTrans";

        // --- Ice ---
        case CAudioSourceSurface::ESurfId::Ice:                       return "Ice";
        case CAudioSourceSurface::ESurfId::CustomIce:                 return "CustomIce";

        // --- Boost / Turbo ---
        case CAudioSourceSurface::ESurfId::Turbo:                     return "Turbo";
        case CAudioSourceSurface::ESurfId::Turbo2:                    return "Turbo2";
        case CAudioSourceSurface::ESurfId::TurboRoulette:             return "TurboRoulette";
        case CAudioSourceSurface::ESurfId::TurboWood:                 return "TurboWood";
        case CAudioSourceSurface::ESurfId::Turbo2Wood:                return "Turbo2Wood";
        case CAudioSourceSurface::ESurfId::TechMagnetic:              return "TechMagnetic";
        case CAudioSourceSurface::ESurfId::TurboTechMagnetic:        return "TurboTechMagnetic";
        case CAudioSourceSurface::ESurfId::Turbo2TechMagnetic:       return "Turbo2TechMagnetic";
        case CAudioSourceSurface::ESurfId::TechMagneticAccel:        return "TechMagneticAccel";
        case CAudioSourceSurface::ESurfId::TechSuperMagnetic:        return "TechSuperMagnetic";
        case CAudioSourceSurface::ESurfId::FreeWheeling:              return "FreeWheeling";
        case CAudioSourceSurface::ESurfId::FreeWheelingTechMagnetic: return "FreeWheelingTechMagnetic";
        case CAudioSourceSurface::ESurfId::FreeWheelingWood:          return "FreeWheelingWood";

        // --- Colliders & Barriers ---
        case CAudioSourceSurface::ESurfId::Rubber:                    return "Rubber";
        case CAudioSourceSurface::ESurfId::SlidingRubber:             return "SlidingRubber";
        case CAudioSourceSurface::ESurfId::RubberBand:                return "RubberBand";
        case CAudioSourceSurface::ESurfId::Bumper:                    return "Bumper";
        case CAudioSourceSurface::ESurfId::Bumper2:                   return "Bumper2";
        case CAudioSourceSurface::ESurfId::WallJump:                  return "WallJump";
        case CAudioSourceSurface::ESurfId::NotCollidable:             return "NotCollidable";

        // --- Special ---
        case CAudioSourceSurface::ESurfId::Danger:                    return "Danger";
        case CAudioSourceSurface::ESurfId::Test:                      return "Test";
        case CAudioSourceSurface::ESurfId::GolfBall:                  return "GolfBall";
        case CAudioSourceSurface::ESurfId::GolfWall:                  return "GolfWall";
        case CAudioSourceSurface::ESurfId::GolfGround:                return "GolfGround";
        case CAudioSourceSurface::ESurfId::OffZone:                   return "OffZone";
        case CAudioSourceSurface::ESurfId::Bullet:                    return "Bullet";
        case CAudioSourceSurface::ESurfId::Energy:                    return "Energy";

        // --- Tech Zones ---
        case CAudioSourceSurface::ESurfId::Tech:                      return "Tech";
        case CAudioSourceSurface::ESurfId::TechArmor:                 return "TechArmor";
        case CAudioSourceSurface::ESurfId::TechSafe:                  return "TechSafe";
        case CAudioSourceSurface::ESurfId::TechHook:                  return "TechHook";
        case CAudioSourceSurface::ESurfId::TechHook2:                 return "TechHook2";
        case CAudioSourceSurface::ESurfId::TechGround:                return "TechGround";
        case CAudioSourceSurface::ESurfId::TechWall:                  return "TechWall";
        case CAudioSourceSurface::ESurfId::TechArrow:                 return "TechArrow";
        case CAudioSourceSurface::ESurfId::TechTarget:                return "TechTarget";
        case CAudioSourceSurface::ESurfId::TechTeleport:              return "TechTeleport";
        case CAudioSourceSurface::ESurfId::TechLaser:                 return "TechLaser";
        case CAudioSourceSurface::ESurfId::TechNucleus:               return "TechNucleus";
        case CAudioSourceSurface::ESurfId::TechGravityChange:         return "TechGravityChange";
        case CAudioSourceSurface::ESurfId::TechGravityReset:          return "TechGravityReset";

        // --- Player / Vehicle ---
        case CAudioSourceSurface::ESurfId::Player:                    return "Player";
        case CAudioSourceSurface::ESurfId::PlayerOnly:                return "PlayerOnly";
        case CAudioSourceSurface::ESurfId::NoGrip:                    return "NoGrip";
        case CAudioSourceSurface::ESurfId::NoSteering:                return "NoSteering";
        case CAudioSourceSurface::ESurfId::NoBrakes:                  return "NoBrakes";

        // --- Fallback ---
        default: {
            return "Surface_" + tostring(int(mat));
        }
    }
}
#endif

/**
 * Draws the schematic overlay of wheel placements with their active original material names.
 */
// ---------------------------------------------------------------------------
// Surface overlay — per-wheel ground contact material display
// ---------------------------------------------------------------------------
// Renders a polished wheel-surface panel: 2x2 grid with colored circles
// representing each wheel (FL, FR, RL, RR). Circle color reflects the
// surface type (green=road, brown=dirt, blue=ice, etc.). Material name
// and wheel label shown alongside. Position/size configurable via settings.
// ---------------------------------------------------------------------------

// Map a surface material to a display color for the wheel circle.
#if MP4
vec4 SurfaceMaterialColor(CAudioSourceSurface::ESurfId mat) {
    switch (mat) {
        // road — green
        case CAudioSourceSurface::ESurfId::Concrete:
        case CAudioSourceSurface::ESurfId::Asphalt:
        case CAudioSourceSurface::ESurfId::Pavement:
        case CAudioSourceSurface::ESurfId::WetAsphalt:
        case CAudioSourceSurface::ESurfId::WetPavement:
        case CAudioSourceSurface::ESurfId::PavementStair:             return vec4(0.20f, 0.75f, 0.35f, 1.0f);

        // grass / nature — green-yellow
        case CAudioSourceSurface::ESurfId::Grass:
        case CAudioSourceSurface::ESurfId::WetGrass:
        case CAudioSourceSurface::ESurfId::Forest:
        case CAudioSourceSurface::ESurfId::Wheat:                     return vec4(0.45f, 0.80f, 0.20f, 1.0f);

        // dirt / gravel — brown
        case CAudioSourceSurface::ESurfId::Dirt:
        case CAudioSourceSurface::ESurfId::DirtRoad:
        case CAudioSourceSurface::ESurfId::WetDirtRoad:
        case CAudioSourceSurface::ESurfId::Gravel:                    return vec4(0.70f, 0.45f, 0.15f, 1.0f);

        // sand — tan
        case CAudioSourceSurface::ESurfId::Sand:                      return vec4(0.85f, 0.75f, 0.40f, 1.0f);

        // rock / stone — grey
        case CAudioSourceSurface::ESurfId::Rock:
        case CAudioSourceSurface::ESurfId::Stone:                     return vec4(0.55f, 0.55f, 0.58f, 1.0f);

        // wood — amber
        case CAudioSourceSurface::ESurfId::Wood:
        case CAudioSourceSurface::ESurfId::Trunk:
        case CAudioSourceSurface::ESurfId::SlidingWood:               return vec4(0.75f, 0.55f, 0.20f, 1.0f);

        // snow — white-blue
        case CAudioSourceSurface::ESurfId::Snow:                      return vec4(0.80f, 0.88f, 0.98f, 1.0f);

        // water — blue
        case CAudioSourceSurface::ESurfId::Water:                     return vec4(0.20f, 0.50f, 0.90f, 1.0f);

        // metal — steel
        case CAudioSourceSurface::ESurfId::Metal:
        case CAudioSourceSurface::ESurfId::MetalFence:                return vec4(0.60f, 0.65f, 0.75f, 1.0f);
        case CAudioSourceSurface::ESurfId::ResonantMetal:             return vec4(0.50f, 0.55f, 0.65f, 1.0f);
        case CAudioSourceSurface::ESurfId::MetalTrans:                return vec4(0.65f, 0.70f, 0.80f, 1.0f);

        // ice — cyan
        case CAudioSourceSurface::ESurfId::Ice:
        case CAudioSourceSurface::ESurfId::CustomIce:                 return vec4(0.40f, 0.85f, 0.95f, 1.0f);

        // turbo / boost — orange
        case CAudioSourceSurface::ESurfId::Turbo:                     return vec4(0.95f, 0.50f, 0.10f, 1.0f);
        case CAudioSourceSurface::ESurfId::Turbo2:                    return vec4(0.95f, 0.30f, 0.10f, 1.0f);
        case CAudioSourceSurface::ESurfId::TurboRoulette:             return vec4(0.95f, 0.50f, 0.10f, 1.0f);
        case CAudioSourceSurface::ESurfId::TurboWood:                 return vec4(0.85f, 0.55f, 0.15f, 1.0f);
        case CAudioSourceSurface::ESurfId::Turbo2Wood:                return vec4(0.85f, 0.40f, 0.10f, 1.0f);

        // magnetic — purple
        case CAudioSourceSurface::ESurfId::TechMagnetic:              return vec4(0.65f, 0.30f, 0.90f, 1.0f);
        case CAudioSourceSurface::ESurfId::TurboTechMagnetic:        return vec4(0.75f, 0.35f, 0.85f, 1.0f);
        case CAudioSourceSurface::ESurfId::Turbo2TechMagnetic:       return vec4(0.75f, 0.25f, 0.80f, 1.0f);
        case CAudioSourceSurface::ESurfId::TechMagneticAccel:        return vec4(0.60f, 0.20f, 0.95f, 1.0f);
        case CAudioSourceSurface::ESurfId::TechSuperMagnetic:        return vec4(0.80f, 0.20f, 0.95f, 1.0f);
        case CAudioSourceSurface::ESurfId::FreeWheeling:              return vec4(0.50f, 0.50f, 0.50f, 1.0f);
        case CAudioSourceSurface::ESurfId::FreeWheelingTechMagnetic: return vec4(0.60f, 0.40f, 0.80f, 1.0f);
        case CAudioSourceSurface::ESurfId::FreeWheelingWood:          return vec4(0.60f, 0.45f, 0.25f, 1.0f);

        // barriers / rubber — red
        case CAudioSourceSurface::ESurfId::Rubber:
        case CAudioSourceSurface::ESurfId::SlidingRubber:
        case CAudioSourceSurface::ESurfId::RubberBand:                return vec4(0.90f, 0.20f, 0.20f, 1.0f);
        case CAudioSourceSurface::ESurfId::Bumper:                    return vec4(0.85f, 0.15f, 0.15f, 1.0f);
        case CAudioSourceSurface::ESurfId::Bumper2:                   return vec4(0.95f, 0.10f, 0.10f, 1.0f);
        case CAudioSourceSurface::ESurfId::WallJump:                  return vec4(0.80f, 0.25f, 0.25f, 1.0f);
        case CAudioSourceSurface::ESurfId::NotCollidable:             return vec4(0.50f, 0.50f, 0.50f, 0.5f);

        // special — yellow
        case CAudioSourceSurface::ESurfId::Danger:                    return vec4(0.95f, 0.80f, 0.10f, 1.0f);
        case CAudioSourceSurface::ESurfId::Test:                      return vec4(0.90f, 0.90f, 0.20f, 1.0f);
        case CAudioSourceSurface::ESurfId::GolfBall:
        case CAudioSourceSurface::ESurfId::GolfWall:
        case CAudioSourceSurface::ESurfId::GolfGround:                return vec4(0.30f, 0.85f, 0.40f, 1.0f);
        case CAudioSourceSurface::ESurfId::OffZone:                   return vec4(0.95f, 0.50f, 0.05f, 1.0f);
        case CAudioSourceSurface::ESurfId::Bullet:                    return vec4(0.90f, 0.60f, 0.10f, 1.0f);
        case CAudioSourceSurface::ESurfId::Energy:                    return vec4(0.30f, 0.80f, 0.95f, 1.0f);

        // tech zones — teal
        case CAudioSourceSurface::ESurfId::Tech:                      return vec4(0.20f, 0.80f, 0.75f, 1.0f);
        case CAudioSourceSurface::ESurfId::TechArmor:                 return vec4(0.25f, 0.75f, 0.85f, 1.0f);
        case CAudioSourceSurface::ESurfId::TechSafe:                  return vec4(0.30f, 0.85f, 0.60f, 1.0f);
        case CAudioSourceSurface::ESurfId::TechHook:
        case CAudioSourceSurface::ESurfId::TechHook2:                 return vec4(0.35f, 0.70f, 0.90f, 1.0f);
        case CAudioSourceSurface::ESurfId::TechGround:                return vec4(0.20f, 0.70f, 0.80f, 1.0f);
        case CAudioSourceSurface::ESurfId::TechWall:                  return vec4(0.30f, 0.65f, 0.85f, 1.0f);
        case CAudioSourceSurface::ESurfId::TechArrow:                 return vec4(0.40f, 0.75f, 0.90f, 1.0f);
        case CAudioSourceSurface::ESurfId::TechTarget:                return vec4(0.25f, 0.80f, 0.70f, 1.0f);
        case CAudioSourceSurface::ESurfId::TechTeleport:              return vec4(0.35f, 0.85f, 0.95f, 1.0f);
        case CAudioSourceSurface::ESurfId::TechLaser:                 return vec4(0.50f, 0.90f, 0.95f, 1.0f);
        case CAudioSourceSurface::ESurfId::TechNucleus:               return vec4(0.30f, 0.75f, 0.90f, 1.0f);
        case CAudioSourceSurface::ESurfId::TechGravityChange:         return vec4(0.40f, 0.60f, 0.95f, 1.0f);
        case CAudioSourceSurface::ESurfId::TechGravityReset:          return vec4(0.35f, 0.55f, 0.90f, 1.0f);

        // player / vehicle — white
        case CAudioSourceSurface::ESurfId::Player:                    return vec4(0.95f, 0.95f, 0.95f, 1.0f);
        case CAudioSourceSurface::ESurfId::PlayerOnly:                return vec4(0.90f, 0.90f, 0.90f, 1.0f);
        case CAudioSourceSurface::ESurfId::NoGrip:                    return vec4(0.70f, 0.70f, 0.70f, 1.0f);
        case CAudioSourceSurface::ESurfId::NoSteering:                return vec4(0.65f, 0.65f, 0.65f, 1.0f);
        case CAudioSourceSurface::ESurfId::NoBrakes:                  return vec4(0.60f, 0.60f, 0.60f, 1.0f);

        // unknown — dim grey
        default:                                                     return vec4(0.40f, 0.40f, 0.42f, 0.8f);
    }
}
#endif

void RenderSurfaces() {
#if !MP4
    return;
#else
    if (!S_ShowSurfaces) return;

    auto state = VehicleState::ViewingPlayerState();
    if (state is null) return;

    int displayWidth = Display::GetWidth();
    int displayHeight = Display::GetHeight();

    // Layout: wider panel with wheel circles + labels
    int panelW = S_SurfaceWidth;
    int panelH = S_SurfaceHeight;
    int x = int(S_SurfaceX * displayWidth);
    int y = int(S_SurfaceY * displayHeight);

    // Clamp to screen
    if (x + panelW > displayWidth) x = displayWidth - panelW - 4;
    if (y + panelH > displayHeight) y = displayHeight - panelH - 4;
    if (x < 0) x = 0;
    if (y < 0) y = 0;

    float halfW = panelW * 0.5f;
    float halfH = panelH * 0.5f;

    // --- Background panel ---
    nvg::BeginPath();
    nvg::RoundedRect(vec2(x, y), vec2(panelW, panelH), 6.0f);
    nvg::FillColor(vec4(0.06f, 0.07f, 0.10f, 0.88f));
    nvg::Fill();

    // --- Border ---
    nvg::StrokeWidth(1.5f);
    nvg::StrokeColor(vec4(0.35f, 0.45f, 0.65f, 0.5f));
    nvg::BeginPath();
    nvg::RoundedRect(vec2(x, y), vec2(panelW, panelH), 6.0f);
    nvg::Stroke();

    // --- Inner dividers ---
    nvg::StrokeWidth(1.0f);
    nvg::StrokeColor(vec4(0.25f, 0.30f, 0.40f, 0.4f));
    // vertical
    nvg::BeginPath();
    nvg::MoveTo(vec2(x + halfW, y + 2));
    nvg::LineTo(vec2(x + halfW, y + panelH - 2));
    nvg::Stroke();
    // horizontal
    nvg::BeginPath();
    nvg::MoveTo(vec2(x + 2, y + halfH));
    nvg::LineTo(vec2(x + panelW - 2, y + halfH));
    nvg::Stroke();

    // Per-wheel rendering — 4 explicit calls (no loops/arrays — AngelScript limitation)
    float circleR = Math::Min(halfW, halfH) * 0.30f;
    float lblFontSize = Math::Max(9.0f, S_SurfaceFontSize * 0.5f);
    float matFontSize = S_SurfaceFontSize;

    DrawWheelSurface(x + halfW * 0.45f, y + halfH * 0.45f, circleR, lblFontSize, matFontSize, "FL", state.FLGroundContactMaterial);
    DrawWheelSurface(x + halfW + halfW * 0.45f, y + halfH * 0.45f, circleR, lblFontSize, matFontSize, "FR", state.FRGroundContactMaterial);
    DrawWheelSurface(x + halfW * 0.45f, y + halfH + halfH * 0.45f, circleR, lblFontSize, matFontSize, "RL", state.RLGroundContactMaterial);
    DrawWheelSurface(x + halfW + halfW * 0.45f, y + halfH + halfH * 0.45f, circleR, lblFontSize, matFontSize, "RR", state.RRGroundContactMaterial);
#endif
}

/** Draws a single colored wheel circle with material name label. */
void DrawWheelSurface(float cx, float cy, float circleR, float lblFontSize, float matFontSize, const string &in label, CAudioSourceSurface::ESurfId mat) {
#if !MP4
    return;
#else
    vec4 col = SurfaceMaterialColor(mat);
    string matName = SurfaceMaterialName(mat);

    // Glow
    nvg::BeginPath();
    nvg::Circle(vec2(cx, cy), circleR * 1.4f);
    nvg::FillColor(vec4(col.x, col.y, col.z, 0.15f));
    nvg::Fill();

    // Main circle
    nvg::BeginPath();
    nvg::Circle(vec2(cx, cy), circleR);
    nvg::FillColor(col);
    nvg::Fill();

    // Circle border
    nvg::StrokeWidth(1.5f);
    nvg::StrokeColor(vec4(1.0f, 1.0f, 1.0f, 0.3f));
    nvg::BeginPath();
    nvg::Circle(vec2(cx, cy), circleR);
    nvg::Stroke();

    // Wheel label (FL/FR/RL/RR)
    nvg::BeginPath();
    nvg::FontSize(lblFontSize);
    nvg::FillColor(vec4(0.55f, 0.60f, 0.70f, 0.8f));
    nvg::TextAlign(nvg::Align::Top | nvg::Align::Left);
    nvg::TextBox(vec2(cx - circleR, cy - circleR - lblFontSize - 2), circleR * 2, label);

    // Material name below circle
    nvg::BeginPath();
    nvg::FontSize(matFontSize);
    float luma = col.x * 0.299f + col.y * 0.587f + col.z * 0.114f;
    if (luma > 0.6f) {
        nvg::FillColor(vec4(0.08f, 0.08f, 0.10f, 1.0f));
    } else {
        nvg::FillColor(vec4(0.92f, 0.94f, 0.98f, 1.0f));
    }
    nvg::TextAlign(nvg::Align::Top | nvg::Align::Center);
    nvg::TextBox(vec2(cx - circleR - 4, cy + circleR + 3), circleR * 2 + 8, matName);
#endif
}

/**
 * Returns a compact textual summary representation of the active wheel surfaces.
 */
string GetSurfaceSummary() {
#if !MP4
    return "N/A";
#else
    auto state = VehicleState::ViewingPlayerState();
    if (state is null) return "N/A";

    string fl = SurfaceMaterialName(state.FLGroundContactMaterial);
    string fr = SurfaceMaterialName(state.FRGroundContactMaterial);
    string rl = SurfaceMaterialName(state.RLGroundContactMaterial);
    string rr = SurfaceMaterialName(state.RRGroundContactMaterial);

    if (fl == fr && fr == rl && rl == rr) return fl;
    if (fl == fr && rl == rr) return fl + " | " + rl;
    return fl + "/" + fr + "/" + rl + "/" + rr;
#endif
}