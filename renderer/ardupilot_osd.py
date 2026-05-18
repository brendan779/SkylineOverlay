#!/usr/bin/env python3
"""
ardupilot_osd.py
────────────────
Reads an ArduPilot .bin dataflash log and renders a transparent
ProRes 4444 (.mov) OSD overlay video for compositing in DaVinci Resolve,
Final Cut Pro, Premiere, etc.

Usage:
    python3 ardupilot_osd.py <logfile.bin> [options]

Options:
    --config   Path to config file   (default: osd_config.py in same dir)
    --out      Override output path  (default: from config)
    --offset   Time offset seconds   (default: from config)
    --fps      Override output FPS   (default: from config)
    --width    Override width px     (default: from config)
    --height   Override height px    (default: from config)
    --preview  Render first 10s only (for quick checks)
    --dump     Print all message types found in the log and exit
"""

import sys
import os
import argparse
import math
import subprocess
import multiprocessing
import time
from pathlib import Path

# ── Dependency check ─────────────────────────────────────────────────────────
def _check_deps():
    missing = []
    try:
        from PIL import Image
    except ImportError:
        missing.append("Pillow")
    try:
        from pymavlink import mavutil
    except ImportError:
        missing.append("pymavlink")
    try:
        import numpy
    except ImportError:
        missing.append("numpy")
    if missing:
        print(f"[ERROR] Missing packages: {', '.join(missing)}")
        print(f"        Run: pip3 install {' '.join(missing)} --break-system-packages")
        sys.exit(1)
    try:
        subprocess.run(["ffmpeg", "-version"], capture_output=True, check=True)
    except FileNotFoundError:
        print("[ERROR] ffmpeg not found.")
        print("        Install with: brew install ffmpeg")
        sys.exit(1)

_check_deps()

import numpy as np
from PIL import Image as PILImage, ImageDraw as IDraw, ImageFont
from pymavlink import mavutil

# ── Config loader ─────────────────────────────────────────────────────────────
def load_config(config_path: str):
    import importlib.util
    spec = importlib.util.spec_from_file_location("osd_config", config_path)
    cfg = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(cfg)
    return cfg

# ── ArduPlane flight modes (fixed-wing + VTOL/quadplane) ─────────────────────
PLANE_MODES = {
    0:  "MANUAL",
    1:  "CIRCLE",
    2:  "STABILIZE",
    3:  "TRAINING",
    4:  "ACRO",
    5:  "FBWA",
    6:  "FBWB",
    7:  "CRUISE",
    8:  "AUTOTUNE",
    10: "AUTO",
    11: "RTL",
    12: "LOITER",
    13: "TAKEOFF",
    14: "AVOID_ADSB",
    15: "GUIDED",
    16: "INITIALISING",
    17: "QSTABILIZE",
    18: "QHOVER",
    19: "QLOITER",
    20: "QLAND",
    21: "QRTL",
    22: "QAUTOTUNE",
    23: "QACRO",
    24: "THERMAL",
    25: "LOITER_ALT_QLAND",
    26: "AUTOLAND",
}

# ── Log reader ────────────────────────────────────────────────────────────────
class LogData:
    """Parses .bin and exposes time-indexed telemetry."""

    def __init__(self, bin_path: str, verbose=True):
        self.path = bin_path
        self.verbose = verbose

        # time-series arrays (seconds, value)
        self.gps_speed   = []   # m/s
        self.air_speed   = []   # m/s  — from ARSP sensor
        self.altitude    = []   # m relative
        self.altitude_abs= []   # m AMSL
        self.pitch       = []   # deg
        self.roll        = []   # deg
        self.yaw         = []   # deg
        self.flight_mode = []   # (t, mode_str)
        self.messages    = []   # (t, text, severity)
        self.rangefinder = []   # (t, distance_m) — only valid readings
        self.wind_vn     = []   # (t, m/s) — wind north (EKF estimate)
        self.wind_ve     = []   # (t, m/s) — wind east  (EKF estimate)

        self._parse()

    def _parse(self):
        if self.verbose:
            print(f"[log] Opening {self.path}")
        mlog = mavutil.mavlink_connection(self.path, robust_parsing=True)
        t0 = None

        while True:
            msg = mlog.recv_match(blocking=False)
            if msg is None:
                break
            mtype = msg.get_type()
            if mtype == "BAD_DATA":
                continue

            # Determine base timestamp
            ts = getattr(msg, "TimeUS", None)
            if ts is not None:
                t_sec = ts / 1e6
            else:
                t_sec = None

            if mtype == "GPS":
                if t_sec is None:
                    continue
                if t0 is None:
                    t0 = t_sec
                t = t_sec - t0
                spd = getattr(msg, "Spd", None)
                alt = getattr(msg, "Alt", None)  # AMSL
                if spd is not None:
                    self.gps_speed.append((t, float(spd)))
                if alt is not None:
                    self.altitude_abs.append((t, float(alt)))


            elif mtype == "ARSP":
                if t_sec is None:
                    continue
                if t0 is None:
                    t0 = t_sec
                t = t_sec - t0
                aspd = getattr(msg, "Airspeed", None)
                if aspd is not None:
                    self.air_speed.append((t, float(aspd)))

            elif mtype == "BARO":
                if t_sec is None:
                    continue
                if t0 is None:
                    t0 = t_sec
                t = t_sec - t0
                alt = getattr(msg, "Alt", None)
                if alt is not None:
                    self.altitude.append((t, float(alt)))

            elif mtype == "ATT":
                if t_sec is None:
                    continue
                if t0 is None:
                    t0 = t_sec
                t = t_sec - t0
                p = getattr(msg, "Pitch", None)
                r = getattr(msg, "Roll", None)
                y = getattr(msg, "Yaw", None)
                if p is not None:
                    self.pitch.append((t, float(p)))
                if r is not None:
                    self.roll.append((t, float(r)))
                if y is not None:
                    self.yaw.append((t, float(y)))

            elif mtype == "MODE":
                if t_sec is None:
                    continue
                if t0 is None:
                    t0 = t_sec
                t = t_sec - t0
                mode_num = getattr(msg, "Mode", 0)
                reason  = getattr(msg, "Rsn", None)
                # Try to detect vehicle type from mode numbers
                name = self._mode_name(mode_num)
                self.flight_mode.append((t, name))

            elif mtype == "MSG":
                if t_sec is None:
                    continue
                if t0 is None:
                    t0 = t_sec
                t = t_sec - t0
                text = getattr(msg, "Message", "")
                sev  = getattr(msg, "Severity", 6)
                self.messages.append((t, str(text), int(sev)))


            elif mtype == "RFND":
                if t_sec is None:
                    continue
                if t0 is None:
                    t0 = t_sec
                t = t_sec - t0
                dist  = getattr(msg, "Dist", None)
                status = getattr(msg, "Status", 0)
                # Status 4 = Good; only store valid readings
                if dist is not None and status == 4 and float(dist) > 0:
                    self.rangefinder.append((t, float(dist)))


            elif mtype in ("XKF2", "NKF2"):
                # EKF wind estimate. XKF2 = EKF3 (newer), NKF2 = EKF2 (older).
                # Both expose VWN (wind north m/s) and VWE (wind east m/s).
                if t_sec is None:
                    continue
                if t0 is None:
                    t0 = t_sec
                t   = t_sec - t0
                vwn = getattr(msg, "VWN", None)
                vwe = getattr(msg, "VWE", None)
                if vwn is not None and vwe is not None:
                    # Only store if at least one is non-zero — EKF reports zeros
                    # before it has converged on a wind estimate.
                    if abs(float(vwn)) > 1e-4 or abs(float(vwe)) > 1e-4:
                        self.wind_vn.append((t, float(vwn)))
                        self.wind_ve.append((t, float(vwe)))

        if t0 is None:
            print("[warn] No timestamped messages found — log may be empty or corrupt.")
            return

        # Compute relative altitude from BARO Alt by zeroing at start
        if self.altitude:
            alt0 = self.altitude[0][1]
            self.altitude = [(t, a - alt0) for t, a in self.altitude]

        duration = max(
            self.altitude[-1][0] if self.altitude else 0,
            self.gps_speed[-1][0] if self.gps_speed else 0,
            self.pitch[-1][0] if self.pitch else 0,
        )
        if self.verbose:
            print(f"[log] Duration: {duration:.1f}s")
            print(f"[log] GPS speed samples: {len(self.gps_speed)}")
            print(f"[log] Airspeed samples:  {len(self.air_speed)}")
            print(f"[log] Altitude samples:  {len(self.altitude)}")
            print(f"[log] Attitude samples:  {len(self.pitch)}")
            print(f"[log] Mode changes:      {len(self.flight_mode)}")
            print(f"[log] Status messages:   {len(self.messages)}")
            print(f"[log] Rangefinder samples:{len(self.rangefinder)}")
            print(f"[log] Wind samples:       {len(self.wind_vn)}")

    def _mode_name(self, num):
        return PLANE_MODES.get(num, f"Mode {num}")

    def duration(self) -> float:
        candidates = [
            self.altitude[-1][0] if self.altitude else 0,
            self.gps_speed[-1][0] if self.gps_speed else 0,
            self.pitch[-1][0] if self.pitch else 0,
            self.flight_mode[-1][0] if self.flight_mode else 0,
        ]
        return max(candidates)

    def sample(self, series: list, t: float, default=0.0):
        """Linear interpolation at time t."""
        if not series:
            return default
        if t <= series[0][0]:
            return series[0][1]
        if t >= series[-1][0]:
            return series[-1][1]
        # Binary search
        lo, hi = 0, len(series) - 1
        while lo < hi - 1:
            mid = (lo + hi) // 2
            if series[mid][0] <= t:
                lo = mid
            else:
                hi = mid
        t0, v0 = series[lo]
        t1, v1 = series[hi]
        if t1 == t0:
            return v0
        frac = (t - t0) / (t1 - t0)
        return v0 + frac * (v1 - v0)

    def mode_at(self, t: float) -> str:
        if not self.flight_mode:
            return "Unknown"
        mode = self.flight_mode[0][1]
        for mt, m in self.flight_mode:
            if mt <= t:
                mode = m
            else:
                break
        return mode

    def messages_at(self, t: float, window: float) -> list:
        """Messages visible at time t (within window seconds before t)."""
        return [(mt, txt, sev) for mt, txt, sev in self.messages
                if t - window <= mt <= t]


# ── Frame renderer ────────────────────────────────────────────────────────────
class OSDRenderer:
    """
    Renders a full graphical HUD panel:
      Left  : GND speed tape | AIR speed tape | ALT tape (+ rangefinder badge)
      Centre: Artificial horizon + compass ribbon  (absolutely centred)
      Right : Vertical airspeed bar | Mode pill | Messages
    All widgets rendered with PIL for pixel-perfect control.
    """

    def __init__(self, cfg, log):
        self.cfg = cfg
        self.log = log
        self.w   = cfg.OUTPUT_WIDTH
        self.h   = cfg.OUTPUT_HEIGHT

        # Colours as 0-255 RGBA tuples
        self.C_BG       = self._f2i(cfg.COLOR_BG)
        self.C_ACCENT   = self._f2i(cfg.COLOR_ACCENT)
        self.C_VALUE    = self._f2i(cfg.COLOR_VALUE)
        self.C_LABEL    = self._f2i(cfg.COLOR_LABEL)
        self.C_MODE_BG  = self._f2i(cfg.COLOR_MODE_BG)
        self.C_MODE_TXT = self._f2i(cfg.COLOR_MODE_TEXT)
        self.C_MSG      = self._f2i(cfg.COLOR_MESSAGE)
        self.C_WARN     = self._f2i(cfg.COLOR_WARN)
        self.C_SKY      = (45, 100, 165, 217)
        self.C_GND      = (95, 62,  22,  217)
        self.C_HORIZON  = (255, 255, 255, 140)
        self.C_RETICLE  = (255, 215, 0,   230)
        self.C_TICK     = (255, 255, 255, 90)
        self.C_TICK_MAJ = (255, 255, 255, 160)
        self.C_COMPASS  = (255, 185, 55,  230)
        self.C_RNG      = (65,  210, 130, 240)
        self.C_RNG_BG   = (30,  120, 70,  55)
        self.C_VAS      = self._f2i(cfg.COLOR_ACCENT)
        self.C_BORDER   = (255, 255, 255, 65)
        self.C_TAPE_PTR = (255, 255, 255, 80)
        self.C_CURSOR   = (255, 255, 255, 220)
        self.C_CURSOR_BG= (8,   8,   14,  185)
        self.C_PITCH    = (255, 255, 255, 80)
        self.C_PITCH_MAJ= (255, 255, 255, 130)

        # Layout — all in pixels
        self.MARGIN      = cfg.LOWER_THIRD_MARGIN_PX
        self.PH          = int(self.h * cfg.LOWER_THIRD_HEIGHT_FRACTION)
        self.PY          = self.MARGIN                 # panel bottom-left y
        self.BOX_R       = 18
        self.GAP         = 22
        self.GAP_SM      = 14
        self.TAPE_W      = 270
        self.AH_W        = 440
        self.COMPASS_H   = 56
        self.VAS_W       = 60
        self.MODE_W      = 240
        self.TAPE_SPAN   = 60    # value range shown in full tape height

        # Font sizes (PIL ImageFont via truetype if available, else default)
        self._fonts = {}
        self._init_fonts()

    @staticmethod
    def _f2i(c):
        """Convert 0-1 float RGBA tuple to 0-255 int tuple."""
        return tuple(int(x * 255) for x in c)

    def _init_fonts(self):

        # Locate the fonts directory — try several plausible locations
        candidates = [
            Path(__file__).resolve().parent / "fonts",
            Path.cwd() / "fonts",
            Path(__file__).resolve().parent,
            Path.cwd(),
        ]
        fonts_dir = None
        for c in candidates:
            if (c / "BarlowCondensed-Bold.ttf").exists():
                fonts_dir = c
                break

        if fonts_dir is None:
            print("[ERROR] Cannot find BarlowCondensed-Bold.ttf in any of:")
            for c in candidates:
                print(f"          {c}")
            print("        The fonts/ folder must sit next to ardupilot_osd.py")
            print("        OR in the directory you run the script from.")
            sys.exit(1)

        reg  = str(fonts_dir / "BarlowCondensed-Regular.ttf")
        bold = str(fonts_dir / "BarlowCondensed-Bold.ttf")
        print(f"[fonts] Loading from {fonts_dir}")

        def _load(path, size):
            try:
                return ImageFont.truetype(path, size)
            except Exception as e:
                # If a TTF that we KNOW exists fails to load, that's a real
                # error — don't silently fall back to the unscalable bitmap font.
                print(f"[ERROR] Failed to load font {path} at size {size}: {e}")
                print("        Falling back to default bitmap font (text will be tiny).")
                return ImageFont.load_default()
        # Font sizes scale directly with output height (1080p reference).
        # Values below are pixel-equivalent (PIL ≥9 on Linux/macOS).
        s = self.h / 1080.0
        self._fonts = {
            "label":    _load(reg,  int(18 * s)),   # field labels "GND SPD"
            "value":    _load(bold, int(54 * s)),   # (unused legacy)
            "unit":     _load(reg,  int(16 * s)),   # unit "km/h"
            "tape_num": _load(reg,  int(20 * s)),   # tape tick numbers
            "cursor":   _load(bold, int(34 * s)),   # cursor box number
            "cursor_u": _load(reg,  int(16 * s)),   # cursor unit
            "compass":  _load(bold, int(20 * s)),   # N/S/E/W cardinal labels
            "card":     _load(bold, int(17 * s)),   # compass degree numbers
            "card_sm":  _load(reg,  int(14 * s)),   # minor compass numbers
            "mode":     _load(bold, int(20 * s)),   # mode pill text
            "msg":      _load(reg,  int(20 * s)),   # status messages
            "rng_val":  _load(bold, int(24 * s)),   # rangefinder distance
            "rng_lbl":  _load(reg,  int(14 * s)),   # "RNG m" label
            "pitch_lbl":_load(reg,  int(17 * s)),   # pitch ladder labels
            "hdg":      _load(bold, int(25 * s)),   # compass heading readout
        }

    # ── PIL drawing helpers ───────────────────────────────────────────────
    def _rounded_rect(self, draw, x, y, w, h, r, fill, border=None):
        x1, y1 = x + w, y + h
        r = min(r, w // 2, h // 2)
        draw.rectangle([x + r, y, x1 - r, y1], fill=fill)
        draw.rectangle([x, y + r, x1, y1 - r], fill=fill)
        draw.pieslice([x,       y,       x + 2*r, y + 2*r], 180, 270, fill=fill)
        draw.pieslice([x1-2*r,  y,       x1,      y + 2*r],  270, 360, fill=fill)
        draw.pieslice([x,       y1-2*r,  x + 2*r, y1],        90,  180, fill=fill)
        draw.pieslice([x1-2*r,  y1-2*r,  x1,      y1],         0,   90, fill=fill)
        if border:
            draw.arc([x,       y,       x + 2*r, y + 2*r], 180, 270, fill=border)
            draw.arc([x1-2*r,  y,       x1,      y + 2*r], 270, 360, fill=border)
            draw.arc([x,       y1-2*r,  x + 2*r, y1],       90, 180, fill=border)
            draw.arc([x1-2*r,  y1-2*r,  x1,      y1],        0,  90, fill=border)
            draw.line([x+r, y,  x1-r, y],  fill=border)
            draw.line([x+r, y1, x1-r, y1], fill=border)
            draw.line([x,  y+r, x,  y1-r], fill=border)
            draw.line([x1, y+r, x1, y1-r], fill=border)

    def _text_size(self, draw, text, font):
        bb = draw.textbbox((0, 0), text, font=font)
        return bb[2] - bb[0], bb[3] - bb[1]

    def _draw_text_centred(self, draw, cx, cy, text, font, fill):
        tw, th = self._text_size(draw, text, font)
        draw.text((cx - tw // 2, cy - th // 2), text, font=font, fill=fill)

    def _draw_text_right(self, draw, rx, cy, text, font, fill):
        tw, th = self._text_size(draw, text, font)
        draw.text((rx - tw, cy - th // 2), text, font=font, fill=fill)

    def _speed_convert(self, ms):
        u = self.cfg.SPEED_UNITS
        if u == "kmh":  return ms * 3.6,  "km/h"
        if u == "mph":  return ms * 2.237, "mph"
        return ms, "m/s"

    # ── Widget: vertical tape ─────────────────────────────────────────────
    def _draw_tape(self, img, draw, x, y, w, h, value, unit_str, label_str,
                   step=10, minor_step=2):
        """Vertical tape — scale numbers sit left of the ticks, readout box
        on the right so it never covers the sliding numbers."""
        # Background box
        self._rounded_rect(draw, x, y, w, h, self.BOX_R, self.C_BG, self.C_BORDER)

        # Label
        lf = self._fonts["label"]
        lw, lh = self._text_size(draw, label_str, lf)
        draw.text((x + w // 2 - lw // 2, y + 6), label_str, font=lf,
                  fill=self.C_LABEL)

        tape_y0 = y + lh + 10
        tape_h  = h - lh - 10

        # ── Layout zones (left → right): numbers | ticks | readout box ────
        nf        = self._fonts["tape_num"]
        num_w, _  = self._text_size(draw, "0000", nf)
        num_right = 8 + num_w            # numbers right-align here
        tick_x0   = num_right + 8        # ticks start just right of numbers
        tick_maj  = max(12, int(w * 0.06))
        tick_min  = tick_maj // 2
        box_gap   = 12
        box_x     = tick_x0 + tick_maj + box_gap

        # ── Tape clip: ticks + scale numbers ──────────────────────────────
        tape_clip = PILImage.new("RGBA", (w, tape_h), (0, 0, 0, 0))
        td = IDraw.Draw(tape_clip)

        px_per_unit = tape_h / self.TAPE_SPAN
        centre_val  = value
        val_min = centre_val - self.TAPE_SPAN / 2 - step
        val_max = centre_val + self.TAPE_SPAN / 2 + step
        v = math.floor(val_min / minor_step) * minor_step

        while v <= val_max:
            py_tape = int(tape_h / 2 - (v - centre_val) * px_per_unit)
            if 0 <= py_tape <= tape_h:
                is_major   = (round(v) % step == 0)
                tick_color = self.C_TICK_MAJ if is_major else self.C_TICK
                tick_len   = tick_maj if is_major else tick_min
                td.line([(tick_x0, py_tape), (tick_x0 + tick_len, py_tape)],
                        fill=tick_color, width=1)
                if is_major:
                    ntxt   = f"{int(round(v))}"
                    nw, nh = self._text_size(td, ntxt, nf)
                    td.text((num_right - nw, py_tape - nh // 2), ntxt,
                            font=nf, fill=self.C_TICK_MAJ)
            v += minor_step

        img.paste(tape_clip, (x, tape_y0), tape_clip)

        # ── Readout box on the right ──────────────────────────────────────
        val_txt = f"{value:.0f}"
        cf      = self._fonts["cursor"]
        uf      = self._fonts["cursor_u"]
        # Full bounding boxes — draw.text places text by the em-box top, not
        # the glyph top, so we keep the offsets and compensate when drawing.
        vbb = draw.textbbox((0, 0), val_txt, font=cf)
        ubb = draw.textbbox((0, 0), unit_str, font=uf)
        vw, vh = vbb[2] - vbb[0], vbb[3] - vbb[1]
        uw, uh = ubb[2] - ubb[0], ubb[3] - ubb[1]
        gap_vu  = 4
        total_h = vh + gap_vu + uh
        pad_v   = int(total_h * 0.22)
        cur_h   = total_h + pad_v * 2
        cur_y   = tape_y0 + tape_h // 2 - cur_h // 2
        cur_x   = x + box_x
        cur_w   = w - box_x - 6
        mid_y   = cur_y + cur_h // 2

        # Pointer triangle — points left from the box toward the ticks
        ptr_w = max(10, int(w * 0.05))
        draw.polygon([(cur_x - 1,         mid_y - ptr_w),
                      (cur_x - 1,         mid_y + ptr_w),
                      (cur_x - 1 - ptr_w, mid_y)], fill=self.C_TAPE_PTR)

        self._rounded_rect(draw, cur_x, cur_y, cur_w, cur_h, 6,
                            self.C_CURSOR_BG, (255, 255, 255, 55))
        cx_mid   = cur_x + cur_w // 2
        val_top  = cur_y + pad_v
        draw.text((cx_mid - vw // 2 - vbb[0], val_top - vbb[1]),
                  val_txt, font=cf, fill=self.C_CURSOR)
        unit_top = val_top + vh + gap_vu
        draw.text((cx_mid - uw // 2 - ubb[0], unit_top - ubb[1]),
                  unit_str, font=uf, fill=self.C_LABEL)

    # ── Widget: artificial horizon ────────────────────────────────────────
    def _draw_horizon(self, img, draw, x, y, w, h, pitch_deg, roll_deg):

        # Render into a sub-image, then paste with clip
        sub = PILImage.new("RGBA", (w, h), (0, 0, 0, 0))
        sd  = IDraw.Draw(sub)

        # Sky / ground fill rotated by roll
        # Horizon line offset by pitch (px_per_deg)
        px_per_deg = h / 60.0
        pitch_offset = pitch_deg * px_per_deg

        cx, cy = w // 2, h // 2
        roll_rad = math.radians(roll_deg)

        # Draw sky and ground as a rotated split
        # We oversample so rotation never exposes transparent edges
        pad = int(max(w, h) * 0.6)
        big = PILImage.new("RGBA", (w + 2*pad, h + 2*pad), (0, 0, 0, 0))
        bd  = IDraw.Draw(big)

        bw, bh = big.size
        bcx, bcy = bw // 2, bh // 2

        # Horizon y in big image — pitch up means horizon drops on screen
        horizon_y = bcy + pitch_offset

        # Fill sky above horizon line, ground below
        bd.rectangle([0, 0, bw, int(horizon_y)], fill=self.C_SKY)
        bd.rectangle([0, int(horizon_y), bw, bh], fill=self.C_GND)
        # Horizon line
        bd.line([(0, int(horizon_y)), (bw, int(horizon_y))],
                fill=self.C_HORIZON, width=2)

        # Rotate around centre of big image
        big_rot = big.rotate(roll_deg, center=(bcx, bcy), resample=PILImage.BILINEAR)

        # Crop back to widget size
        left = bcx - cx
        top  = bcy - cy
        cropped = big_rot.crop((left, top, left + w, top + h))

        # Rounded mask
        mask = PILImage.new("L", (w, h), 0)
        md   = IDraw.Draw(mask)
        r    = self.BOX_R
        md.rounded_rectangle([0, 0, w-1, h-1], radius=r, fill=255)
        sub.paste(cropped, (0, 0), mask)

        # ── Pitch ladder lines (drawn in sub, after sky/ground) ──────────
        # These need to be in the rotated frame so we re-draw after paste
        # Simpler: draw pitch lines in un-rotated coords then rotate mask
        pitch_sub = PILImage.new("RGBA", (w, h), (0, 0, 0, 0))
        pd2 = IDraw.Draw(pitch_sub)

        for deg_offset in [-10, -5, 5, 10]:
            py_line = cy + (deg_offset - pitch_deg) * px_per_deg
            lw2 = w // 3 if abs(deg_offset) == 10 else w // 4
            lx0 = cx - lw2 // 2
            lx1 = cx + lw2 // 2
            col = self.C_PITCH_MAJ if abs(deg_offset) == 10 else self.C_PITCH
            pd2.line([(lx0, int(py_line)), (lx1, int(py_line))], fill=col, width=1)
            # degree label
            if abs(deg_offset) == 10:
                lf = self._fonts["pitch_lbl"]
                txt = f"{abs(deg_offset)}"
                tw2, th2 = self._text_size(pd2, txt, lf)
                pd2.text((lx1 + 4, int(py_line) - th2 // 2), txt,
                         font=lf, fill=self.C_PITCH_MAJ)

        pitch_rot = pitch_sub.rotate(roll_deg, center=(cx, cy),
                                      resample=PILImage.BILINEAR)
        pitch_rot.putalpha(PILImage.fromarray(
            np.array(pitch_rot)[:, :, 3]))
        sub.paste(pitch_rot, (0, 0), pitch_rot)

        # ── Roll arc at bottom ────────────────────────────────────────────
        arc_r   = int(w * 0.42)
        arc_cx  = cx
        arc_cy  = h - 8
        sd2 = IDraw.Draw(sub)
        # Draw arc from -60 to +60 deg (reuse sd2 — don't create Draw per iteration)
        for a in range(-60, 61, 1):
            rad = math.radians(a - 90)
            ax_ = int(arc_cx + arc_r * math.cos(rad))
            ay_ = int(arc_cy + arc_r * math.sin(rad))
            col = self.C_TICK_MAJ if a % 30 == 0 else self.C_TICK
            sd2.point((ax_, ay_), fill=col)

        # Tick marks at -60, -30, 0, +30, +60
        for a in [-60, -30, 0, 30, 60]:
            rad_out = math.radians(a - 90)
            rad_in  = rad_out
            tick_len = 9 if a % 30 == 0 else 6
            ox = arc_cx + arc_r * math.cos(rad_out)
            oy = arc_cy + arc_r * math.sin(rad_out)
            ix = arc_cx + (arc_r - tick_len) * math.cos(rad_in)
            iy = arc_cy + (arc_r - tick_len) * math.sin(rad_in)
            sd2.line([(int(ox), int(oy)), (int(ix), int(iy))],
                     fill=self.C_TICK_MAJ, width=1)

        # Roll indicator triangle (rotates with roll)
        tri_rad  = arc_r - 2
        tri_ang  = math.radians(roll_deg - 90)
        tri_tip  = (arc_cx + tri_rad * math.cos(tri_ang),
                    arc_cy + tri_rad * math.sin(tri_ang))
        perp     = math.radians(roll_deg)
        tri_base = 5
        b1 = (tri_tip[0] + tri_base * math.cos(perp + math.pi / 2),
               tri_tip[1] + tri_base * math.sin(perp + math.pi / 2))
        b2 = (tri_tip[0] + tri_base * math.cos(perp - math.pi / 2),
               tri_tip[1] + tri_base * math.sin(perp - math.pi / 2))
        base_mid_x = (b1[0] + b2[0]) / 2 + (arc_r + 6) / arc_r * \
                     (arc_cx + (arc_r + 6) * math.cos(tri_ang) - arc_cx)
        # simpler — just draw fixed upward triangle at zero, rotated
        tri_pts = [
            (int(tri_tip[0]), int(tri_tip[1])),
            (int(b1[0]), int(b1[1])),
            (int(b2[0]), int(b2[1])),
        ]
        sd2.polygon(tri_pts, fill=self.C_RETICLE)

        # ── Aircraft reticle (fixed, centre) ─────────────────────────────
        arm_len = int(w * 0.18)
        dot_r   = 3
        sd2.line([(cx - arm_len, cy), (cx - dot_r - 2, cy)],
                 fill=self.C_RETICLE, width=2)
        sd2.line([(cx + dot_r + 2, cy), (cx + arm_len, cy)],
                 fill=self.C_RETICLE, width=2)
        sd2.ellipse([(cx - dot_r, cy - dot_r), (cx + dot_r, cy + dot_r)],
                    fill=self.C_RETICLE)

        # ── Label ─────────────────────────────────────────────────────────
        lf  = self._fonts["label"]
        ltxt = "ATT"
        lw2, lh2 = self._text_size(sd2, ltxt, lf)
        sd2.text((cx - lw2 // 2, 5), ltxt, font=lf, fill=self.C_LABEL)

        # ── Border ────────────────────────────────────────────────────────
        sd2.rounded_rectangle([0, 0, w - 1, h - 1], radius=self.BOX_R,
                               outline=self.C_BORDER, width=1)

        img.paste(sub, (x, y), sub)

    # ── Widget: compass ribbon ────────────────────────────────────────────
    def _draw_compass(self, img, draw, x, y, w, h, yaw_deg):
        sub = PILImage.new("RGBA", (w, h), (0, 0, 0, 0))
        sd  = IDraw.Draw(sub)
        self._rounded_rect(sd, 0, 0, w, h, 7, self.C_BG, self.C_BORDER)

        CARDS = {0:'N', 45:'NE', 90:'E', 135:'SE',
                 180:'S', 225:'SW', 270:'W', 315:'NW'}
        px_per_deg = w / 80.0   # 80° visible range
        tick_area_h = h

        for offset in range(-45, 46):
            deg = (yaw_deg + offset) % 360
            px  = w // 2 + int(offset * px_per_deg)
            if px < 2 or px > w - 2:
                continue
            is_10 = (int(deg) % 10 == 0)
            is_5  = (int(deg) % 5 == 0)
            if not (is_5 or is_10):
                continue
            tick_h = 10 if is_10 else 6
            col    = self.C_TICK_MAJ if is_10 else self.C_TICK
            sd.line([(px, 0), (px, tick_h)], fill=col, width=1)
            if is_10:
                card = CARDS.get(int(deg) % 360)
                txt  = card if card else str(int(deg))
                fnt  = self._fonts["card"] if card else self._fonts["card_sm"]
                col2 = self.C_COMPASS if card else self.C_TICK_MAJ
                tw, th = self._text_size(sd, txt, fnt)
                # Skip labels whose bounding box would extend past the ribbon edges
                lx = px - tw // 2
                if lx < 2 or lx + tw > w - 2:
                    continue
                sd.text((lx, tick_h + 1), txt, font=fnt, fill=col2)

        # Centre cursor line
        sd.line([(w // 2, 0), (w // 2, tick_area_h)],
                fill=(255, 210, 0, 165), width=1)
        # Cursor triangle
        tri_x = w // 2
        sd.polygon([(tri_x, 0), (tri_x - 4, 5), (tri_x + 4, 5)],
                   fill=(255, 210, 0, 200))

        img.paste(sub, (x, y), sub)

    # ── Widget: vertical airspeed bar ─────────────────────────────────────
    def _draw_vas(self, img, draw, x, y, w, h, vspeed_ms):
        self._rounded_rect(draw, x, y, w, h, self.BOX_R, self.C_BG, self.C_BORDER)

        lf   = self._fonts["label"]
        ltxt = "V/S"
        lw2, lh2 = self._text_size(draw, ltxt, lf)
        draw.text((x + w // 2 - lw2 // 2, y + 5), ltxt, font=lf,
                  fill=self.C_LABEL)

        # Track geometry
        track_w  = 5
        track_x  = x + w // 2 - track_w // 2
        track_y0 = y + lh2 + 12
        val_f    = self._fonts["cursor_u"]
        vtxt     = f"{vspeed_ms:+.1f}"
        vw2, vh2 = self._text_size(draw, vtxt, val_f)
        track_y1 = y + h - vh2 - 10
        track_h  = track_y1 - track_y0
        mid_y    = track_y0 + track_h // 2

        # Track bg
        self._rounded_rect(draw, track_x, track_y0, track_w, track_h, 2,
                           (255, 255, 255, 18))
        # Fill — clamp to ±5 m/s full scale
        frac    = max(-1.0, min(1.0, vspeed_ms / 5.0))
        fill_h  = int(abs(frac) * track_h / 2)
        if frac >= 0:
            fy0 = mid_y - fill_h
            fy1 = mid_y
        else:
            fy0 = mid_y
            fy1 = mid_y + fill_h
        if fill_h > 0:
            self._rounded_rect(draw, track_x, fy0, track_w, max(2, fy1 - fy0),
                               2, self.C_VAS)
        # Zero line
        draw.line([(track_x - 2, mid_y), (track_x + track_w + 2, mid_y)],
                  fill=(255, 255, 255, 100), width=1)

        # Value label at bottom
        draw.text((x + w // 2 - vw2 // 2, track_y1 + 2), vtxt,
                  font=val_f, fill=self.C_ACCENT)


    # ── Widget: wind compass ──────────────────────────────────────────────
    def _draw_wind(self, img, draw, x, y, w, h, wind_vn, wind_ve, yaw_deg,
                   min_speed_ms=0.5):
        """
        Body-frame wind compass. Aircraft silhouette in centre points up
        (nose = top of widget). Mauve arrow on the ring shows wind "from"
        bearing relative to the aircraft, pointing inward toward the centre.
        Speed text sits in a small badge at the bottom of the ring.
        """
        sub = PILImage.new("RGBA", (w, h), (0, 0, 0, 0))
        sd  = IDraw.Draw(sub)

        # Background box
        self._rounded_rect(sd, 0, 0, w, h, self.BOX_R, self.C_BG, self.C_BORDER)

        # Label
        lf = self._fonts["label"]
        ltxt = "WIND"
        lw2, lh2 = self._text_size(sd, ltxt, lf)
        sd.text((w // 2 - lw2 // 2, 6), ltxt, font=lf, fill=self.C_LABEL)

        # Compass geometry
        cx = w // 2
        # Centre slightly below label, with breathing room at the bottom for speed badge
        cy = (lh2 + 14 + h - 14) // 2
        r  = min(w, h - lh2 - 24) // 2 - 4   # outer ring radius

        # ── Outer ring ────────────────────────────────────────────────────
        sd.ellipse([cx - r, cy - r, cx + r, cy + r],
                   outline=(255, 255, 255, 60), width=2)

        # ── Cardinal tick marks at 0/90/180/270 (long) and 45° (short) ────
        for deg, length in [(0, 0.16), (90, 0.16), (180, 0.16), (270, 0.16),
                            (45, 0.10), (135, 0.10), (225, 0.10), (315, 0.10)]:
            rad = math.radians(deg - 90)
            r_in  = r * (1.0 - length)
            r_out = r
            x0 = cx + r_in  * math.cos(rad)
            y0 = cy + r_in  * math.sin(rad)
            x1 = cx + r_out * math.cos(rad)
            y1 = cy + r_out * math.sin(rad)
            col = (255, 255, 255, 90) if length > 0.12 else (255, 255, 255, 55)
            sd.line([(x0, y0), (x1, y1)], fill=col, width=2 if length > 0.12 else 1)

        # ── Aircraft silhouette (viewed from above, nose up) ──────────────
        # Scale aircraft features to ring radius
        ac_scale = r / 60.0   # tuned at r≈60
        def acp(x_off, y_off):
            return (cx + x_off * ac_scale, cy + y_off * ac_scale)

        ac_fill = (220, 220, 220, 215)
        # Fuselage (vertical rectangle)
        sd.rectangle([acp(-1.6, -22), acp(1.6, 14)], fill=ac_fill)
        # Main wings
        sd.polygon([acp(-28, -2), acp(28, -2), acp(24, 4), acp(-24, 4)],
                   fill=ac_fill)
        # Tail wings
        sd.polygon([acp(-10, 13), acp(10, 13), acp(7, 17), acp(-7, 17)],
                   fill=ac_fill)
        # Nose triangle
        sd.polygon([acp(-3, -22), acp(3, -22), acp(0, -28)],
                   fill=ac_fill)
        # Cockpit dot
        cock = acp(0, -14)
        cr   = max(1, int(2 * ac_scale))
        sd.ellipse([cock[0] - cr, cock[1] - cr, cock[0] + cr, cock[1] + cr],
                   fill=(40, 40, 40, 180))

        # ── Compute wind ──────────────────────────────────────────────────
        speed_ms = math.sqrt(wind_vn * wind_vn + wind_ve * wind_ve)
        has_wind = speed_ms >= min_speed_ms

        if has_wind:
            # Earth-frame "from" bearing in degrees (where wind is COMING FROM)
            # VWN/VWE describe wind velocity vector (where wind is going to).
            # The "from" direction is the opposite: atan2(-VWE, -VWN)
            earth_from = (math.degrees(math.atan2(-wind_ve, -wind_vn)) + 360) % 360
            # Convert to body-frame bearing (relative to aircraft nose)
            body_from  = (earth_from - yaw_deg + 360) % 360

            # Arrow geometry — sits on the outside of the ring at body_from,
            # points inward toward centre.
            ang = math.radians(body_from - 90)
            # Outer end (the "from" point, on/just outside the ring)
            ox = cx + r * math.cos(ang)
            oy = cy + r * math.sin(ang)
            # Arrowhead tip (inside the ring, closer to centre)
            tip_r = r * 0.42
            tx = cx + tip_r * math.cos(ang)
            ty = cy + tip_r * math.sin(ang)
            # Shaft starts at the outer dot and ends at the back of the arrowhead
            head_back_r = r * 0.55
            sx = cx + head_back_r * math.cos(ang)
            sy = cy + head_back_r * math.sin(ang)

            mauve = self.C_ACCENT
            # Outer dot at the "from" point
            dot_r = max(3, int(r * 0.07))
            sd.ellipse([ox - dot_r, oy - dot_r, ox + dot_r, oy + dot_r],
                       fill=mauve)
            # Shaft
            sd.line([(ox, oy), (sx, sy)], fill=mauve,
                    width=max(2, int(r * 0.06)))
            # Arrowhead — equilateral-ish triangle, base at (sx,sy) perpendicular
            perp = ang + math.pi / 2
            head_w = r * 0.16
            hx1 = sx + head_w * math.cos(perp)
            hy1 = sy + head_w * math.sin(perp)
            hx2 = sx - head_w * math.cos(perp)
            hy2 = sy - head_w * math.sin(perp)
            sd.polygon([(tx, ty), (hx1, hy1), (hx2, hy2)], fill=mauve)

        # ── Speed badge at bottom of ring ─────────────────────────────────
        sf = self._fonts["cursor_u"]   # numeric font, smallish
        uf = self._fonts["rng_lbl"]    # tiny unit font
        if has_wind:
            speed_disp, unit_disp = self._speed_convert(speed_ms)
            stxt = f"{speed_disp:.0f}"
        else:
            stxt = "—"
            unit_disp = self.cfg.SPEED_UNITS if self.cfg.SPEED_UNITS != "kmh" else "km/h"
            if unit_disp == "ms": unit_disp = "m/s"
            if unit_disp == "mph": unit_disp = "mph"
        sw, sh = self._text_size(sd, stxt, sf)
        uw, uh = self._text_size(sd, unit_disp, uf)
        badge_w  = sw + uw + 14
        badge_h  = max(sh, uh) + 6
        badge_x  = cx - badge_w // 2
        badge_y  = cy + r - badge_h // 2
        self._rounded_rect(sd, badge_x, badge_y, badge_w, badge_h, 5,
                           (8, 8, 14, 200), (255, 255, 255, 40))
        # value + unit side by side
        sd.text((badge_x + 6, badge_y + (badge_h - sh) // 2), stxt,
                font=sf, fill=self.C_CURSOR)
        sd.text((badge_x + 6 + sw + 4,
                 badge_y + (badge_h - uh) // 2 + (sh - uh) // 2 + 1),
                unit_disp, font=uf, fill=self.C_LABEL)

        img.paste(sub, (x, y), sub)

    # ── Widget: rangefinder badge ──────────────────────────────────────────
    def _draw_rng_badge(self, draw, bx, by, dist_m):
        """Small green badge overlaid on the alt tape."""
        txt_val = f"{dist_m:.1f}"
        txt_lbl = "RNG m"
        vf = self._fonts["rng_val"]
        lf = self._fonts["rng_lbl"]
        vw, vh = self._text_size(draw, txt_val, vf)
        lw2, lh2 = self._text_size(draw, txt_lbl, lf)
        bw = max(vw, lw2) + 10
        bh = vh + lh2 + 6
        self._rounded_rect(draw, bx, by, bw, bh, 5, self.C_RNG_BG,
                           (self.C_RNG[0], self.C_RNG[1], self.C_RNG[2], 100))
        draw.text((bx + bw // 2 - vw // 2, by + 3), txt_val,
                  font=vf, fill=self.C_RNG)
        draw.text((bx + bw // 2 - lw2 // 2, by + 3 + vh + 1), txt_lbl,
                  font=lf, fill=(self.C_RNG[0], self.C_RNG[1],
                                 self.C_RNG[2], 140))
        return bw  # so caller can right-align

    # ── Widget: mode pill ─────────────────────────────────────────────────
    def _draw_mode(self, draw, x_right, y, h, mode_str):
        """Mode box is right-anchored at x_right and auto-sizes to fit content."""
        lf = self._fonts["label"]
        mf = self._fonts["mode"]
        ltxt = "MODE"
        lw2, lh2 = self._text_size(draw, ltxt, lf)
        mw2, mh2 = self._text_size(draw, mode_str, mf)
        pill_pad_x = 14
        pill_pad_y = 8
        pill_w     = mw2 + pill_pad_x * 2
        pill_h     = mh2 + pill_pad_y
        # total box width: label + gap + pill + side paddings
        inner_gap = 14
        box_pad   = 16
        w         = box_pad + lw2 + inner_gap + pill_w + box_pad
        x         = x_right - w

        self._rounded_rect(draw, x, y, w, h, self.BOX_R, self.C_BG, self.C_BORDER)
        # Label on left
        draw.text((x + box_pad, y + h // 2 - lh2 // 2), ltxt, font=lf,
                  fill=self.C_LABEL)
        # Pill on right
        pill_x = x + w - box_pad - pill_w
        pill_y = y + h // 2 - pill_h // 2
        self._rounded_rect(draw, pill_x, pill_y, pill_w, pill_h, 8,
                           self.C_MODE_BG)
        draw.text((pill_x + pill_pad_x, pill_y + pill_pad_y // 2 - 2),
                  mode_str, font=mf, fill=self.C_MODE_TXT)
        return w  # report actual width for caller to align messages

    # ── Widget: messages ──────────────────────────────────────────────────
    def _draw_messages(self, draw, x, y, w, h, msgs_visible, t, window):
        self._rounded_rect(draw, x, y, w, h, self.BOX_R, self.C_BG, self.C_BORDER)
        lf  = self._fonts["label"]
        ltxt = "MESSAGES"
        lw2, lh2 = self._text_size(draw, ltxt, lf)
        pad = 16
        self._draw_text_right(draw, x + w - pad, y + lh2 // 2 + 8, ltxt, lf,
                              self.C_LABEL)
        mf = self._fonts["msg"]
        max_text_w = w - pad * 2
        line_h = int(h * 0.28)
        base_y = y + h - line_h
        for mi, (mt, txt, sev) in enumerate(reversed(msgs_visible[-2:])):
            age   = t - mt
            alpha = max(50, int(255 * (1.0 - age / window)))
            col   = self.C_WARN if sev <= 3 else self.C_MSG
            col   = (col[0], col[1], col[2], alpha)
            # Truncate to fit visually inside the box
            disp = txt
            while disp and self._text_size(draw, disp, mf)[0] > max_text_w:
                disp = disp[:-1]
            if len(disp) < len(txt) and len(disp) > 1:
                disp = disp[:-1] + "…"
            tw2, th2 = self._text_size(draw, disp, mf)
            draw.text((x + w - 8 - tw2, base_y - mi * line_h - th2 // 2),
                      disp, font=mf, fill=col)

    # ── Main render ───────────────────────────────────────────────────────
    def render_frame(self, t: float):
        cfg = self.cfg
        log = self.log

        img  = PILImage.new("RGBA", (self.w, self.h), (0, 0, 0, 0))
        draw = IDraw.Draw(img)

        m  = self.MARGIN
        ph = self.PH
        py = self.PY   # bottom of panel region (y from top of frame)
        # In image coords, y=0 is top, so panel sits at bottom:
        panel_top = self.h - py - ph

        GAP    = self.GAP
        GAP_SM = self.GAP_SM
        TW     = self.TAPE_W
        AHW    = self.AH_W
        COMP_H = self.COMPASS_H
        AH_H   = ph - COMP_H - 5   # horizon takes most of panel height
        VASW   = self.VAS_W
        MODEW  = self.MODE_W

        # ── Telemetry values ──────────────────────────────────────────────
        gnd_ms   = log.sample(log.gps_speed, t)
        air_ms   = log.sample(log.air_speed, t)
        alt_m    = log.sample(log.altitude_abs if cfg.ALTITUDE_DATUM == "absolute"
                              else log.altitude, t)
        pitch    = log.sample(log.pitch, t)
        roll     = log.sample(log.roll, t)
        yaw      = log.sample(log.yaw, t)
        yaw      = (yaw + 360) % 360
        vspeed   = 0.0
        if len(log.altitude) >= 2:
            dt = 0.5
            a1 = log.sample(log.altitude, t)
            a0 = log.sample(log.altitude, max(0, t - dt))
            vspeed = (a1 - a0) / dt

        rng_m    = None
        if log.rangefinder:
            rng_raw = log.sample(log.rangefinder, t)
            # Only show if there's a recent reading within 2s
            recent = [d for ts, d in log.rangefinder
                      if abs(ts - t) < 2.0 and d > 0]
            if recent:
                rng_m = rng_raw

        mode_str = log.mode_at(t)
        msgs     = log.messages_at(t, cfg.MESSAGE_DISPLAY_SECONDS)
        gnd_val, gnd_unit = self._speed_convert(gnd_ms)
        air_val, air_unit = self._speed_convert(air_ms)

        # Wind (from EKF wind estimate, body-frame display)
        wind_vn  = log.sample(log.wind_vn, t) if log.wind_vn else 0.0
        wind_ve  = log.sample(log.wind_ve, t) if log.wind_ve else 0.0
        wind_enabled = getattr(cfg, "WIND_ENABLED", True) and bool(log.wind_vn)

        # ── AH column x — exactly centred ────────────────────────────────
        ah_x = self.w // 2 - AHW // 2

        # ── Left group: GND | AIR | WIND | gap | ALT ─────────────────────
        # Wind widget is a square the same height as the panel
        WIND_W = ph if wind_enabled else 0
        x = m
        gnd_x  = x;        x += TW + GAP_SM
        air_x  = x;        x += TW + GAP_SM
        wind_x = x if wind_enabled else 0
        if wind_enabled:
            x += WIND_W + GAP_SM
        alt_x  = x         # alt sits to the left of AH (will be recomputed below)

        # ensure alt_x + TW + GAP_SM == ah_x (right-align alt to AH)
        alt_x = ah_x - GAP_SM - TW

        # ── Right group starts after AH ───────────────────────────────────
        ah_right = ah_x + AHW
        vas_x    = ah_right + GAP_SM
        # mode and messages pushed to right margin
        mode_x   = self.w - m - MODEW
        msg_x    = mode_x   # same x, different y

        # ── Draw left tapes ───────────────────────────────────────────────
        for bx, val, unit, lbl in [
            (gnd_x, gnd_val, gnd_unit, "GND SPD"),
            (air_x, air_val, air_unit, "AIR SPD"),
            (alt_x, alt_m,   "m",      "ALT"),
        ]:
            self._draw_tape(img, draw, bx, panel_top, TW, ph,
                            val, unit, lbl)

        # ── Wind compass ──────────────────────────────────────────────────
        if wind_enabled:
            min_speed = getattr(cfg, "WIND_MIN_SPEED_MS", 0.5)
            self._draw_wind(img, draw, wind_x, panel_top, WIND_W, ph,
                            wind_vn, wind_ve, yaw,
                            min_speed_ms=min_speed)

        # Rangefinder badge — sits at top-right of alt tape, fully inside
        if rng_m is not None:
            # Render off-screen first to get actual width, then position
            tmp = PILImage.new("RGBA", (400, 100), (0,0,0,0))
            td  = IDraw.Draw(tmp)
            badge_w = self._draw_rng_badge(td, 0, 0, rng_m)
            # Place badge so its right edge sits 4px inside the alt tape edge
            bx = alt_x + TW - badge_w - 4
            self._draw_rng_badge(draw, bx, panel_top + 4, rng_m)

        # ── Artificial horizon ────────────────────────────────────────────
        self._draw_horizon(img, draw, ah_x, panel_top, AHW, AH_H,
                           pitch, roll)

        # ── Compass ribbon (below AH, same x/width) ───────────────────────
        comp_y = panel_top + AH_H + 5
        self._draw_compass(img, draw, ah_x, comp_y, AHW, COMP_H, yaw)

        # ── Vertical airspeed ─────────────────────────────────────────────
        self._draw_vas(img, draw, vas_x, panel_top, VASW, ph, vspeed)

        # ── Mode + messages on right ──────────────────────────────────────
        # Mode box auto-sizes to its content; messages box is wider so full
        # message text fits without truncation.
        x_right = self.w - m
        mode_h  = int(ph * 0.32)
        actual_mode_w = self._draw_mode(draw, x_right, panel_top, mode_h, mode_str)
        # Messages box width: enough to fit ~60 chars of message at this font size
        msg_box_w_factor = 0.20   # fraction of frame width — tune here
        msg_w  = max(int(self.w * msg_box_w_factor),
                     actual_mode_w)
        msg_x  = x_right - msg_w
        msg_h  = ph - mode_h - GAP_SM
        msg_y  = panel_top + mode_h + GAP_SM
        self._draw_messages(draw, msg_x, msg_y, msg_w, msg_h, msgs, t,
                            cfg.MESSAGE_DISPLAY_SECONDS)

        return np.array(img)

# ── FFmpeg pipe writer ────────────────────────────────────────────────────────
class VideoWriter:
    """Pipes RGBA frames to ffmpeg → ProRes 4444 (transparent) .mov"""

    def __init__(self, out_path: str, width: int, height: int, fps: float):
        self.out_path = out_path
        self.fps = fps
        # ProRes 4444 supports alpha channel — perfect for compositing
        cmd = [
            "ffmpeg", "-y",
            "-f", "rawvideo",
            "-vcodec", "rawvideo",
            "-pix_fmt", "rgba",
            "-s", f"{width}x{height}",
            "-r", str(fps),
            "-i", "-",
            "-vcodec", "prores_ks",
            "-profile:v", "4444",
            "-pix_fmt", "yuva444p10le",
            "-vendor", "apl0",
            "-bits_per_mb", "8000",
            out_path,
        ]
        self.proc = subprocess.Popen(cmd, stdin=subprocess.PIPE,
                                     stderr=subprocess.DEVNULL)

    def write(self, rgba: np.ndarray):
        self.proc.stdin.write(rgba.tobytes())

    def close(self):
        self.proc.stdin.close()
        self.proc.wait()


# ── Parallel rendering workers ───────────────────────────────────────────────
_pool_renderer: OSDRenderer = None  # type: ignore

def _worker_init(cfg_path: str, log: LogData):
    global _pool_renderer
    cfg = load_config(cfg_path)
    _pool_renderer = OSDRenderer(cfg, log)

def _render_worker(t: float) -> np.ndarray:
    return _pool_renderer.render_frame(t)


# ── CLI ───────────────────────────────────────────────────────────────────────
def parse_args():
    p = argparse.ArgumentParser(description="ArduPilot OSD overlay generator")
    p.add_argument("bin",        help="Path to ArduPilot .bin dataflash log")
    p.add_argument("--config",   default=None, help="Path to osd_config.py")
    p.add_argument("--out",      default=None, help="Output .mov path")
    p.add_argument("--offset",   type=float, default=None)
    p.add_argument("--fps",      type=float, default=None)
    p.add_argument("--width",    type=int,   default=None)
    p.add_argument("--height",   type=int,   default=None)
    p.add_argument("--preview",  action="store_true",
                   help="Render first 10 seconds only")
    p.add_argument("--dump",     action="store_true",
                   help="Print message types in log and exit")
    return p.parse_args()


def main():
    args = parse_args()

    # Load config
    script_dir  = Path(__file__).parent
    config_path = args.config or str(script_dir / "osd_config.py")
    if not os.path.exists(config_path):
        print(f"[ERROR] Config not found: {config_path}")
        sys.exit(1)
    cfg = load_config(config_path)

    # Apply CLI overrides
    if args.out:     cfg.OUTPUT_FILE = args.out
    if args.offset is not None: cfg.TIME_OFFSET_SECONDS = args.offset
    if args.fps:     cfg.OUTPUT_FPS  = args.fps
    if args.width:   cfg.OUTPUT_WIDTH  = args.width
    if args.height:  cfg.OUTPUT_HEIGHT = args.height

    # Dump mode
    if args.dump:
        print("Scanning log message types...")
        mlog = mavutil.mavlink_connection(args.bin, robust_parsing=True)
        types = set()
        while True:
            msg = mlog.recv_match(blocking=False)
            if msg is None:
                break
            types.add(msg.get_type())
        for t in sorted(types):
            print(f"  {t}")
        return

    # Load log
    log = LogData(args.bin)
    duration = log.duration()
    if duration == 0:
        print("[ERROR] No telemetry data found in log.")
        sys.exit(1)

    if args.preview:
        duration = min(duration, 10.0)
        print(f"[preview] Rendering first {duration:.1f}s")

    fps      = cfg.OUTPUT_FPS
    offset   = cfg.TIME_OFFSET_SECONDS
    n_frames = int(duration * fps)
    out_path = cfg.OUTPUT_FILE

    n_workers = max(1, multiprocessing.cpu_count() - 1)
    print(f"[render] {n_frames} frames @ {fps}fps → {out_path}")
    print(f"[render] Resolution: {cfg.OUTPUT_WIDTH}x{cfg.OUTPUT_HEIGHT}  Workers: {n_workers}")

    def fmt_time(s: float) -> str:
        m, s = divmod(int(s), 60)
        return f"{m}m{s:02d}s"

    times  = [i / fps + offset for i in range(n_frames)]
    writer = VideoWriter(out_path, cfg.OUTPUT_WIDTH, cfg.OUTPUT_HEIGHT, fps)
    interrupted = False
    render_start = time.monotonic()

    with multiprocessing.Pool(
        processes=n_workers,
        initializer=_worker_init,
        initargs=(config_path, log),
    ) as pool:
        try:
            for i, frame in enumerate(pool.imap(_render_worker, times, chunksize=1)):
                if i % int(fps) == 0:
                    elapsed = time.monotonic() - render_start
                    pct = i / n_frames
                    eta = (elapsed / pct - elapsed) if pct > 0 else 0
                    print(
                        f"\r[render] {pct*100:5.1f}%  {i}/{n_frames}"
                        f"  elapsed {fmt_time(elapsed)}  eta {fmt_time(eta)}   ",
                        end="", flush=True,
                    )
                writer.write(frame)
        except KeyboardInterrupt:
            pool.terminate()
            interrupted = True
            print("\n[interrupted]")
        finally:
            writer.close()

    if interrupted:
        return

    print(f"\n[done] Saved: {out_path}")
    print()
    print("── Compositing tips ────────────────────────────────────────────────")
    print("  DaVinci Resolve : Place overlay on track above footage.")
    print("                    Set composite mode to Normal — alpha is baked in.")
    print("  Final Cut Pro   : Drop onto storyline above clip, set blend to Normal.")
    print("  Premiere Pro    : Place on V2, no keying needed (ProRes 4444 alpha).")
    print("────────────────────────────────────────────────────────────────────")


if __name__ == "__main__":
    main()
