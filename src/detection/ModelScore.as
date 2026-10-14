// ============================================================================
// MP4 Vehicle Detector
// ============================================================================
// Live accuracy measurement for the server-side ML model.
//
// The detector already reads the authoritative answer from the game itself
// (Pursuit label -> ForceModelId -> SettingsPlayerModelId -> title ident).
// That answer is ground truth. So instead of quoting an offline classification
// report that goes stale the moment new data arrives, the plugin scores the
// model LIVE: every fresh prediction is compared against what the game says
// the player is actually driving.
//
// This answers the question the offline report cannot: "on the car I am
// driving right now, is the model right?"
//
// Openplanet compiles all .as files in this plugin directory together.
// ============================================================================

// Section: Model Accuracy Scoring
// ============================================================================

/**
 * True when the game readout is trustworthy enough to be used as ground truth.
 * "Map expectation" is excluded on purpose: it is a guess derived from the map
 * declaration, so scoring against it would measure nothing.
 */
bool IsGameReadoutAuthoritative() {
    if (g_CurrentVehicle == "Unknown" || g_CurrentVehicle.Length == 0) return false;
    if (g_CurrentSource == "Map expectation") return false;
    if (g_CurrentSource == "Telemetry 0-100") return false;
    if (g_CurrentSource == "No data") return false;
    if (g_CurrentSource == "This plugin targets MP4") return false;
    return true;
}

/**
 * Scores the current model prediction against the game readout.
 *
 * Called once per fresh prediction. A prediction is only counted when the game
 * readout is authoritative AND the model produced a named vehicle, so neither
 * "Unknown" nor a map-derived guess can inflate the accuracy figure.
 *
 * Each prediction is scored exactly once, keyed on the file's own timestamp —
 * re-reading the same unchanged file every second must not count again.
 */
void ScoreModelPrediction() {
    if (!S_ScoreModelAccuracy) return;

    // No fresh model result, nothing to score.
    if (g_ExternalDetectionStale || g_ExternalDetectedLabel.Length == 0) return;

    // Already scored this exact prediction.
    if (g_ModelLastScoredStamp == g_ExternalFileStamp) return;

    if (!IsGameReadoutAuthoritative()) {
        g_ModelLastVerdict = "Waiting for a confirmed game readout to score against.";
        // Remember the stamp anyway so we do not re-evaluate this same file
        // every second while we wait for a confirmed readout.
        g_ModelLastScoredStamp = g_ExternalFileStamp;
        return;
    }

    string modelNormalized = NormalizeToKnownVehicle(g_ExternalDetectedLabel);
    if (modelNormalized.Length == 0) {
        // The model named something outside the known list — record as wrong
        // rather than skipping it, because that is a real failure mode.
        g_ModelWrong += 1;
        g_ModelTotal += 1;
        g_ModelAgreeing = false;
        g_ModelStreak = g_ModelStreak > 0 ? -1 : g_ModelStreak - 1;
        g_ModelLastVerdict = "Model said \"" + g_ExternalDetectedLabel + "\", which is not a known vehicle.";
    } else if (modelNormalized == g_CurrentVehicle) {
        g_ModelCorrect += 1;
        g_ModelTotal += 1;
        g_ModelAgreeing = true;
        g_ModelStreak = g_ModelStreak >= 0 ? g_ModelStreak + 1 : 1;
        g_ModelLastVerdict = "Model agrees: " + ToPrettyVehicleName(modelNormalized) + ".";
    } else {
        g_ModelWrong += 1;
        g_ModelTotal += 1;
        g_ModelAgreeing = false;
        g_ModelStreak = g_ModelStreak > 0 ? -1 : g_ModelStreak - 1;
        g_ModelLastVerdict = "Model said " + ToPrettyVehicleName(modelNormalized)
            + ", you drive " + g_CurrentDisplayName + ".";
    }

    g_ModelLastScoredMs = Time::Now;
    g_ModelLastScoredStamp = g_ExternalFileStamp;
    g_ModelLastConfidence = g_ExternalDetectedConfidence;
}

/** Returns the live accuracy as a percentage, or -1 when too few samples exist. */
float GetModelLiveAccuracy() {
    if (g_ModelTotal <= 0) return -1.0f;
    return float(g_ModelCorrect) / float(g_ModelTotal) * 100.0f;
}

/**
 * Returns an honest one-word health verdict. Deliberately refuses to call the
 * model "good" until S_MinSamplesForVerdict real comparisons have accumulated,
 * because a handful of lucky frames is not evidence of a working model.
 */
string GetModelHealthVerdict() {
    if (!S_ScoreModelAccuracy) return "scoring off";
    if (g_ModelTotal < int64(S_MinSamplesForVerdict)) {
        return "not enough data (" + Text::Format("%d", int(g_ModelTotal)) + "/" + Text::Format("%d", int(S_MinSamplesForVerdict)) + ")";
    }

    float acc = GetModelLiveAccuracy();
    if (acc >= 90.0f) return "reliable (" + Text::Format("%.0f%%", acc) + ")";
    if (acc >= 70.0f) return "usable (" + Text::Format("%.0f%%", acc) + ")";
    if (acc >= 40.0f) return "unreliable (" + Text::Format("%.0f%%", acc) + ")";
    return "not usable (" + Text::Format("%.0f%%", acc) + ")";
}

/** Returns a per-vehicle accuracy breakdown line, or "" when nothing is known yet. */
string GetModelBreakdownLine() {
    if (g_ModelCorrect + g_ModelWrong == 0) return "";
    return "On " + g_CurrentDisplayName + ": "
        + Text::Format("%d", int(g_ModelCorrect)) + " right / "
        + Text::Format("%d", int(g_ModelWrong)) + " wrong";
}

/** Resets the live scoring counters (useful after a car switch or reload). */
void ResetModelScore() {
    g_ModelCorrect = 0;
    g_ModelWrong = 0;
    g_ModelTotal = 0;
    g_ModelStreak = 0;
    g_ModelAgreeing = false;
    g_ModelLastVerdict = "";
    g_ModelLastScoredMs = 0;
    g_ModelLastScoredStamp = -1;
    g_ModelLastConfidence = 0.0f;
}