# Audio Player for Raspberry Pi

A complete audio system for Raspberry Pi with Sense HAT visualization, featuring CamillaDSP for audio processing, real-time FFT visualization, and AirPlay/Spotify metadata display.

## Features

- **CamillaDSP**: Real-time audio processing with EQ and limiting
- **Sense HAT Display**: 8x8 LED matrix showing:
  - Real-time audio spectrum visualization (8-band FFT)
  - Track metadata scrolling (AirPlay/Spotify)
  - Source indicator icons
  - Auto-brightness based on time of day
- **Audio Sources**: AirPlay (Shairport Sync), Spotify (librespot)
- **Audio Output**: USB Audio CODEC (Burr-Brown PCM2902)
- **System Requirements**: Raspberry Pi with Sense HAT, PulseAudio

## Quick Start

### 1. Install System Dependencies

```bash
# Install PulseAudio, PortAudio, and ALSA development libraries
sudo apt update
sudo apt install -y pulseaudio pulseaudio-utils libportaudio2 libportaudiocpp0 portaudio19-dev

# Install CamillaDSP (if not already installed)
# Download from: https://github.com/HEnquist/camilladsp/releases
# For Raspberry Pi 4 (ARM64):
wget https://github.com/HEnquist/camilladsp/releases/latest/download/camilladsp-linux-aarch64.tar.gz
tar -xzf camilladsp-linux-aarch64.tar.gz
sudo mv camilladsp /usr/local/bin/
```

### 2. Setup PulseAudio with Camilla Sink

The `camilla_sink` is a null sink that captures all audio and routes it through CamillaDSP.

```bash
# Load the module (temporary - for testing)
pactl load-module module-null-sink sink_name=camilla_sink sink_properties='device.description="CamillaDSP"'

# Set volume to 100% (important!)
pactl set-sink-volume camilla_sink 100%

# Make it permanent by adding to ~/.config/pulse/default.pa:
echo "load-module module-null-sink sink_name=camilla_sink sink_properties='device.description=\"CamillaDSP\"'" >> ~/.config/pulse/default.pa
echo "set-sink-volume camilla_sink 100%" >> ~/.config/pulse/default.pa
```

### 3. Configure USB Audio CODEC Output

The system is configured to use a USB Audio CODEC (Burr-Brown PCM2902) for direct audio output via CamillaDSP:

**Important**: CamillaDSP needs exclusive access to the USB Audio device. PulseAudio must release it first.

```bash
# Verify USB Audio CODEC is detected
aplay -l | grep "USB Audio CODEC"

# The CamillaDSP config (sense_music/camilla.yml) is already set to use:
#   device: "hw:1,0" (USB Audio CODEC)

# Release USB Audio from PulseAudio (run this before starting CamillaDSP)
USB_CARD=$(aplay -l | grep "USB Audio CODEC" | head -1 | awk '{print $2}' | tr -d ':')
USB_MODULE=$(pactl list modules | grep -B1 "device_id=\"$USB_CARD\"" | grep "Module #" | sed 's/Module #//')
if [[ -n "$USB_MODULE" ]]; then
    pactl unload-module "$USB_MODULE"
    echo "USB Audio released from PulseAudio"
fi

# To prevent PulseAudio from grabbing USB Audio on startup, add to ~/.config/pulse/default.pa:
#   unload-module module-udev-detect
#   load-module module-udev-detect ignore_dB=1
#   set-card-profile alsa_card.usb-Burr-Brown_from_TI_USB_Audio_CODEC-00 off
```

### 4. Setup Python Environment

```bash
# Create virtual environment with system packages (needed for Sense HAT)
python3 -m venv venv --system-site-packages

# Activate and install dependencies
source venv/bin/activate
pip install -r requirements.txt
```

**Note**: The `--system-site-packages` flag is required so the venv can access the system `python3-sense-hat` package.

### 5. Test the System

```bash
# Start the complete system
./start.sh

# Or start components individually:
# Terminal 1: Start CamillaDSP
camilladsp sense_music/camilla.yml

# Terminal 2: Start music display
./venv/bin/python sense_music/music_display.py -v
```

## Usage

### Manual Start

```bash
# Start everything
./start.sh

# With verbose logging
./start.sh -v

# Test audio playback
paplay --device=camilla_sink psx.wav
```

### Systemd User Service (Auto-start on Login)

The services run as user services (not system services), which means they start when you log in and have access to your PulseAudio session:

```bash
# Install and enable user services (run as regular user, not sudo)
./install-services.sh

# Start services immediately
systemctl --user start camilladsp.service
systemctl --user start sense-music.service

# Check if services are running
systemctl --user status camilladsp.service
systemctl --user status sense-music.service

# View live logs
journalctl --user -u camilladsp.service -f
journalctl --user -u sense-music.service -f

# Stop services
systemctl --user stop camilladsp.service
systemctl --user stop sense-music.service

# Disable auto-start on login
systemctl --user disable camilladsp.service
systemctl --user disable sense-music.service

# Completely remove services
./uninstall-services.sh
```

**Run services even after logout:**
```bash
# Enable lingering (services continue running after you log out)
sudo loginctl enable-linger $USER

# To disable lingering:
sudo loginctl disable-linger $USER
```

**Services explained:**
- `camilladsp.service` - Runs CamillaDSP audio processor (needs USB Audio CODEC)
- `sense-music.service` - Runs the Sense HAT display and visualizer

### Audio Visualizer Only

If you just want the FFT visualizer without metadata:

```bash
./venv/bin/python sense_music/audio_visualizer.py
```

## Configuration

### CamillaDSP Configuration

Edit `sense_music/camilla.yml` to customize:
- Sample rate and buffer size
- EQ bands (10-band parametric EQ)
- Limiter settings
- Input/output devices

### Music Display Configuration

Configuration is in `sense_music/music_display.py` in the `Config` dataclass:
- `pipe_path`: Path to Shairport Sync metadata pipe
- `pa_device_name`: PulseAudio device to monitor
- `scroll_speed`: Text scroll speed
- `agc_*`: Automatic gain control settings
- `*_brightness`: LED brightness levels by time of day
- Colors for different apps/sources

### Shairport Sync Setup

For AirPlay metadata support:

```bash
# Install Shairport Sync
sudo apt install shairport-sync

# Edit /etc/shairport-sync.conf:
# metadata = {
#     enabled = "yes";
#     include_cover_art = "no";
#     pipe_name = "/tmp/shairport-sync-metadata";
#     pipe_timeout = 5000;
# };

# Restart service
sudo systemctl restart shairport-sync
```

## Troubleshooting

### No Audio Output

1. Check PulseAudio is running: `pulseaudio --check`
2. Verify camilla_sink exists: `pactl list sinks | grep camilla`
3. Check USB Audio CODEC is detected: `aplay -l | grep "USB Audio CODEC"`
4. Verify loopback is active: `pactl list modules | grep module-loopback`
5. Check CamillaDSP logs: `camilladsp sense_music/camilla.yml -v`
6. Verify playback device in camilla.yml matches your hardware (currently set to `hw:1,0` for USB Audio CODEC)

### Sense HAT Not Working

1. Enable I2C: `sudo raspi-config` → Interfacing Options → I2C
2. Check Sense HAT is detected: `ls /dev/i2c-*`
3. Test: `python3 -c "from sense_hat import SenseHat; s = SenseHat(); s.show_message('Hi')"`

### No Metadata Display

1. Verify Shairport Sync is configured with metadata pipe
2. Check pipe exists: `ls -la /tmp/shairport-sync-metadata`
3. Check pipe permissions (should be readable by user)

### High CPU Usage

1. Increase `chunksize` in camilla.yml
2. Reduce sample rate if acceptable
3. Disable verbose logging

## File Structure

```
.
├── start.sh                    # Master startup script
├── setup.sh                    # One-time setup script
├── play_chime.sh               # Test audio playback script
├── install-services.sh         # Install systemd services
├── uninstall-services.sh       # Remove systemd services
├── release-usb-audio.sh        # Release USB Audio from PulseAudio
├── requirements.txt            # Python dependencies
├── camilladsp.service          # Systemd service for CamillaDSP
├── sense-music.service         # Systemd service for display
├── sense_music/
│   ├── camilla.yml            # CamillaDSP configuration
│   ├── music_display.py       # Main display + visualizer app
│   └── audio_visualizer.py    # Standalone visualizer
├── camilladsp/                # CamillaDSP source (submodule)
└── venv/                      # Python virtual environment
```

## License

See individual component licenses. CamillaDSP is GPLv3.

## Credits

- CamillaDSP by HEnquist
- Sense HAT library by Raspberry Pi Foundation
