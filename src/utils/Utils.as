// ============================================================================
// MP4 Vehicle Detector Clean
// ============================================================================
// Split module for Plugins/vehicle-detector. Openplanet compiles all .as files
// in this plugin directory together.
// ============================================================================

// Section: JSON Helpers
// ============================================================================

/** Escapes a string so it can be safely embedded in JSON. */
string JsonEscape(const string &in value) {
    string result = value;
    result = result.Replace("\\", "\\\\");
    result = result.Replace("\"", "\\\"");
    result = result.Replace("\n", " ");
    result = result.Replace("\r", " ");
    return result;
}


// Section: Telemetry Buffer Helpers
// ============================================================================

/** Clears the telemetry ring-buffer. */
void ResetTelemetry() {
    g_CurrentTelemetry.RemoveRange(0, g_CurrentTelemetry.Length);
}

/**
 * Appends a line to the telemetry buffer. Silently drops the line if
 * the buffer has reached its capacity of 64 entries.
 */
void AddTelemetryLine(const string &in line) {
    if (g_CurrentTelemetry.Length >= 64) return;
    g_CurrentTelemetry.InsertLast(line);
}


// ============================================================================
// Section: Utility
// ============================================================================

/** Formats an MwId as a zero-padded hex string (e.g. "0x00001234"). */
string FormatMwIdHex(MwId id) {
    if (id.Value == 0) return "0x00000000";
    if (id.Value == 0xFFFFFFFF) return "0xFFFFFFFF";
    return "0x" + Text::Format("%08x", id.Value);
}
