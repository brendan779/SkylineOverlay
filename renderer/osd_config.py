# ─────────────────────────────────────────────
#  ArduPilot OSD Config  — edit this file only
# ─────────────────────────────────────────────

# ── Output video ─────────────────────────────
OUTPUT_WIDTH   = 3840
OUTPUT_HEIGHT  = 2160
OUTPUT_FPS     = 30
OUTPUT_FILE    = "osd_overlay.mov"

# ── Timing ───────────────────────────────────
TIME_OFFSET_SECONDS = 0.0

# ── Fields to display ────────────────────────
ENABLED_FIELDS = [
    "speed",
    "airspeed",
    "altitude",
    "attitude",
    "flight_mode",
    "messages",
]

# ── Lower-third layout ───────────────────────
LOWER_THIRD_HEIGHT_FRACTION = 0.12
LOWER_THIRD_MARGIN_PX       = 96

# ── Colours (R, G, B, A) — all 0.0–1.0 ──────
COLOR_BG          = (0.05, 0.05, 0.05, 0.85)
COLOR_LABEL       = (0.65, 0.65, 0.65, 1.0)
COLOR_VALUE       = (1.0,  1.0,  1.0,  1.0)
COLOR_ACCENT      = (0.69, 0.44, 0.63, 1.0)    # mauve
COLOR_MODE_BG     = (0.69, 0.44, 0.63, 0.85)   # mauve
COLOR_MODE_TEXT   = (1.0,  1.0,  1.0,  1.0)
COLOR_MESSAGE     = (1.0,  0.85, 0.35, 1.0)
COLOR_WARN        = (1.0,  0.4,  0.1,  1.0)

# ── Typography ───────────────────────────────
# Barlow Condensed is bundled (fonts/ folder). Falls back to DejaVu Sans Condensed.
FONT_FAMILY      = "Barlow Condensed"
FONT_LABEL_SIZE  = 11
FONT_VALUE_SIZE  = 22
FONT_MODE_SIZE   = 13
FONT_MSG_SIZE    = 12

# ── Attitude bar ─────────────────────────────
ATTITUDE_BAR_THICKNESS = 3
PITCH_RANGE_DEG        = 45
ROLL_RANGE_DEG         = 60

# ── Messages ─────────────────────────────────
MESSAGE_DISPLAY_SECONDS = 4.0
MESSAGE_MAX_CHARS       = 72

# ── Speed units ──────────────────────────────
# "kmh" | "mph" | "ms"
SPEED_UNITS = "kmh"

# ── Altitude datum ───────────────────────────
# "relative" = above home   "absolute" = AMSL
ALTITUDE_DATUM = "relative"

# ── Map overlay (top-right corner) ───────────
MAP_ENABLED       = True
MAP_SIZE_FRACTION = 0.22        # fraction of frame width (square)
MAP_MARGIN_PX     = 48          # margin from top-right corner

# How many metres the full map width represents (zoom level)
MAP_SPAN_M        = 600

# Metres of recent GPS track to draw on map
MAP_TRACK_WINDOW_M = 500

# Tile source: "osm" (no key) or "esri_satellite" (no key)
MAP_TILE_SOURCE   = "osm"

# Google Maps Static API key — leave blank to use OSM tiles.
# Get a key: https://console.cloud.google.com/ (Maps Static API)
# When set, Google Maps satellite imagery is used automatically.
GOOGLE_MAPS_API_KEY = ""

# Map appearance
MAP_BG_COLOR      = (0.05, 0.05, 0.05, 0.75)
MAP_BORDER_COLOR  = (0.69, 0.44, 0.63, 0.9)    # mauve
MAP_BORDER_WIDTH  = 2
MAP_TRACK_COLOR   = (0.69, 0.44, 0.63, 0.85)   # mauve
MAP_TRACK_WIDTH   = 2
MAP_DOT_COLOR     = (1.0,  1.0,  1.0,  1.0)
MAP_DOT_RADIUS    = 5
MAP_CORNER_RADIUS = 8


# ── Wind indicator ───────────────────────────
WIND_ENABLED       = True   # Show body-frame wind compass
WIND_MIN_SPEED_MS  = 0.5    # Hide arrow below this speed (EKF settling)
