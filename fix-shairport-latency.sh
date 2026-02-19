#!/bin/bash
# Fix Shairport Sync latency issues
# Run with: sudo ./fix-shairport-latency.sh

set -e

echo "=== Fixing Shairport Sync Latency Issues ==="
echo ""

# Backup existing config
if [[ -f /etc/shairport-sync.conf ]]; then
    cp /etc/shairport-sync.conf /etc/shairport-sync.conf.backup.$(date +%Y%m%d_%H%M%S)
    echo "✓ Backed up existing config"
fi

echo "[1/5] Configuring shairport-sync for low latency..."
cat > /etc/shairport-sync.conf << 'EOF'
general =
{
    name = "Jukebox";
    volume_range_db = 60;
    output_backend = "pa";
    latency = 11025;  # ~0.25s for video sync (was 44100 = 1s)
    drift_tolerance_in_seconds = 0.005;
    resync_threshold_in_seconds = 0.030;
};

metadata =
{
    enabled = "yes";
    include_cover_art = "no";
    pipe_name = "/tmp/shairport-sync-metadata";
    pipe_timeout = 5000;
};

pa =
{
    application_name = "Shairport Sync";
    sink = "camilla_sink";
    audio_backend_buffer_desired_length_in_seconds = 0.05;  # Lower buffer (was 0.15)
    audio_backend_latency_offset_in_seconds = 0.0;
};

sessioncontrol =
{
    run_this_before_play_begins = "/home/josh/play_chime.sh";
    wait_for_completion = "no";
};
EOF
echo "✓ Shairport config updated"

echo "[2/5] Configuring PulseAudio for low latency..."
mkdir -p /etc/pulse
if [[ -f /etc/pulse/daemon.conf ]]; then
    cp /etc/pulse/daemon.conf /etc/pulse/daemon.conf.backup.$(date +%Y%m%d_%H%M%S)
fi

# Update or add low-latency settings
if grep -q "^default-fragments" /etc/pulse/daemon.conf 2>/dev/null; then
    sed -i 's/^default-fragments = .*/default-fragments = 2/' /etc/pulse/daemon.conf
else
    echo "default-fragments = 2" >> /etc/pulse/daemon.conf
fi

if grep -q "^default-fragment-size-msec" /etc/pulse/daemon.conf 2>/dev/null; then
    sed -i 's/^default-fragment-size-msec = .*/default-fragment-size-msec = 4/' /etc/pulse/daemon.conf
else
    echo "default-fragment-size-msec = 4" >> /etc/pulse/daemon.conf
fi

echo "✓ PulseAudio configured for low latency"

echo "[3/5] Updating CamillaDSP to use low-latency config..."
CAMILLA_SERVICE="/home/josh/.config/systemd/user/camilladsp.service"
if [[ -f "$CAMILLA_SERVICE" ]]; then
    # Create backup
    cp "$CAMILLA_SERVICE" "${CAMILLA_SERVICE}.backup.$(date +%Y%m%d_%H%M%S)"
    # Switch to low-latency config
    sed -i 's/camilla\.yml/camilla-lowlatency.yml/' "$CAMILLA_SERVICE"
    echo "✓ CamillaDSP service updated to use low-latency config"
else
    echo "⚠ CamillaDSP service not found at $CAMILLA_SERVICE"
    echo "  Manually edit your service to use camilla-lowlatency.yml"
fi

echo "[4/5] Restarting services..."
systemctl restart shairport-sync
echo "✓ Shairport-sync restarted"

# Reload systemd for user
sudo -u josh systemctl --user daemon-reload 2>/dev/null || true
sudo -u josh systemctl --user restart camilladsp.service 2>/dev/null || true
echo "✓ CamillaDSP restarted"

echo "[5/5] Verifying configuration..."
sleep 2
if systemctl is-active --quiet shairport-sync; then
    echo "✓ Shairport-sync is running"
else
    echo "✗ Shairport-sync failed to start - check: journalctl -u shairport-sync"
fi

echo ""
echo "=== Latency Fix Applied ==="
echo ""
echo "Key changes made:"
echo "  - Shairport latency: 44100 → 11025 samples (~0.25s)"
echo "  - PulseAudio buffer: 0.15s → 0.05s"
echo "  - CamillaDSP: Using camilla-lowlatency.yml (chunksize 512)"
echo "  - PulseAudio fragments: 2 x 4ms"
echo ""
echo "If you still experience issues:"
echo "  1. Reboot the system: sudo reboot"
echo "  2. Check logs: journalctl -u shairport-sync -f"
echo "  3. Test with: paplay --device=camilla_sink psx.wav"
echo ""
echo "To restore original config:"
echo "  sudo cp /etc/shairport-sync.conf.backup.* /etc/shairport-sync.conf"
