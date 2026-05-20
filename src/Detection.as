// ============================================================================
// MP4 Vehicle Detector
// ============================================================================
// Split module for Plugins/vehicle-detector. Openplanet compiles all .as files
// in this plugin directory together.
// ============================================================================

// Section: Detection — Main Update Loop
// ============================================================================

/**
 * Called every frame. On non-MP4 builds, short-circuits. On MP4, runs the
 * full detection pipeline: DetectVehicle → UpdateAccelerationTelemetry →
 * ApplyTelemetryFallback → SetCurrentVehicle.
 */
void UpdateDetector() {
#if !MP4
    g_CurrentVehicle = "Unsupported";
    g_CurrentDisplayName = "Unsupported";
    g_CurrentSource = "This plugin targets MP4";
    g_CurrentRawValue = "";
    return;
#else
    auto app = cast<CTrackMania>(GetApp());
    if (app is null || app.CurrentPlayground is null) {
        SetCurrentVehicle("Unknown", "Unknown", "No playground", "");
        return;
    }

    auto player = VehicleState::GetViewingPlayer();
    string vehicle;
    string displayName;
    string source;
    string rawValue;

    DetectVehicle(app, player, vehicle, displayName, source, rawValue);
    UpdateAccelerationTelemetry();

    string finalVehicle = vehicle;
    string finalDisplayName = displayName;
    string finalSource = source;
    string finalRawValue = rawValue;
    bool didOverride = false;
    ApplyTelemetryFallback(vehicle, displayName, source, rawValue, finalVehicle, finalDisplayName, finalSource, finalRawValue, didOverride);

    SetCurrentVehicle(finalVehicle, finalDisplayName, finalSource, finalRawValue);
#endif
}

/**
 * Writes new vehicle data into globals, updates the timestamp, and logs
 * the change if S_LogVehicleChanges is enabled and the vehicle actually
 * changed. Also dumps the full telemetry buffer when S_LogDetectionDetails.
 */
void SetCurrentVehicle(const string &in vehicle, const string &in displayName, const string &in source, const string &in rawValue) {
    g_CurrentVehicle = vehicle;
    g_CurrentDisplayName = displayName;
    g_CurrentSource = source;
    g_CurrentRawValue = rawValue;
    g_LastTelemetryUpdate = Time::Now;

    // Log vehicle transitions (e.g. "StadiumCar -> CanyonCar (AsyncModelName)")
    if (S_LogVehicleChanges && g_CurrentVehicle != g_LastLoggedVehicle) {
        print("[MP4 Vehicle Detector] " + g_LastLoggedVehicle + " -> " + g_CurrentVehicle + " (" + g_CurrentSource + ")");
        g_LastLoggedVehicle = g_CurrentVehicle;
    }

    // Verbose debug: dump entire telemetry buffer to console
    if (S_LogDetectionDetails) {
        for (uint i = 0; i < g_CurrentTelemetry.Length; i++) {
            print("[MP4 Vehicle Detector Debug] " + g_CurrentTelemetry[i]);
        }
    }
}


// ============================================================================
// Section: Detection — MP4 Vehicle Identification
// ============================================================================

#if MP4

/**
 * Main detection pipeline. Tries multiple sources in priority order:
 *   1. AsyncModelName  — read via reflection from the player object
 *   2. Manialink scan  — walks UI layers looking for vehicle labels
 *   3. RootMap.CollectionName + "Car" — map collection fallback
 *   4. ForceModelId    — last-resort hex ID from script API
 * Each source is tried via TryResolveVehicle which normalizes the raw
 * text against the known vehicle list. If nothing matches, the function
 * falls through to "Unknown".
 */
void DetectVehicle(CTrackMania@ app, CGamePlayer@ player, string &out vehicle, string &out displayName, string &out source, string &out rawValue) {
    vehicle = "Unknown";
    displayName = "Unknown";
    source = "No data";
    rawValue = "";
    ResetTelemetry();

    AddTelemetryLine("Detector start");
    AddTelemetryLine("Current playground: OK");
    AddTelemetryLine("Viewing player available: " + (player is null ? "no" : "yes"));

    // --- Source 1: AsyncModelName via reflection ---
    string candidate = ReadPlayerStringMember(player, "AsyncModelName");
    AddTelemetryLine("AsyncModelName raw: " + (candidate.Length > 0 ? candidate : "<empty>"));
    if (TryResolveVehicle(candidate, "AsyncModelName", vehicle, displayName, source, rawValue)) return;

    // --- Source 2: Scan Manialink UI layers ---
    candidate = ScanUiForVehicle(app);
    AddTelemetryLine("Manialink raw: " + (candidate.Length > 0 ? candidate : "<empty>"));
    if (TryResolveVehicle(candidate, "Manialink", vehicle, displayName, source, rawValue)) return;

    // --- Source 3: RootMap collection name ---
    if (app.RootMap !is null) {
        candidate = app.RootMap.CollectionName + "Car";
        AddTelemetryLine("RootMap.CollectionName raw: " + app.RootMap.CollectionName);
        if (TryResolveVehicle(candidate, "RootMap.CollectionName", vehicle, displayName, source, rawValue)) return;
    }

    // --- Source 4 (supplementary): SettingsPlayerModelId ---
    auto pgApi = app.Network !is null ? app.Network.PlaygroundClientScriptAPI : null;
    if (pgApi !is null) {
        AddTelemetryLine("SettingsPlayerModelId: " + FormatMwIdHex(pgApi.SettingsPlayerModelId));
    }

    // --- Source 5: ForceModelId from CTrackManiaPlayer ---
    auto tmPlayer = cast<CTrackManiaPlayer>(player);
    if (tmPlayer !is null) {
        auto scriptPlayer = cast<CTmRaceRulesPlayer>(tmPlayer.ScriptAPI);
        if (scriptPlayer !is null) {
            MwId forceId = scriptPlayer.ForceModelId;
            AddTelemetryLine("ForceModelId: " + FormatMwIdHex(forceId));
            if (forceId.Value != 0 && forceId.Value != 0xFFFFFFFF) {
                vehicle = "Unknown";
                displayName = "Unknown ForceModelId";
                source = "ForceModelId";
                rawValue = "0x" + Text::Format("%08x", forceId.Value);
                AddTelemetryLine("Resolved via ForceModelId fallback");
                return;
            }
        }
    }

    // --- Diagnostic: dump VehicleState if available ---
    auto state = VehicleState::ViewingPlayerState();
    if (state !is null) {
        AddTelemetryLine("VehicleState speed: " + Text::Format("%.1f km/h", state.FrontSpeed * 3.6f));
        AddTelemetryLine("VehicleState gear: " + Text::Format("%d", state.CurGear));
        AddTelemetryLine("VehicleState gas: " + Text::Format("%.2f", state.InputGasPedal));
        AddTelemetryLine("VehicleState braking: " + (state.InputIsBraking ? "true" : "false"));
        AddTelemetryLine("VehicleState ground: " + (state.IsGroundContact ? "true" : "false"));
    } else {
        AddTelemetryLine("VehicleState: <null>");
    }

    AddTelemetryLine("Final fallback: Unknown");
}

/**
 * Reads a string member from a CGamePlayer using reflection.
 * Returns "" if the player is null, the type can't be resolved,
 * the member doesn't exist, or the offset is invalid (0xFFFF).
 */
string ReadPlayerStringMember(CGamePlayer@ player, const string &in memberName) {
    if (player is null) return "";

    auto type = Reflection::TypeOf(player);
    if (type is null) return "";

    auto member = type.GetMember(memberName);
    if (member is null || member.Offset == 0xFFFF) return "";

    return Dev::GetOffsetString(player, member.Offset);
}

/**
 * Attempts to resolve a raw candidate string into a known vehicle.
 * First cleans up the text, then normalizes against the known list.
 * If normalization succeeds → known vehicle. If the cleaned text is
 * non-empty but doesn't match → stored as "raw-only" result.
 * Returns true if a resolution was made (known or raw-only).
 */
bool TryResolveVehicle(const string &in candidate, const string &in sourceName, string &out vehicle, string &out displayName, string &out source, string &out rawValue) {
    string cleaned = CleanupVehicleText(candidate);
    AddTelemetryLine(sourceName + " cleaned: " + (cleaned.Length > 0 ? cleaned : "<empty>"));
    if (cleaned.Length == 0) return false;

    string normalized = NormalizeToKnownVehicle(cleaned);
    AddTelemetryLine(sourceName + " normalized: " + (normalized.Length > 0 ? normalized : "<no-match>"));

    if (normalized.Length > 0) {
        // Known vehicle match
        vehicle = normalized;
        displayName = ToPrettyVehicleName(normalized);
        source = sourceName;
        rawValue = cleaned;
        AddTelemetryLine("Resolved vehicle: " + normalized + " via " + sourceName);
        return true;
    }

    // Unrecognized but non-empty — store as raw-only for transparency
    vehicle = "Unknown";
    displayName = cleaned;
    source = sourceName + " (raw)";
    rawValue = cleaned;
    AddTelemetryLine("Resolved raw-only candidate via " + sourceName);
    return true;
}

/**
 * Walks all visible Manialink UI layers and scans their frames for
 * vehicle-related labels. Returns the first matching label value,
 * or "" if nothing was found.
 */
string ScanUiForVehicle(CTrackMania@ app) {
    if (!S_ScanManialinkLabels) return "";
    if (app is null || app.Network is null || app.Network.PlaygroundClientScriptAPI is null) return "";

    auto ui = app.Network.PlaygroundClientScriptAPI.UI;
    if (ui is null) return "";

    for (uint i = 0; i < ui.UILayers.Length; i++) {
        auto layer = ui.UILayers[i];
        if (!layer.IsVisible || layer.LocalPage is null || layer.LocalPage.MainFrame is null) continue;

        string found = ScanFrameForVehicle(layer.LocalPage.MainFrame);
        if (found.Length > 0) return found;
    }
    return "";
}

/**
 * Recursively scans a Manialink frame and its children for labels
 * that contain a known vehicle name or have a "vehicle"-related
 * ControlId. Returns the label's raw Value on first match.
 */
string ScanFrameForVehicle(CGameManialinkFrame@ frame) {
    if (frame is null) return "";

    for (uint i = 0; i < frame.Controls.Length; i++) {
        auto control = frame.Controls[i];

        // Check if the control is a label with vehicle info
        auto label = cast<CGameManialinkLabel>(control);
        if (label !is null) {
            string cleaned = CleanupVehicleText(string(label.Value));
            if (NormalizeToKnownVehicle(cleaned).Length > 0) {
                return string(label.Value);
            }

            // Fallback: label whose ControlId contains "vehicle"
            string controlId = string(control.ControlId).ToLower();
            if (controlId.Contains("vehicle") && cleaned.Length > 0) {
                return string(label.Value);
            }
        }

        // Recurse into child frames
        auto child = cast<CGameManialinkFrame>(control);
        if (child !is null) {
            string nested = ScanFrameForVehicle(child);
            if (nested.Length > 0) return nested;
        }
    }

    return "";
}

#endif

