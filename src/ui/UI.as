// ============================================================================
// MP4 Vehicle Detector
// ============================================================================
// Split module for Plugins/vehicle-detector. Openplanet compiles all .as files
// in this plugin directory together.
// ============================================================================

// Section: UI — Menu & Render
// ============================================================================

/** Adds a toggle item to the Openplanet overlay menu. */
void RenderMenu() {
    if (UI::MenuItem(Icons::Car + " Vehicle Detector", "", S_ShowWindow)) {
        S_ShowWindow = !S_ShowWindow;
    }
    if (UI::MenuItem(Icons::Eye + " Show HUD Overlay", "", S_ShowHudOverlay)) {
        S_ShowHudOverlay = !S_ShowHudOverlay;
    }
}

/** Draws a compact always-visible HUD with vehicle and training status. */
void RenderHudOverlay() {
#if !MP4
    return;
#else
    if (!S_ShowHudOverlay) return;

    const uint flags =
        UI::WindowFlags::NoSavedSettings |
        UI::WindowFlags::NoCollapse;

    UI::SetNextWindowSize(120, 0, UI::Cond::FirstUseEver);

    if (UI::Begin(Icons::Car + " Vehicle HUD", flags)) {
        if (!g_TrainingCaptureArmed) {
            if (UI::Button("Start training")) {
                StartTrainingSession();
            }
        } else if (g_TrainingCapturePaused) {
            if (UI::Button("Resume training")) {
                ResumeTrainingSession();
            }
            UI::SameLine();
            if (UI::Button("Stop")) {
                StopTrainingSession();
            }
        } else {
            if (UI::Button("Pause training")) {
                PauseTrainingSession();
            }
            UI::SameLine();
            if (UI::Button("Stop")) {
                StopTrainingSession();
            }
        }

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

        if (g_SelectedTrainingVehicle.Length > 0) {
            UI::TextDisabled("Label: " + ToPrettyVehicleName(g_SelectedTrainingVehicle));
        } else if (g_TrainingLockedVehicle.Length > 0) {
            UI::TextDisabled("Label: " + ToPrettyVehicleName(g_TrainingLockedVehicle) + " (locked)");
        } else {
            UI::TextDisabled("Label: Auto (Detection)");
        }

        if (g_TrainingLockedVehicle.Length > 0 && g_CurrentVehicle != g_TrainingLockedVehicle) {
            UI::TextDisabled("Vehicle changed in game; training label stays locked.");
        }

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
    }
    UI::End();
#endif
}

/** Draws the main plugin window. On non-MP4 builds shows a warning instead. */
void Render() {
#if !MP4
    // --- Non-MP4: show incompatibility notice ---
    if (!S_ShowWindow) return;
    if (UI::Begin(Icons::Car + " Vehicle Detector", S_ShowWindow)) {
        UI::Text("This plugin is designed for ManiaPlanet 4.");
    }
    UI::End();
    return;
#else
    // --- MP4: full UI ---
    RenderHudOverlay();
    if (!S_ShowWindow) return;

    UI::SetNextWindowSize(500, 420, UI::Cond::FirstUseEver);
    if (!UI::Begin(Icons::Car + " Vehicle Detector", S_ShowWindow)) {
        UI::End();
        return;
    }

    // Current vehicle info
    UI::Text("Current vehicle:");
    UI::Separator();
    UI::Text(g_CurrentDisplayName);
    UI::TextDisabled("Code: " + g_CurrentVehicle);
    UI::TextDisabled("Source: " + g_CurrentSource);
    if (g_CurrentRawValue.Length > 0) {
        UI::TextWrapped("Raw: " + g_CurrentRawValue);
    }

    // Vehicle thumbnail
    UI::Separator();
    UI::Texture@ tex = GetVehicleTexture(g_CurrentVehicle);
    if (tex !is null) {
        UI::Image(tex, vec2(220, 120));
        string texPath = GetVehicleTexturePath(g_CurrentVehicle);
        if (texPath.Length > 0) UI::TextDisabled("Texture: " + texPath);
    } else {
        UI::TextDisabled("No thumbnail available for this entry.");
    }

    // Live VehicleState telemetry
    auto state = VehicleState::ViewingPlayerState();
    if (state !is null) {
        UI::Separator();
        UI::Text("VehicleState:");
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
    }

    // 0-100 km/h timing section
    UI::Separator();
    UI::Text("0-100 km/h:");
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

    UI::Separator();
    UI::Text("Training / Telemetry:");
    UI::TextDisabled("Collecting trusted labels only: AsyncModelName, Manialink, Manual selection");
    UI::TextDisabled("Training mode: " + (S_ContinuousTrainingCapture ? "Continuous segments" : "Impact-triggered captures"));
    UI::TextDisabled("Samples streamed to 127.0.0.1:" + S_TrainingExportPort);
    UI::Text("Current training run: #" + Text::Format("%d", g_TrainingRunId));
    UI::Text("Network export status: " + (S_EnableTrainingExport ? "Enabled" : "Disabled"));
    if (!g_TrainingCaptureArmed) {
        if (UI::Button("Start training##main")) {
            StartTrainingSession();
        }
    } else if (g_TrainingCapturePaused) {
        if (UI::Button("Resume training##main")) {
            ResumeTrainingSession();
        }
        UI::SameLine();
        if (UI::Button("Stop training##main")) {
            StopTrainingSession();
        }
    } else {
        if (UI::Button("Pause training##main")) {
            PauseTrainingSession();
        }
        UI::SameLine();
        if (UI::Button("Stop training##main")) {
            StopTrainingSession();
        }
    }
    UI::TextDisabled("State: " + (g_TrainingCaptureArmed ? (g_TrainingCapturePaused ? "Paused" : "Running") : "Stopped"));
    if (g_TrainingCaptureActive) {
        float elapsedSec = float(Time::Now - g_TrainingCaptureStartMs) / 1000.0f;
        UI::Text("Current motion: " + g_TrainingMotionLabel);
        UI::Text("Segment time: " + Text::Format("%.2f s", elapsedSec));
    } else {
        UI::TextDisabled("Training capture waiting for vehicle state.");
    }

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
    if (g_SelectedTrainingVehicle.Length > 0) {
        UI::Text("Active selection: " + ToPrettyVehicleName(g_SelectedTrainingVehicle) + " (#" + tostring(g_SelectedTrainingVehicleIndex) + ")");
    } else if (g_TrainingLockedVehicle.Length > 0) {
        UI::Text("Active selection: " + ToPrettyVehicleName(g_TrainingLockedVehicle) + " (locked)");
    } else {
        UI::Text("Active selection: Auto (Detection)");
    }
    UI::Text("Telemetry capture status: " + (g_TrainingCaptureActive ? "Active" : "Inactive"));

    // Supported vehicles list
    UI::Separator();
    UI::Text("Supported Vehicles (" + tostring(TRAINING_SUPPORTED_VEHICLE_COUNT) + "):");
    UI::Text("- StadiumCar");
    UI::Text("- CanyonCar");
    UI::Text("- ValleyCar");
    UI::Text("- LagoonCar");
    UI::Text("- IslandCar");
    UI::Text("- BayCar");
    UI::Text("- CoastCar");
    UI::Text("- DesertCar");
    UI::Text("- SnowCar");
    UI::Text("- RallyCar");
    UI::Text("- TrafficCar");

    // Collapsible telemetry / debug panel
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

