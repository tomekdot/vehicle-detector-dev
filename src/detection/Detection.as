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
    g_CurrentTrust = "";
    g_CurrentRawValue = "";
    return;
#else
    auto app = cast<CTrackMania>(GetApp());
    if (app is null || app.CurrentPlayground is null) {
        SetCurrentVehicle("Unknown", "Unknown", "No playground", "", "");
        return;
    }

    auto player = VehicleState::GetViewingPlayer();
    string vehicle;
    string displayName;
    string source;
    string rawValue;
    string trust;

    DetectVehicle(app, player, vehicle, displayName, source, rawValue, trust);
    UpdateAccelerationTelemetry();

    string finalVehicle = vehicle;
    string finalDisplayName = displayName;
    string finalSource = source;
    string finalRawValue = rawValue;
    bool didOverride = false;
    ApplyTelemetryFallback(vehicle, displayName, source, rawValue, finalVehicle, finalDisplayName, finalSource, finalRawValue, didOverride);
    if (didOverride) trust = "measured 0-100";

    SetCurrentVehicle(finalVehicle, finalDisplayName, finalSource, finalRawValue, trust);
#endif
}

/**
 * Writes new vehicle data into globals, updates the timestamp, and logs
 * the change if S_LogVehicleChanges is enabled and the vehicle actually
 * changed. Also dumps the full telemetry buffer when S_LogDetectionDetails.
 * `trust` classifies how far the source can be believed and is shown in the UI.
 */
void SetCurrentVehicle(const string &in vehicle, const string &in displayName, const string &in source, const string &in rawValue, const string &in trust) {
    g_CurrentVehicle = vehicle;
    g_CurrentDisplayName = displayName;
    g_CurrentSource = source;
    g_CurrentTrust = trust;
    g_CurrentRawValue = rawValue;
    g_LastTelemetryUpdate = Time::Now;

    // Log vehicle transitions (e.g. "StadiumCar -> CanyonCar (Pursuit label)")
    if (S_LogVehicleChanges && g_CurrentVehicle != g_LastLoggedVehicle) {
        print("[MP4 Vehicle Detector] " + g_LastLoggedVehicle + " -> " + g_CurrentVehicle + " (" + g_CurrentSource + ")");
        g_LastLoggedVehicle = g_CurrentVehicle;

        // Model accuracy is per-car: predictions scored against a different
        // ground truth are not comparable, so the running tally starts fresh.
        ResetModelScore();
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
 * Main detection pipeline. Tries sources in strict trust order — strongest
 * evidence first, and never guesses from a map name:
 *   1. Pursuit Manialink label   — the server tells the client which model
 *   2. ForceModelId               — per-player model forced by the server
 *   3. SettingsPlayerModelId      — model forced by the script API
 *   4. Titlepack VehicleIdentId   — title-wide vehicle (CarSelector/Unlock)
 *   5. Map VehicleName            — what the map *expects* (weakest, and
 *                                   explicitly labelled as an expectation)
 *
 * The map name is deliberately NOT a source: on ManiaPlanet the map title
 * ("...Lagoon...") has nothing to do with the car being driven, and guessing
 * from it produced confidently wrong answers. If every real source fails the
 * result is "Unknown" plus the map expectation, not a fabricated car.
 */
void DetectVehicle(CTrackMania@ app, CGamePlayer@ player, string &out vehicle, string &out displayName, string &out source, string &out rawValue, string &out trust) {
    vehicle = "Unknown";
    displayName = "Unknown";
    source = "No data";
    rawValue = "";
    trust = "";
    ResetTelemetry();

    AddTelemetryLine("Detector start");
    AddTelemetryLine("Current playground: OK");
    AddTelemetryLine("Viewing player available: " + (player is null ? "no" : "yes"));

    // --- Map expectation (context for the UI, never used as the answer) ---
    g_MapVehicle = "";
    if (app.RootMap !is null) {
        string mapVehicle = app.RootMap.VehicleName.GetName();
        if (mapVehicle != "" && mapVehicle != "Unassigned") {
            g_MapVehicle = mapVehicle;
            AddTelemetryLine("Map expects: " + mapVehicle + " (" + app.RootMap.VehicleAuthor.GetName() + ")");
        } else {
            AddTelemetryLine("Map vehicle: unassigned");
        }
    }

    // --- Source 1: Pursuit/server Manialink label (strongest per-player signal)
    string candidate = ScanUiForVehicle(app);
    AddTelemetryLine("Manialink raw: " + (candidate.Length > 0 ? candidate : "<empty>"));
    if (TryResolveVehicle(candidate, "Pursuit label", vehicle, displayName, source, rawValue, trust)) return;

    // --- Source 2: ForceModelId (server-forced model for this player)
    auto tmPlayer = cast<CTrackManiaPlayer>(player);
    if (tmPlayer !is null && tmPlayer.ScriptAPI !is null) {
        auto scriptPlayer = cast<CTmRaceRulesPlayer>(tmPlayer.ScriptAPI);
        if (scriptPlayer !is null) {
            MwId forceId = scriptPlayer.ForceModelId;
            AddTelemetryLine("ForceModelId: " + FormatMwIdHex(forceId));
            if (forceId.Value != 0 && forceId.Value != 0xFFFFFFFF) {
                string resolvedForce = ResolveMwIdToVehicle(forceId);
                if (resolvedForce.Length > 0) {
                    vehicle = resolvedForce;
                    displayName = ToPrettyVehicleName(resolvedForce);
                    source = "ForceModelId";
                    rawValue = FormatMwIdHex(forceId);
                    trust = "confirmed";
                    AddTelemetryLine("Resolved via ForceModelId registry");
                    return;
                }
                // A forced id we cannot name is still real evidence — show the
                // hex rather than silently degrading to "Unknown".
                vehicle = "Unknown";
                displayName = "Unrecognised forced model";
                source = "ForceModelId";
                rawValue = "0x" + Text::Format("%08x", forceId.Value);
                trust = "forced, not in registry";
                AddTelemetryLine("ForceModelId present but not in the known registry");
                return;
            }
        }
    }

    // --- Source 3: SettingsPlayerModelId (script-API forced model) ---
    if (app.Network !is null && app.Network.PlaygroundClientScriptAPI !is null) {
        auto pgApi = app.Network.PlaygroundClientScriptAPI;
        MwId settingsId = pgApi.SettingsPlayerModelId;
        if (settingsId.Value != 0 && settingsId.Value != 0xFFFFFFFF) {
            AddTelemetryLine("SettingsPlayerModelId: " + FormatMwIdHex(settingsId));
            string resolvedSettings = ResolveMwIdToVehicle(settingsId);
            if (resolvedSettings.Length > 0) {
                vehicle = resolvedSettings;
                displayName = ToPrettyVehicleName(resolvedSettings);
                source = "SettingsPlayerModelId";
                rawValue = FormatMwIdHex(settingsId);
                trust = "confirmed";
                AddTelemetryLine("Resolved via SettingsPlayerModelId registry");
                return;
            }
        }
    }

    // --- Source 4: Titlepack vehicle ident (title-wide force) ---
    auto title = app.LoadedManiaTitle;
    if (title !is null) {
        string ident = title.VehicleIdentId.GetName();
        if (ident != "" && ident != "Unassigned") {
            string normalizedIdent = NormalizeToKnownVehicle(ident);
            vehicle = normalizedIdent.Length > 0 ? normalizedIdent : ident;
            displayName = ToPrettyVehicleName(vehicle);
            source = "Titlepack ident";
            rawValue = ident;
            trust = "title-wide";
            AddTelemetryLine("Resolved via titlepack VehicleIdentId");
            return;
        }
    }

    // --- Source 5: map expectation, explicitly labelled as a guess ---
    if (g_MapVehicle.Length > 0) {
        string normalizedMap = NormalizeToKnownVehicle(g_MapVehicle);
        vehicle = normalizedMap.Length > 0 ? normalizedMap : g_MapVehicle;
        displayName = ToPrettyVehicleName(vehicle);
        source = "Map expectation";
        rawValue = "not forced; map expects " + g_MapVehicle;
        trust = "guess - not forced";
        AddTelemetryLine("No forced model found; falling back to map expectation");
        return;
    }

    // --- Nothing identified ---
    AddTelemetryLine("Final fallback: Unknown");
}

/**
 * Resolves an MwId (ForceModelId / SettingsPlayerModelId) to a canonical
 * vehicle key without a server. MwId is a name hash, so SetName() on each
 * known spelling rebuilds the exact registry the ManiaScript side would
 * otherwise need a server for. Tries GetName() first, then hash compare.
 *
 * The hash match is checked across BOTH the internal code name and its alias
 * (SpeedCar<->DesertCar, AlpineCar<->SnowCar are the same car), so a title
 * forced with either spelling resolves to one canonical key. Returns ""
 * when the id is empty, unassigned, or matches no known vehicle.
 */
string ResolveMwIdToVehicle(MwId id) {
    if (id.Value == 0 || id.Value == 0xFFFFFFFF) return "";
    string viaName = NormalizeToKnownVehicle(CleanupVehicleText(id.GetName()));
    if (viaName.Length > 0) return viaName;

    // Both canonical codes and their alias spellings — the registry hashes
    // whichever one the titlepack actually used.
    const array<string> spellings = {
        "StadiumCar", "CanyonCar", "ValleyCar", "LagoonCar", "IslandCar",
        "BayCar", "CoastCar", "RallyCar", "TrafficCar",
        "DesertCar", "SpeedCar", "SnowCar", "AlpineCar"
    };
    for (uint i = 0; i < spellings.Length; i++) {
        MwId cand;
        cand.SetName(spellings[i]);
        if (cand.Value == id.Value) return NormalizeToKnownVehicle(spellings[i]);
    }
    return "";
}

/**
 * Attempts to resolve a raw candidate string into a known vehicle.
 * First cleans up the text, then normalizes against the known list.
 *
 * Returns true ONLY for a recognised vehicle. An unrecognised but non-empty
 * string is recorded as a raw-only note and returns false, so the caller keeps
 * walking down its source chain instead of stopping at a name it cannot map.
 * (Returning true here previously short-circuited every later source.)
 */
bool TryResolveVehicle(const string &in candidate, const string &in sourceName, string &out vehicle, string &out displayName, string &out source, string &out rawValue, string &out trust) {
    string cleaned = CleanupVehicleText(candidate);
    AddTelemetryLine(sourceName + " cleaned: " + (cleaned.Length > 0 ? cleaned : "<empty>"));
    if (cleaned.Length == 0) return false;

    string normalized = NormalizeToKnownVehicle(cleaned);
    AddTelemetryLine(sourceName + " normalized: " + (normalized.Length > 0 ? normalized : "<no-match>"));

    if (normalized.Length == 0) {
        AddTelemetryLine(sourceName + " value is not a known vehicle; continuing to next source");
        return false;
    }

    vehicle = normalized;
    displayName = ToPrettyVehicleName(normalized);
    source = sourceName;
    rawValue = cleaned;
    trust = "confirmed";
    AddTelemetryLine("Resolved vehicle: " + normalized + " via " + sourceName);
    return true;
}

/**
 * Walks all visible Manialink UI layers and scans their frames for labels
 * that contain a known vehicle name or have a "vehicle"-related
 * ControlId. Returns the label's raw Value on first match.
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
