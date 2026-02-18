#!/bin/bash
# Start Audio Player System
# This script starts CamillaDSP and the Sense HAT music display

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_PYTHON="$SCRIPT_DIR/venv/bin/python"
CONFIG_FILE="$SCRIPT_DIR/sense_music/camilla.yml"

echo "=== Starting Audio Player System ==="

# Check if running on Raspberry Pi
if [[ ! -f /proc/device-tree/model ]] || ! grep -q "Raspberry Pi" /proc/device-tree/model 2>/dev/null; then
    echo "Warning: This may not be a Raspberry Pi. Some features may not work."
fi

# Release USB Audio CODEC from PulseAudio so CamillaDSP can use it
echo "Checking USB Audio device..."
USB_CARD=$(aplay -l | grep "USB Audio CODEC" | head -1 | awk '{print $2}' | tr -d ':')
if [[ -n "$USB_CARD" ]]; then
    USB_MODULE=$(pactl list modules 2>/dev/null | grep -B1 "device_id=\"$USB_CARD\"" | grep "Module #" | sed 's/Module #//' || true)
    if [[ -n "$USB_MODULE" ]]; then
        echo "Releasing USB Audio from PulseAudio (module $USB_MODULE)..."
        pactl unload-module "$USB_MODULE" 2>/dev/null || true
    fi
fi

# Check if camilladsp is running, if not start it
if ! pgrep -x "camilladsp" > /dev/null; then
    echo "Starting CamillaDSP..."
    if [[ -f "$CONFIG_FILE" ]]; then
        camilladsp "$CONFIG_FILE" &
        CAMILLA_PID=$!
        echo "CamillaDSP started with PID $CAMILLA_PID"
        sleep 2
        
        # Verify it started
        if ! pgrep -x "camilladsp" > /dev/null; then
            echo "Error: CamillaDSP failed to start. Check that USB Audio CODEC is connected."
            exit 1
        fi
    else
        echo "Warning: CamillaDSP config not found at $CONFIG_FILE"
    fi
else
    echo "CamillaDSP is already running"
fi

# Check if the virtual environment exists
if [[ ! -f "$VENV_PYTHON" ]]; then
    echo "Error: Virtual environment not found at $SCRIPT_DIR/venv"
    echo "Please run: python3 -m venv venv && ./venv/bin/pip install -r requirements.txt"
    exit 1
fi

# Start the music display
echo "Starting Music Display..."
exec "$VENV_PYTHON" "$SCRIPT_DIR/sense_music/music_display.py" "$@"
