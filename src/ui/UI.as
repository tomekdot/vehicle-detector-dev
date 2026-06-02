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
uint64 g_LastDetectionCheckMs = 0;

/**
 * Reads the latest external model detection from the JSON file on disk.
 */
void UpdateLatestExternalDetection() {
    string path = IO::FromStorageFolder("mp4-vehicle-detector/latest_detection.json");
    if (!IO::FileExists(path)) {
        g_ExternalDetectedLabel = "";
        g_ExternalDetectedConfidence = 0.0f;
        return;
    }

    Json::Value@ val = Json::FromFile(path);
    if (val is null) {
        g_ExternalDetectedLabel = "";
        g_ExternalDetectedConfidence = 0.0f;
        return;
    }

    if (val.Get("label") !is null) {
        g_ExternalDetectedLabel = string(val.Get("label"));
    }
    if (val.Get("confidence") !is null) {
        g_ExternalDetectedConfidence = Text::ParseFloat(string(val.Get("confidence")));
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

        // Status details
        UI::TextDisabled("State: " + (g_TrainingCaptureArmed ? (g_TrainingCapturePaused ? "Paused" : "Running") : "Stopped"));
        UI::Text("Training: " + (g_TrainingCaptureActive ? "Active" : "Inactive"));
        UI::TextDisabled("Mode: " + (S_ContinuousTrainingCapture ? "Continuous" : "Impact triggered"));
        UI::TextDisabled("Motion: " + g_TrainingMotionLabel);

        if (g_TrainingCaptureActive) {
            float elapsedSec = float(Time::Now - g_TrainingCaptureStartMs) / 1000.0f;
            UI::Text("Segment time: " + Text::Format("%.2f s", elapsedSec));
        } else {
            UI::TextDisabled("Waiting for data.");
        }

        // Vehicle labels
        if (g_SelectedTrainingVehicle.Length > 0) {
            UI::TextDisabled("Label: " + ToPrettyVehicleName(g_SelectedTrainingVehicle));
        } else if (g_TrainingLockedVehicle.Length > 0) {
            UI::TextDisabled("Label: " + ToPrettyVehicleName(g_TrainingLockedVehicle) + " (locked)");
        } else {
            UI::TextDisabled("Label: Auto (Detection)");
        }

        // Server-side model inference results
        if (g_ExternalDetectedLabel.Length > 0) {
            UI::Text("External detection: " + ToPrettyVehicleName(g_ExternalDetectedLabel) + " (" + Text::Format("%.0f", g_ExternalDetectedConfidence * 100.0f) + "%)");
        } else {
            UI::TextDisabled("External detection: unknown");
        }

        if (g_TrainingLockedVehicle.Length > 0 && g_CurrentVehicle != g_TrainingLockedVehicle) {
            UI::TextDisabled("Vehicle changed in game; training label stays locked.");
        }

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

        UI::SameLine();
        if (UI::Button("Accept detection as Manual")) {
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
    UI::SetNextWindowSize(260, 160, UI::Cond::FirstUseEver);

    if (!UI::Begin(Icons::Car + " Detected Vehicle", S_ShowDetectionWindow, flags)) {
        UI::End();
        return;
    }

    if (g_ExternalDetectedLabel.Length == 0) {
        UI::TextDisabled("Detected: unknown");
    } else {
        UI::Text("Detected:");
        UI::SameLine();
        UI::Text(" " + ToPrettyVehicleName(g_ExternalDetectedLabel));
        UI::TextDisabled("Confidence: " + Text::Format("%.1f%%", g_ExternalDetectedConfidence * 100.0f));

        UI::Separator();
        UI::Text("Thumbnail:");
        UI::Texture@ detectedTex = GetVehicleTexture(g_ExternalDetectedLabel);
        if (detectedTex !is null) {
            UI::Image(detectedTex, vec2(120, 60));
        } else {
            UI::TextDisabled("No thumbnail available.");
        }

        // Export toggle configurations
        if (S_EnableTrainingExport) {
            UI::Text("Export: Enabled");
            if (UI::Button("Disable export")) S_EnableTrainingExport = false;
        } else {
            UI::Text("Export: Disabled");
            if (UI::Button("Enable export")) S_EnableTrainingExport = true;
        }

        if (UI::Button("Accept detection as Manual")) {
            AcceptExternalDetectionAsManual();
        }
        UI::TextWrapped("Tip: enable export and use Manual selection while driving to collect more trusted samples.");
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
    UI::TextDisabled("Source: " + g_CurrentSource);
    if (g_CurrentRawValue.Length > 0) {
        UI::TextWrapped("Raw: " + g_CurrentRawValue);
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
    UI::TextDisabled("Collecting trusted labels only: Manual selection");
    UI::TextDisabled("Model inference: warm-start=6, conf>=60%, smoothing=2/3 (server)");
    UI::TextDisabled("Latest external detection: Plugins/vehicle-detector-dev/tools/results/latest_detection.json");
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

    // --- Per-wheel rendering ---
    // Each quadrant: colored circle (left) + material name (right) + wheel label (top)
    float circleR = Math::Min(halfW, halfH) * 0.30f;
    float labelFontSize = Math::Max(9.0f, S_SurfaceFontSize * 0.5f);
    float nameFontSize = S_SurfaceFontSize;

    // Wheel positions: FL, FR, RL, RR
    vec2 centers[4];
    centers[0] = vec2(x + halfW * 0.45f, y + halfH * 0.45f);       // FL
    centers[1] = vec2(x + halfW + halfW * 0.45f, y + halfH * 0.45f); // FR
    centers[2] = vec2(x + halfW * 0.45f, y + halfH + halfH * 0.45f); // RL
    centers[3] = vec2(x + halfW + halfW * 0.45f, y + halfH + halfH * 0.45f); // RR

    string labels[4] = {"FL", "FR", "RL", "RR"};
    CAudioSourceSurface::ESurfId mats[4];
    mats[0] = state.FLGroundContactMaterial;
    mats[1] = state.FRGroundContactMaterial;
    mats[2] = state.RLGroundContactMaterial;
    mats[3] = state.RRGroundContactMaterial;

    for (int i = 0; i < 4; i++) {
        vec2 c = centers[i];
        vec4 col = SurfaceMaterialColor(mats[i]);
        string matName = SurfaceMaterialName(mats[i]);

        // Colored circle with glow
        // Glow (larger, semi-transparent)
        nvg::BeginPath();
        nvg::Circle(c, circleR * 1.4f);
        nvg::FillColor(vec4(col.x, col.y, col.z, 0.15f));
        nvg::Fill();

        // Main circle
        nvg::BeginPath();
        nvg::Circle(c, circleR);
        nvg::FillColor(col);
        nvg::Fill();

        // Circle border
        nvg::StrokeWidth(1.5f);
        nvg::StrokeColor(vec4(1.0f, 1.0f, 1.0f, 0.3f));
        nvg::BeginPath();
        nvg::Circle(c, circleR);
        nvg::Stroke();

        // Wheel label (FL/FR/RL/RR) — top-left of quadrant
        nvg::BeginPath();
        nvg::FontSize(labelFontSize);
        nvg::FillColor(vec4(0.55f, 0.60f, 0.70f, 0.8f));
        nvg::TextAlign(nvg::Align::Top | nvg::Align::Left);
        nvg::TextBox(vec2(c.x - circleR, c.y - circleR - labelFontSize - 2), circleR * 2, labels[i]);

        // Material name — below circle, centered
        nvg::BeginPath();
        nvg::FontSize(nameFontSize);
        // Text color: white on dark surfaces, dark on bright surfaces
        float luma = col.x * 0.299f + col.y * 0.587f + col.z * 0.114f;
        if (luma > 0.6f) {
            nvg::FillColor(vec4(0.08f, 0.08f, 0.10f, 1.0f));
        } else {
            nvg::FillColor(vec4(0.92f, 0.94f, 0.98f, 1.0f));
        }
        nvg::TextAlign(nvg::Align::Top | nvg::Align::Center);
        nvg::TextBox(vec2(c.x - circleR - 4, c.y + circleR + 3), circleR * 2 + 8, matName);
    }
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