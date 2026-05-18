# ArduOverlay

Reads an ArduPilot `.bin` dataflash log and renders a **transparent ProRes 4444 `.mov`** OSD overlay video for compositing in DaVinci Resolve, Final Cut Pro, Premiere, and similar editors.

---

## Requirements

- Python 3
- ffmpeg

### Install Python dependencies

```bash
pip3 install pymavlink matplotlib numpy --break-system-packages
```

### Check ffmpeg

```bash
ffmpeg -version
```

If not installed: `brew install ffmpeg`

---

## Usage

### Basic

```bash
python3 ardupilot_osd.py myflight.bin
```

Outputs `osd_overlay.mov` in the current directory.

### Preview first 10 seconds

```bash
python3 ardupilot_osd.py myflight.bin --preview
```

### Custom output path

```bash
python3 ardupilot_osd.py myflight.bin --out /path/to/output.mov
```

### Sync offset

If the video and log started at different times:

```bash
# Telemetry starts 3.5 seconds after video starts:
python3 ardupilot_osd.py myflight.bin --offset 3.5

# Telemetry starts 2 seconds before video:
python3 ardupilot_osd.py myflight.bin --offset -2.0
```

### Override resolution or FPS

```bash
python3 ardupilot_osd.py myflight.bin --width 3840 --height 2160 --fps 60
```

### Inspect a log file

```bash
python3 ardupilot_osd.py myflight.bin --dump
```

Prints all message types found in the log and exits — useful for checking what data is available.

---

## Configuration

All settings live in `osd_config.py`. Edit that file to customise the output.

| Setting | Default | Description |
|---|---|---|
| `OUTPUT_WIDTH` | `1920` | Match your source footage width |
| `OUTPUT_HEIGHT` | `1080` | Match your source footage height |
| `OUTPUT_FPS` | `30` | Match your footage frame rate |
| `OUTPUT_FILE` | `osd_overlay.mov` | Output file path |
| `TIME_OFFSET_SECONDS` | `0.0` | Shift telemetry relative to video start |
| `ENABLED_FIELDS` | all | Comment out any field to hide it |
| `SPEED_UNITS` | `"kmh"` | `"kmh"`, `"mph"`, or `"ms"` |
| `ALTITUDE_DATUM` | `"relative"` | `"relative"` (above home) or `"absolute"` (AMSL) |
| `COLOR_*` | — | All colours as `(R, G, B, A)` tuples, values 0.0–1.0 |
| `FONT_*_SIZE` | — | Font sizes in points |
| `LOWER_THIRD_HEIGHT_FRACTION` | `0.18` | Panel height as a fraction of frame height |
| `LOWER_THIRD_MARGIN_PX` | `48` | Left/right/bottom margin in pixels |
| `MESSAGE_DISPLAY_SECONDS` | `4.0` | How long each status message stays visible |
| `MESSAGE_MAX_CHARS` | `72` | Truncate messages longer than this |
| `PITCH_RANGE_DEG` | `45` | Full-scale deflection for pitch bar |
| `ROLL_RANGE_DEG` | `60` | Full-scale deflection for roll bar |

### OSD fields

Enable or disable fields by editing `ENABLED_FIELDS` in `osd_config.py`:

```python
ENABLED_FIELDS = [
    "speed",        # GPS ground speed
    "altitude",     # relative or absolute altitude
    "attitude",     # pitch / roll / yaw bars
    "flight_mode",  # ArduPilot flight mode name
    "messages",     # STATUSTEXT log messages
]
```

---

## Compositing

The output is **ProRes 4444 with a real alpha channel** — no keying or colour removal needed.

### DaVinci Resolve
1. Import `osd_overlay.mov` into your Media Pool
2. Place it on a video track above your footage
3. Set composite mode to **Normal**

### Final Cut Pro
1. Drop `osd_overlay.mov` into your timeline above your clip
2. Blend mode: **Normal** (default)

### Premiere Pro
1. Place on **V2** (or any track above footage)
2. No keying needed — alpha is embedded

---

## Supported vehicles

- **Copter** — all frame types (default)
- **Plane** — fixed-wing and VTOL (auto-detected from mode numbers in log)
- **Rover** (auto-detected)

---

## Troubleshooting

**"No telemetry data found"**
Your `.bin` may be from a very old ArduPilot version or be corrupt. Run `--dump` to see what message types are present.

**Speed shows 0 the whole time**
GPS lock may have been lost. Check for `GPS` messages with `--dump`.

**Altitude looks wrong**
Try switching `ALTITUDE_DATUM` to `"absolute"` in `osd_config.py`, or verify that a home position was set before arming.

**Video and telemetry are out of sync**
Use `--offset` to shift the telemetry. Positive delays telemetry relative to video; negative advances it.
