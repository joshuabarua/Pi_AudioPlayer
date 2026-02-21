#!/usr/bin/env python3
"""
Music Display + Audio Visualizer for Raspberry Pi Sense HAT.
Displays track info from AirPlay/Spotify metadata and shows real-time FFT visualization.
"""

import os
import sys
import re
import math
import ast
import time
import logging
import threading
import subprocess
import select
import datetime
import base64
from pathlib import Path
from typing import Optional, Tuple, Dict, Any, List
from dataclasses import dataclass, field
from functools import lru_cache

import numpy as np
import sounddevice as sd

# Optional: Sense HAT - fail gracefully if not available
try:
    from sense_hat import SenseHat
    SENSE_HAT_AVAILABLE = True
except ImportError:
    SENSE_HAT_AVAILABLE = False
    logging.warning("Sense HAT not available - running in headless mode")


# =============================================================================
# Configuration
# =============================================================================

@dataclass
class Config:
    """Centralized configuration with sensible defaults."""

    # Paths
    pipe_path: str = "/tmp/shairport-sync-metadata"

    # Audio settings
    pa_device_name: str = "camilla_sink.monitor"
    sample_rate: int = 44100
    block_size: int = 2048
    n_bands: int = 8
    smoothing: float = 0.3

    # Visualizer settings
    scroll_speed: float = 0.02
    check_interval: float = 0.12

    # Timeouts
    metadata_timeout: float = 20.0
    track_repeat_interval: float = 30.0
    no_audio_timeout: float = 10.0

    # AGC (Automatic Gain Control)
    agc_target_rms: float = 0.02
    agc_max_gain: float = 4.0
    agc_min_gain: float = 0.25
    agc_attack: float = 0.1
    agc_release: float = 0.01
    limit_threshold: float = 0.25

    # Volume Ducking (lower playback volume for notifications)
    duck_enabled: bool = True
    duck_level: float = 0.3  # 30% volume during ducking
    duck_duration: float = 2.0  # seconds to stay ducked

    # Brightness (time-of-day)
    day_brightness: float = 0.10
    twilight_brightness: float = 0.05
    night_brightness: float = 0.01

    # Colors (RGB tuples)
    airplay_blue: Tuple[int, int, int] = (0, 100, 255)
    spotify_green: Tuple[int, int, int] = (30, 215, 96)
    track_white: Tuple[int, int, int] = (255, 255, 255)
    error_red: Tuple[int, int, int] = (255, 0, 0)
    spinner_color: Tuple[int, int, int] = (255, 0, 0)
    green: Tuple[int, int, int] = (0, 255, 0)
    orange: Tuple[int, int, int] = (255, 140, 0)
    red: Tuple[int, int, int] = (255, 0, 0)

    # Retry settings
    audio_max_retries: int = 3
    audio_retry_delay: float = 2.0

    # Debug
    verbose: bool = False

    def __post_init__(self):
        self.app_colors: Dict[str, Tuple[int, int, int]] = {
            "Shairport Sync": self.airplay_blue,
            "AirPlay": self.airplay_blue,
            "Spotify": self.spotify_green,
            "librespot": self.spotify_green,
        }

    def get_app_color(self, app_name: str) -> Tuple[int, int, int]:
        """Get color for an app name (case-insensitive match)."""
        app_lower = app_name.lower()
        for key, color in self.app_colors.items():
            if key.lower() in app_lower:
                return color
        return self.track_white


# Global config instance
CONFIG = Config()


# =============================================================================
# Logging Setup
# =============================================================================

def setup_logging(verbose: bool = False) -> logging.Logger:
    """Configure structured logging."""
    level = logging.DEBUG if verbose else logging.INFO
    logging.basicConfig(
        level=level,
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
        datefmt="%H:%M:%S",
    )
    return logging.getLogger("music_display")


LOGGER = setup_logging()


# =============================================================================
# Compiled Regex Patterns (performance optimization)
# =============================================================================

# Metadata parsing
RE_PIPE_TYPE = re.compile(r"<type>([0-9A-Fa-f]+)</type>")
RE_PIPE_CODE = re.compile(r"<code>([0-9A-Fa-f]+)</code>")
RE_PIPE_DATA = re.compile(r"<data[^>]*>(.*?)</data>", re.S)

# App detection
RE_SINK_INPUT = re.compile(r"^\s*Sink Input #\d+")
RE_APP_NAME = re.compile(r'application\.name="([^"]+)"')

# Volume parsing
RE_VOLUME = re.compile(r"(\d+)%")


# =============================================================================
# Thread-Safe State Management
# =============================================================================

class ThreadSafeState:
    """Thread-safe state management for audio callback and main loop."""

    def __init__(self):
        self._lock = threading.RLock()
        self._levels_smooth = np.zeros(CONFIG.n_bands, dtype=np.float32)
        self._audio_last_active = 0.0
        self._ambient_index = 0
        self._agc_gain = 1.0
        self._stream_active = False
        self._last_error: Optional[str] = None
        self._silence_detected = False
        self._saved_volume: Optional[int] = None
        self._ducked_until: float = 0.0

    @property
    def levels_smooth(self) -> np.ndarray:
        with self._lock:
            return self._levels_smooth.copy()

    @levels_smooth.setter
    def levels_smooth(self, value: np.ndarray):
        with self._lock:
            self._levels_smooth = value.astype(np.float32)

    @property
    def audio_last_active(self) -> float:
        with self._lock:
            return self._audio_last_active

    @audio_last_active.setter
    def audio_last_active(self, value: float):
        with self._lock:
            self._audio_last_active = value

    @property
    def ambient_index(self) -> int:
        with self._lock:
            return self._ambient_index

    @ambient_index.setter
    def ambient_index(self, value: int):
        with self._lock:
            self._ambient_index = value

    @property
    def agc_gain(self) -> float:
        with self._lock:
            return self._agc_gain

    @agc_gain.setter
    def agc_gain(self, value: float):
        with self._lock:
            self._agc_gain = value

    @property
    def stream_active(self) -> bool:
        with self._lock:
            return self._stream_active

    @stream_active.setter
    def stream_active(self, value: bool):
        with self._lock:
            self._stream_active = value

    @property
    def last_error(self) -> Optional[str]:
        with self._lock:
            return self._last_error

    @last_error.setter
    def last_error(self, value: Optional[str]):
        with self._lock:
            self._last_error = value

    @property
    def ducked_until(self) -> float:
        with self._lock:
            return getattr(self, '_ducked_until', 0.0)

    @ducked_until.setter
    def ducked_until(self, value: float):
        with self._lock:
            self._ducked_until = value


# Global state instance
STATE = ThreadSafeState()


# =============================================================================
# Pre-computed Constants
# =============================================================================

# Hann window (created lazily in case block_size changes)
_HANN_WINDOW: Optional[np.ndarray] = None

def get_hann_window(size: int = CONFIG.block_size) -> np.ndarray:
    """Get or create Hann window of specified size."""
    global _HANN_WINDOW
    if _HANN_WINDOW is None or len(_HANN_WINDOW) != size:
        _HANN_WINDOW = np.hanning(size)
    return _HANN_WINDOW


# Spinner animation path
SPINNER_PATH = [
    (0, 0), (1, 0), (2, 0), (3, 0), (4, 0), (5, 0), (6, 0), (7, 0),
    (7, 1), (7, 2), (7, 3), (7, 4), (7, 5), (7, 6), (7, 7),
    (6, 7), (5, 7), (4, 7), (3, 7), (2, 7), (1, 7), (0, 7),
    (0, 6), (0, 5), (0, 4), (0, 3), (0, 2), (0, 1),
    (1, 1), (2, 1), (3, 1), (4, 1), (5, 1), (6, 1),
    (6, 2), (6, 3), (6, 4), (6, 5), (6, 6),
    (5, 6), (4, 6), (3, 6), (2, 6), (1, 6),
    (1, 5), (1, 4), (1, 3), (1, 2),
    (2, 2), (3, 2), (4, 2), (5, 2),
    (5, 3), (5, 4), (5, 5),
    (4, 5), (3, 5), (2, 5),
    (2, 4), (2, 3),
    (3, 3), (4, 3),
    (4, 4), (3, 4),
]
TAIL_LENGTH = 28


# =============================================================================
# Utility Functions
# =============================================================================

def get_brightness_factor(now: Optional[datetime.datetime] = None) -> float:
    """Get brightness factor based on time of day."""
    if now is None:
        now = datetime.datetime.now()
    h = now.hour + now.minute / 60.0

    if 8.0 <= h < 22.0:
        return CONFIG.day_brightness
    if 6.5 <= h < 8.0 or 22.0 <= h < 23.5:
        return CONFIG.twilight_brightness
    return CONFIG.night_brightness


def apply_brightness(color: Tuple[int, int, int], factor: float) -> Tuple[int, int, int]:
    """Apply brightness factor to RGB color."""
    r, g, b = color
    return int(r * factor), int(g * factor), int(b * factor)


def get_current_volume() -> int:
    """Get current PulseAudio sink volume (0-100)."""
    try:
        result = subprocess.run(
            ["pactl", "get-sink-volume", CONFIG.pa_device_name],
            capture_output=True,
            text=True,
            timeout=2,
        )
        for line in result.stdout.splitlines():
            if "Volume:" in line:
                match = RE_VOLUME.search(line)
                if match:
                    return int(match.group(1))
    except subprocess.TimeoutExpired:
        LOGGER.warning("pactl get-sink-volume timed out")
    except FileNotFoundError:
        LOGGER.warning("pactl not found")
    except subprocess.CalledProcessError as e:
        LOGGER.warning(f"pactl error: {e}")
    return 100


def set_sink_volume(volume_percent: int) -> bool:
    """Set PulseAudio sink volume. Returns True on success."""
    try:
        subprocess.run(
            ["pactl", "set-sink-volume", CONFIG.pa_device_name, f"{volume_percent}%"],
            capture_output=True,
            timeout=2,
        )
        return True
    except subprocess.TimeoutExpired:
        LOGGER.warning("pactl set-sink-volume timed out")
    except FileNotFoundError:
        LOGGER.warning("pactl not found")
    except subprocess.CalledProcessError as e:
        LOGGER.warning(f"pactl error: {e}")
    return False


def detect_current_app() -> str:
    """Detect which application is currently playing audio."""
    try:
        result = subprocess.run(
            ["pactl", "list", "sink-inputs"],
            capture_output=True,
            text=True,
            timeout=2,
        )
    except subprocess.TimeoutExpired:
        LOGGER.warning("pactl list sink-inputs timed out")
        return "unknown"
    except FileNotFoundError:
        LOGGER.warning("pactl not found")
        return "unknown"
    except subprocess.CalledProcessError as e:
        LOGGER.warning(f"pactl error: {e}")
        return "unknown"

    current_block: List[str] = []

    for line in result.stdout.splitlines():
        if RE_SINK_INPUT.match(line):
            if current_block:
                # Check previous block for app name
                for block_line in current_block:
                    match = RE_APP_NAME.search(block_line)
                    if match:
                        return match.group(1)
            current_block = [line]
        else:
            current_block.append(line)

    # Check final block
    for line in current_block:
        match = RE_APP_NAME.search(line)
        if match:
            return match.group(1)

    return "unknown"


# =============================================================================
# Audio Processing
# =============================================================================

def compute_levels(block: np.ndarray) -> np.ndarray:
    """Compute frequency band levels from audio block using FFT."""
    # Convert to mono
    if block.ndim == 2 and block.shape[1] > 1:
        mono = block.mean(axis=1)
    else:
        mono = block.reshape(-1)

    if mono.size == 0:
        return np.zeros(CONFIG.n_bands, dtype=np.float32)

    # Apply window
    window = get_hann_window(len(mono))
    if len(window) != len(mono):
        window = np.hanning(len(mono))

    # FFT
    spectrum = np.fft.rfft(mono * window)
    mag = np.abs(spectrum)[1:]  # Skip DC

    length = len(mag)
    if length <= 0:
        return np.zeros(CONFIG.n_bands, dtype=np.float32)

    # Compute band averages
    band_size = max(1, length // CONFIG.n_bands)
    bands = []
    for i in range(CONFIG.n_bands):
        start = i * band_size
        end = (i + 1) * band_size if i < CONFIG.n_bands - 1 else length
        if end <= start:
            bands.append(0.0)
        else:
            bands.append(float(np.mean(mag[start:end])))

    bands = np.array(bands, dtype=np.float32)
    bands = np.maximum(bands, 1e-8)

    # Convert to dB and normalize to 0-1
    bands_db = 20.0 * np.log10(bands)
    bands_db = (bands_db + 60.0) / 60.0
    bands_db = np.clip(bands_db, 0.0, 1.0)

    return bands_db


def audio_callback(
    indata: np.ndarray,
    frames: int,
    time_info: Any,
    status: sd.CallbackFlags
) -> None:
    """Audio input callback - runs in separate thread."""
    if status:
        if status.input_overflow:
            LOGGER.debug("Audio input overflow")
        if status.input_underflow:
            LOGGER.debug("Audio input underflow")

    # Clip to prevent distortion
    np.clip(indata, -1.0, 1.0, out=indata)

    # Compute RMS for AGC
    rms = float(np.sqrt(np.mean(indata ** 2))) if indata.size else 0.0

    # AGC (Automatic Gain Control)
    current_gain = STATE.agc_gain
    if rms > 1e-6:
        target_gain = CONFIG.agc_target_rms / rms
        target_gain = max(min(target_gain, CONFIG.agc_max_gain), CONFIG.agc_min_gain)

        if target_gain > current_gain:
            current_gain = current_gain + CONFIG.agc_attack * (target_gain - current_gain)
        else:
            current_gain = current_gain + CONFIG.agc_release * (target_gain - current_gain)

        STATE.agc_gain = current_gain

    # Apply gain and limiting
    indata = indata * current_gain
    np.clip(indata, -CONFIG.limit_threshold, CONFIG.limit_threshold, out=indata)

    # Compute and smooth levels
    levels = compute_levels(indata.copy())
    current_levels = STATE.levels_smooth
    STATE.levels_smooth = (CONFIG.smoothing * current_levels) + ((1.0 - CONFIG.smoothing) * levels)

    # Update activity timestamp and silence detection
    current_mean = float(np.mean(levels))
    if current_mean > 0.01:
        STATE.audio_last_active = time.time()
        STATE.silence_detected = False
    elif current_mean < 0.001:
        STATE.silence_detected = True


def pick_audio_device() -> Optional[int]:
    """Pick best available audio input device."""
    try:
        devices = sd.query_devices()
    except Exception as e:
        LOGGER.error(f"Failed to query audio devices: {e}")
        return None

    # Prefer PulseAudio device
    for idx, dev in enumerate(devices):
        name = dev["name"].lower()
        if dev["max_input_channels"] > 0 and "pulse" in name:
            LOGGER.info(f"Using audio device {idx}: {dev['name']}")
            return idx

    # Fallback: any device with input channels
    for idx, dev in enumerate(devices):
        if dev["max_input_channels"] > 0:
            LOGGER.info(f"Using fallback audio device {idx}: {dev['name']}")
            return idx

    LOGGER.error("No suitable input device found")
    return None


def start_audio_stream() -> Optional[sd.InputStream]:
    """Start audio input stream with retry logic."""
    for attempt in range(CONFIG.audio_max_retries):
        device = pick_audio_device()
        if device is None:
            LOGGER.warning(f"No audio device, attempt {attempt + 1}/{CONFIG.audio_max_retries}")
            time.sleep(CONFIG.audio_retry_delay)
            continue

        try:
            stream = sd.InputStream(
                samplerate=CONFIG.sample_rate,
                blocksize=CONFIG.block_size,
                channels=2,
                dtype="float32",
                device=device,
                callback=audio_callback,
            )
            stream.start()
            STATE.stream_active = True
            LOGGER.info(f"Audio stream started on device {device}")
            return stream
        except sd.PortAudioError as e:
            LOGGER.warning(f"PortAudio error (attempt {attempt + 1}): {e}")
            STATE.last_error = str(e)
            time.sleep(CONFIG.audio_retry_delay)
        except Exception as e:
            LOGGER.error(f"Unexpected audio stream error: {e}")
            STATE.last_error = str(e)
            time.sleep(CONFIG.audio_retry_delay)

    LOGGER.error("Failed to start audio stream after retries")
    return None


# =============================================================================
# Metadata Reader (AirPlay/Spotify)
# =============================================================================

class MetadataReader:
    """Read track metadata from Shairport Sync named pipe."""

    def __init__(self, pipe_path: str):
        self.pipe_path = pipe_path
        self.pipe: Optional[Any] = None
        self.buffer = ""
        self.last_artist: Optional[str] = None
        self.last_title: Optional[str] = None
        self.last_update: float = 0.0
        self._lock = threading.Lock()

    def _close_pipe(self) -> None:
        """Close the named pipe if open."""
        if self.pipe is not None:
            try:
                self.pipe.close()
            except OSError:
                pass
        self.pipe = None

    def _ensure_pipe(self) -> bool:
        """Ensure pipe is open and ready."""
        if self.pipe is not None:
            return True

        if not os.path.exists(self.pipe_path):
            return False

        try:
            self.pipe = open(self.pipe_path, "rb", buffering=0)
            return True
        except OSError as e:
            LOGGER.debug(f"Failed to open pipe: {e}")
            self.pipe = None
            return False

    def _handle_item_xml(self, item_xml: str) -> None:
        """Parse and handle a single metadata item."""
        m_type = RE_PIPE_TYPE.search(item_xml)
        m_code = RE_PIPE_CODE.search(item_xml)
        m_data = RE_PIPE_DATA.search(item_xml)

        if not (m_type and m_code and m_data):
            return

        try:
            type_hex = m_type.group(1).strip()
            code_hex = m_code.group(1).strip()
            type_code = bytes.fromhex(type_hex).decode("ascii", "ignore")
            code = bytes.fromhex(code_hex).decode("ascii", "ignore")
        except ValueError:
            return

        try:
            data_b64 = m_data.group(1).strip()
            payload = base64.b64decode(data_b64)
        except Exception:
            return

        now = time.time()

        with self._lock:
            if type_code == "core" and code == "asar":
                self.last_artist = payload.decode("utf-8", "ignore").strip()
                self.last_update = now
            elif type_code == "core" and code == "minm":
                self.last_title = payload.decode("utf-8", "ignore").strip()
                self.last_update = now

    def _read_chunks(self) -> None:
        """Read and process data from the pipe."""
        if not self._ensure_pipe():
            return

        try:
            while True:
                rlist, _, _ = select.select([self.pipe], [], [], 0)
                if not rlist:
                    break

                data = os.read(self.pipe.fileno(), 4096)
                if not data:
                    LOGGER.info("Metadata pipe closed by remote")
                    self._close_pipe()
                    break

                self.buffer += data.decode("utf-8", "ignore")

                # Process complete items
                while True:
                    start = self.buffer.find("<item>")
                    if start == -1:
                        # Keep some buffer for partial matches
                        self.buffer = self.buffer[-1024:]
                        break

                    end = self.buffer.find("</item>", start)
                    if end == -1:
                        if start > 0:
                            self.buffer = self.buffer[start:]
                        break

                    block = self.buffer[start:end + len("</item>")]
                    self.buffer = self.buffer[end + len("</item>"):]
                    self._handle_item_xml(block)

        except OSError as e:
            LOGGER.debug(f"Pipe read error: {e}")
            self._close_pipe()
        except Exception as e:
            LOGGER.error(f"Unexpected error reading pipe: {e}")
            self._close_pipe()

    def get_track(self) -> Tuple[Optional[str], Optional[str], float]:
        """Get current track info. Returns (artist, title, last_update)."""
        self._read_chunks()

        with self._lock:
            artist = self.last_artist or "Unknown Artist"
            title = self.last_title or "Unknown Track"
            return (artist, title, self.last_update) if (self.last_artist or self.last_title) else (None, None, 0.0)


# =============================================================================
# Sense HAT Display Functions
# =============================================================================

class DisplayController:
    """Control Sense HAT display with graceful degradation."""

    def __init__(self):
        self._sense: Optional[SenseHat] = None
        self._initialized = False
        self._init_sense_hat()

    def _init_sense_hat(self) -> None:
        """Initialize Sense HAT with error handling."""
        if not SENSE_HAT_AVAILABLE:
            LOGGER.warning("Sense HAT not available")
            return

        try:
            self._sense = SenseHat()
            self._sense.set_rotation(180)
            self._sense.low_light = True
            self._sense.clear()
            self._initialized = True
            LOGGER.info("Sense HAT initialized")
        except Exception as e:
            LOGGER.error(f"Failed to initialize Sense HAT: {e}")
            self._sense = None
            self._initialized = False

    @property
    def available(self) -> bool:
        return self._initialized and self._sense is not None

    def clear(self) -> None:
        """Clear the display."""
        if self.available:
            try:
                self._sense.clear()
            except Exception as e:
                LOGGER.error(f"Failed to clear display: {e}")

    def set_pixels(self, pixels: List[Tuple[int, int, int]]) -> None:
        """Set all pixels."""
        if self.available:
            try:
                self._sense.set_pixels(pixels)
            except Exception as e:
                LOGGER.error(f"Failed to set pixels: {e}")

    def set_pixel(self, x: int, y: int, r: int, g: int, b: int) -> None:
        """Set a single pixel."""
        if self.available:
            try:
                self._sense.set_pixel(x, y, r, g, b)
            except Exception as e:
                LOGGER.error(f"Failed to set pixel: {e}")

    def show_message(
        self,
        text: str,
        text_colour: Optional[Tuple[int, int, int]] = None,
        scroll_speed: float = CONFIG.scroll_speed
    ) -> None:
        """Scroll a message across the display."""
        if self.available:
            try:
                self._sense.show_message(
                    text,
                    text_colour=text_colour or CONFIG.track_white,
                    scroll_speed=scroll_speed
                )
            except Exception as e:
                LOGGER.error(f"Failed to show message: {e}")


# =============================================================================
# Visual Display Functions
# =============================================================================

def scroll_text(display: DisplayController, text: str, base_color: Tuple[int, int, int]) -> None:
    """Scroll track info across the display."""
    factor = get_brightness_factor()
    color = apply_brightness(base_color, factor)
    display.show_message(text, text_colour=color, scroll_speed=CONFIG.scroll_speed)


def show_airplay_icon(display: DisplayController) -> None:
    """Show AirPlay/Spotify icon temporarily."""
    display.clear()
    factor = get_brightness_factor()

    bg = apply_brightness((255, 255, 255), factor)
    blue = apply_brightness((0, 0, 255), factor)

    W = bg
    B = blue

    # Simple music note icon
    pixels = [
        W, W, B, B, B, B, W, W,
        W, B, W, W, W, W, B, W,
        B, W, W, B, B, W, W, B,
        W, W, B, W, W, B, W, W,
        W, B, W, W, W, W, B, W,
        W, W, W, B, B, W, W, W,
        W, W, B, W, W, B, W, W,
        W, W, W, W, W, W, W, W,
    ]

    display.set_pixels(pixels)
    time.sleep(1.5)


def show_no_audio_x(display: DisplayController) -> None:
    """Show 'no audio' indicator."""
    factor = get_brightness_factor()
    r, g, b = apply_brightness(CONFIG.error_red, factor)
    off = (0, 0, 0)
    pixels = [off] * 64

    coords = [
        (0, 0), (1, 1), (2, 2), (3, 3),
        (4, 4), (5, 5), (6, 6), (7, 7),
        (7, 0), (6, 1), (5, 2), (4, 3),
        (3, 4), (2, 5), (1, 6), (0, 7),
    ]

    for x, y in coords:
        pixels[y * 8 + x] = (r, g, b)

    display.set_pixels(pixels)


def ambient_step(display: DisplayController) -> None:
    """Show ambient spinner animation when no audio."""
    factor = get_brightness_factor()
    t = time.time()
    pulse = 0.6 + 0.4 * (0.5 + 0.5 * math.sin(t * 1.5))
    brightness = factor * pulse
    brightness = max(0.0, min(1.0, brightness))

    off = (0, 0, 0)
    pixels = [off] * 64

    current_index = STATE.ambient_index
    for i in range(TAIL_LENGTH):
        pos_index = (current_index - i) % len(SPINNER_PATH)
        x, y = SPINNER_PATH[pos_index]
        tail_factor = max(0.0, 1.0 - (i / float(TAIL_LENGTH)))
        total = brightness * tail_factor
        r, g, b = apply_brightness(CONFIG.spinner_color, total)
        if r or g or b:
            pixels[y * 8 + x] = (r, g, b)

    display.set_pixels(pixels)

    STATE.ambient_index = (current_index + 4) % len(SPINNER_PATH)


def draw_levels(display: DisplayController) -> None:
    """Draw audio frequency levels on the LED matrix."""
    brightness = get_brightness_factor()
    off = (0, 0, 0)
    pixels = [off] * 64

    lv = STATE.levels_smooth
    for x in range(CONFIG.n_bands):
        v = float(lv[x])
        h = int(round(v * 8))
        h = max(0, min(8, h))

        for row in range(h):
            y = 7 - row
            if row <= 2:
                base_color = CONFIG.green
            elif row <= 4:
                base_color = CONFIG.orange
            else:
                base_color = CONFIG.red

            r, g, b = apply_brightness(base_color, brightness)
            pixels[y * 8 + x] = (r, g, b)

    display.set_pixels(pixels)


# =============================================================================
# Main Application
# =============================================================================

class MusicDisplayApp:
    """Main application controller."""

    def __init__(self, verbose: bool = False):
        self.verbose = verbose
        self.reader = MetadataReader(CONFIG.pipe_path)
        self.stream: Optional[sd.InputStream] = None
        self.display = DisplayController()
        self.running = False
        self.last_connection_sound_time = 0.0

    def _play_connection_sound(self) -> None:
        """Play a subtle sound when a device connects."""
        try:
            import subprocess
            subprocess.Popen(
                ['/home/josh/Audio_Player/play-connection-sound.sh'],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL
            )
        except Exception:
            pass

    def start(self) -> None:
        """Start the application."""
        LOGGER.info("Starting Music Display + Visualizer")

        self.stream = start_audio_stream()
        self.running = True

        # Initial brightness check
        factor = get_brightness_factor()
        LOGGER.info(f"Brightness factor: {factor}")

        if self.display.available:
            self.display.clear()

        self._main_loop()

    def _main_loop(self) -> None:
        """Main event loop."""
        last_shown_track: Optional[str] = None
        last_track_display_time = 0.0
        no_audio_shown = False
        consecutive_errors = 0

        LOGGER.info("Entering main loop")

        try:
            while self.running:
                try:
                    artist, title, updated_at = self.reader.get_track()
                    now = time.time()
                    audio_recent = (now - STATE.audio_last_active) < 1.5
                    metadata_fresh = updated_at > 0 and (now - updated_at) <= CONFIG.metadata_timeout

                    # Track display logic
                    if audio_recent and metadata_fresh and (artist or title):
                        current_track = f"{artist} - {title}"

                        if current_track != last_shown_track or no_audio_shown:
                            LOGGER.info(f"Track: {current_track}")

                            # Play connection sound only when coming back from idle
                            should_play_connection_sound = (
                                (last_shown_track is None or no_audio_shown)
                                and (now - self.last_connection_sound_time) > 5.0
                            )
                            if should_play_connection_sound:
                                self._play_connection_sound()
                                self.last_connection_sound_time = now

                            show_airplay_icon(self.display)
                            base_color = CONFIG.get_app_color(detect_current_app())
                            scroll_text(self.display, current_track, base_color)

                            last_shown_track = current_track
                            last_track_display_time = time.time()
                            no_audio_shown = False

                    # No audio indicator
                    if (not audio_recent) and (now - STATE.audio_last_active) > CONFIG.no_audio_timeout:
                        if not no_audio_shown:
                            show_no_audio_x(self.display)
                            time.sleep(0.7)
                            no_audio_shown = True
                            LOGGER.info("No audio (idle)")

                    # Draw visualizer or ambient
                    if audio_recent:
                        draw_levels(self.display)
                        no_audio_shown = False
                    else:
                        ambient_step(self.display)

                    consecutive_errors = 0

                except Exception as e:
                    consecutive_errors += 1
                    LOGGER.error(f"Main loop error ({consecutive_errors}): {e}")

                    if consecutive_errors > 10:
                        LOGGER.error("Too many consecutive errors, exiting")
                        break

                    # Check if stream died
                    if self.stream is not None and not STATE.stream_active:
                        LOGGER.warning("Audio stream died, attempting restart")
                        time.sleep(1)
                        self.stream = start_audio_stream()

                time.sleep(CONFIG.check_interval)

        except KeyboardInterrupt:
            LOGGER.info("Received interrupt signal")

        self._shutdown()

    def _shutdown(self) -> None:
        """Clean shutdown."""
        LOGGER.info("Shutting down")

        self.running = False

        if self.stream is not None:
            try:
                self.stream.stop()
                self.stream.close()
                LOGGER.info("Audio stream stopped")
            except Exception as e:
                LOGGER.error(f"Error stopping stream: {e}")

        if self.display.available:
            self.display.clear()
            LOGGER.info("Display cleared")

        LOGGER.info("Shutdown complete")


def main():
    """Entry point."""
    import argparse

    parser = argparse.ArgumentParser(description="Music Display + Visualizer")
    parser.add_argument("-v", "--verbose", action="store_true", help="Verbose logging")
    args = parser.parse_args()

    if args.verbose:
        LOGGER.setLevel(logging.DEBUG)

    app = MusicDisplayApp(verbose=args.verbose)
    app.start()


if __name__ == "__main__":
    main()
