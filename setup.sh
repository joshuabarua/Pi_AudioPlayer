#!/bin/bash
# Initial setup script for Audio Player on Raspberry Pi

echo "=== Audio Player Setup ==="
echo ""

# Check if running on Raspberry Pi
if [[ ! -f /proc/device-tree/model ]] || ! grep -q "Raspberry Pi" /proc/device-tree/model 2>/dev/null; then
    echo "Warning: This doesn't appear to be a Raspberry Pi."
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Check if Sense HAT is available
SENSE_HAT_FB=""
for fb in /sys/class/graphics/fb*; do
    if [[ -f "$fb/name" ]] && grep -q "RPi-Sense FB" "$fb/name" 2>/dev/null; then
        SENSE_HAT_FB="$fb"
        break
    fi
done

if [[ -n "$SENSE_HAT_FB" ]]; then
    echo "✓ Sense HAT detected at $(basename $SENSE_HAT_FB)"
else
    echo "⚠ Sense HAT not detected - display features won't work"
fi

echo ""
echo "Checking system dependencies..."

# Check for required commands
MISSING=()

if ! command -v camilladsp &> /dev/null; then
    MISSING+=("camilladsp")
fi

if ! command -v pactl &> /dev/null; then
    MISSING+=("pulseaudio-utils")
fi

if ! command -v python3 &> /dev/null; then
    MISSING+=("python3")
fi

if [[ ${#MISSING[@]} -gt 0 ]]; then
    echo "⚠ Missing dependencies: ${MISSING[*]}"
    echo ""
    echo "Install them with:"
    echo "  sudo apt update"
    echo "  sudo apt install -y pulseaudio pulseaudio-utils python3 python3-venv python3-pip"
    echo ""
    echo "For CamillaDSP, download from:"
    echo "  https://github.com/HEnquist/camilladsp/releases"
    exit 1
fi

echo "✓ All system dependencies found"

# Check for camilla_sink
echo ""
echo "Checking PulseAudio configuration..."
if pactl list sinks | grep -q "camilla_sink"; then
    echo "✓ camilla_sink already configured"
    # Ensure volume is at 100%
    pactl set-sink-volume camilla_sink 100% 2>/dev/null || true
else
    echo "⚠ camilla_sink not found. Creating..."
    pactl load-module module-null-sink sink_name=camilla_sink sink_properties='device.description="CamillaDSP"'
    # Set volume to 100%
    pactl set-sink-volume camilla_sink 100%
    echo "✓ camilla_sink created with volume at 100%"
    echo ""
    echo "To make this permanent, add to ~/.config/pulse/default.pa:"
    echo "  load-module module-null-sink sink_name=camilla_sink sink_properties='device.description=\"CamillaDSP\"'"
    echo "  set-sink-volume camilla_sink 100%"
fi

# Check for USB Audio CODEC
echo ""
echo "Checking USB Audio CODEC..."
USB_CARD=$(aplay -l | grep "USB Audio CODEC" | head -1 | awk '{print $2}' | tr -d ':')
if [[ -n "$USB_CARD" ]]; then
    echo "✓ USB Audio CODEC found on card $USB_CARD"
    
    # Check if PulseAudio has the USB Audio card loaded (this blocks CamillaDSP)
    USB_MODULE=$(pactl list modules | grep -B1 "device_id=\"$USB_CARD\"" | grep "Module #" | sed 's/Module #//')
    if [[ -n "$USB_MODULE" ]]; then
        echo "⚠ PulseAudio is managing USB Audio (module $USB_MODULE). Unloading to allow CamillaDSP access..."
        pactl unload-module "$USB_MODULE" 2>/dev/null || echo "   Note: Module may already be unloaded"
        echo "✓ USB Audio released from PulseAudio"
        echo ""
        echo "To prevent PulseAudio from grabbing the USB Audio device on startup,"
        echo "add to ~/.config/pulse/default.pa:"
        echo "  unload-module module-udev-detect"
        echo "  load-module module-udev-detect ignore_dB=1"
        echo "  set-card-profile alsa_card.usb-Burr-Brown_from_TI_USB_Audio_CODEC-00 off"
    else
        echo "✓ USB Audio available for CamillaDSP"
    fi
else
    echo "⚠ USB Audio CODEC not found. Checking available cards:"
    aplay -l | grep -E "^card" | head -5
fi

# Setup Python venv
echo ""
echo "Setting up Python environment..."
if [[ ! -d "venv" ]]; then
    echo "Creating virtual environment with system packages..."
    python3 -m venv venv --system-site-packages
    echo "✓ Virtual environment created"
else
    # Check if venv has system site-packages access
    if ! ./venv/bin/python -c "import sense_hat" 2>/dev/null; then
        echo "⚠ Existing venv cannot access Sense HAT. Recreating..."
        rm -rf venv
        python3 -m venv venv --system-site-packages
        echo "✓ Virtual environment recreated with system packages"
    else
        echo "✓ Virtual environment exists with Sense HAT access"
    fi
fi

echo "Installing Python dependencies..."
./venv/bin/pip install -q -r requirements.txt
echo "✓ Dependencies installed"

# Verify installation
echo ""
echo "Verifying installation..."
if ./venv/bin/python -c "import numpy, sounddevice; print('✓ Python dependencies OK')" 2>/dev/null; then
    :
else
    echo "✗ Python dependency check failed"
    exit 1
fi

if camilladsp sense_music/camilla.yml --check &>/dev/null; then
    echo "✓ CamillaDSP configuration OK"
else
    echo "⚠ CamillaDSP configuration check had issues (may be due to PulseAudio holding device)"
    echo "   This is normal - configuration will work once USB Audio is released"
fi

echo ""
echo "=== Setup Complete ==="
echo ""
echo "To start the audio player:"
echo "  ./start.sh"
echo ""
echo "To install as a system service (auto-start on boot):"
echo "  sudo ./install-services.sh"
echo ""
echo "To test audio playback:"
echo "  paplay --device=camilla_sink psx.wav"
