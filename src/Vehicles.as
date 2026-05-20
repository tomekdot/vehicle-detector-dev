// ============================================================================
// MP4 Vehicle Detector
// ============================================================================
// Split module for Plugins/vehicle-detector. Openplanet compiles all .as files
// in this plugin directory together.
// ============================================================================

// Section: Text Processing Helpers
// ============================================================================

/**
 * Strips format codes, removes path prefixes (e.g. "ManiaPlanet:"),
 * and strips file extensions (.gbx, .webp, .dds) from raw vehicle text.
 * Returns the cleaned string or "" if the input was empty.
 */
string CleanupVehicleText(const string &in rawText) {
    string text = Text::StripFormatCodes(rawText);
    if (text.Length == 0) return "";

    // Strip path — keep only the segment after the last "/" or "\"
    int slashIx = text.LastIndexOf("/");
    int backslashIx = text.LastIndexOf("\\");
    int splitIx = slashIx > backslashIx ? slashIx : backslashIx;
    if (splitIx >= 0 && splitIx + 1 < int(text.Length)) {
        text = text.SubStr(splitIx + 1);
    }

    // Strip protocol prefixes
    string lower = text.ToLower();
    if (lower.StartsWith("trackmania:")) text = text.SubStr(11);
    else if (lower.StartsWith("maniaplanet:")) text = text.SubStr(12);

    // Strip common file extensions
    lower = text.ToLower();
    if (lower.EndsWith(".item.gbx")) text = text.SubStr(0, text.Length - 9);
    else if (lower.EndsWith(".gbx")) text = text.SubStr(0, text.Length - 4);
    else if (lower.EndsWith(".webp")) text = text.SubStr(0, text.Length - 5);
    else if (lower.EndsWith(".dds")) text = text.SubStr(0, text.Length - 4);

    return text;
}

/**
 * Normalizes a cleaned vehicle string against the known vehicle list.
 * Removes spaces, underscores, and hyphens before matching so that
 * variants like "Stadium Car", "stadium_car", "Stadium-Car" all match.
 * Returns the canonical key (e.g. "StadiumCar") or "" if no match.
 */
string NormalizeToKnownVehicle(const string &in rawText) {
    string key = rawText.ToLower();
    key = key.Replace(" ", "");
    key = key.Replace("_", "");
    key = key.Replace("-", "");

    // Each condition covers common aliases and the canonical name
    if (key.Contains("stadiumcar") || key == "stadium" || key.Contains("carsport")) return "StadiumCar";
    if (key.Contains("canyoncar") || key == "canyon") return "CanyonCar";
    if (key.Contains("valleycar") || key == "valley") return "ValleyCar";
    if (key.Contains("lagooncar") || key == "lagoon") return "LagoonCar";
    if (key.Contains("islandcar") || key == "island") return "IslandCar";
    if (key.Contains("baycar") || key == "bay") return "BayCar";
    if (key.Contains("coastcar") || key == "coast") return "CoastCar";
    if (key.Contains("desertcar") || key == "desert" || key.Contains("cardesert")) return "DesertCar";
    if (key.Contains("snowcar") || key == "snow" || key.Contains("carsnow")) return "SnowCar";
    if (key.Contains("rallycar") || key == "rally" || key.Contains("carrally")) return "RallyCar";
    if (key.Contains("trafficcar") || key == "traffic") return "TrafficCar";

    return "";
}

/** Converts a canonical vehicle key to a human-readable display name. */
string ToPrettyVehicleName(const string &in vehicle) {
    if (vehicle == "StadiumCar") return "Stadium Car";
    if (vehicle == "CanyonCar") return "Canyon Car";
    if (vehicle == "ValleyCar") return "Valley Car";
    if (vehicle == "LagoonCar") return "Lagoon Car";
    if (vehicle == "IslandCar") return "Island Car";
    if (vehicle == "BayCar") return "Bay Car";
    if (vehicle == "CoastCar") return "Coast Car";
    if (vehicle == "DesertCar") return "Desert Car";
    if (vehicle == "SnowCar") return "Snow Car";
    if (vehicle == "RallyCar") return "Rally Car";
    if (vehicle == "TrafficCar") return "Traffic Car";
    return vehicle;
}


// ============================================================================
// Section: Vehicle Texture
// ============================================================================

/**
 * Returns a cached vehicle thumbnail texture, or loads it on first access.
 * Returns null if no texture path exists for the given vehicle key.
 */
UI::Texture@ GetVehicleTexture(const string &in vehicle) {
    string path = GetVehicleTexturePath(vehicle);
    if (path.Length == 0) return null;

    // Cache hit — same path, already loaded
    if (path == g_LastTexturePath && g_LastTexture !is null) {
        return g_LastTexture;
    }

    // Cache miss — load and remember
    g_LastTexturePath = path;
    @g_LastTexture = UI::LoadTexture(path);
    return g_LastTexture;
}

/** Maps a canonical vehicle key to its thumbnail path inside the game assets. */
string GetVehicleTexturePath(const string &in vehicle) {
    if (vehicle == "CanyonCar") return "Media/MEDIABROWSER_HiddenResources/Common/Images/Editors/Vehicle/CanyonCar.webp";
    if (vehicle == "StadiumCar") return "Media/MEDIABROWSER_HiddenResources/Common/Images/Editors/Vehicle/StadiumCar.webp";
    if (vehicle == "ValleyCar") return "Media/MEDIABROWSER_HiddenResources/Common/Images/Editors/Vehicle/ValleyCar.webp";
    if (vehicle == "LagoonCar") return "Media/MEDIABROWSER_HiddenResources/Common/Images/Editors/Vehicle/LagoonCar.webp";
    if (vehicle == "IslandCar") return "Media/MEDIABROWSER_HiddenResources/Common/Images/Editors/Vehicle/IslandCar.webp";
    if (vehicle == "BayCar") return "Media/MEDIABROWSER_HiddenResources/Common/Images/Editors/Vehicle/BayCar.webp";
    if (vehicle == "CoastCar") return "Media/MEDIABROWSER_HiddenResources/Common/Images/Editors/Vehicle/CoastCar.webp";
    if (vehicle == "DesertCar") return "Media/MEDIABROWSER_HiddenResources/Common/Images/Editors/Vehicle/DesertCar.webp";
    if (vehicle == "SnowCar") return "Media/MEDIABROWSER_HiddenResources/Common/Images/Editors/Vehicle/SnowCar.webp";
    if (vehicle == "RallyCar") return "Media/MEDIABROWSER_HiddenResources/Common/Images/Editors/Vehicle/RallyCar.webp";
    if (vehicle == "TrafficCar") return "Media/MEDIABROWSER_HiddenResources/Common/Images/Editors/Vehicle/TrafficCar.webp";
    return "";
}

