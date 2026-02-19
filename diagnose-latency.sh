#!/bin/bash
# Diagnose Shairport Sync latency issues
# Run this to identify where the delay is coming from

echo "=== Shairport Sync Latency Diagnostic ==="
echo ""

echo "[1] Shairport Sync Status:"
if systemctl is-active --quiet shairport-sync; then
    echo "  ✓ Running"
    systemctl status shairport-sync --no-pager -l | grep -E "(Active:|Main PID:)" | sed 's/^/    /'
else
    echo "  ✗ NOT running"
fi
echo ""

echo "[2] Shairport Sync Configuration:"
if [[ -f /etc/shairport-sync.conf ]]; then
    echo "  Current latency setting:"
    grep -E "^\s*latency" /etc/shairport-sync.conf | sed 's/^/    /'
    echo "  PulseAudio buffer:"
    grep "audio_backend_buffer_desired_length" /etc/shairport-sync.conf | sed 's/^/    /'
else
    echo "  ✗ Config not found at /etc/shairport-sync.conf"
fi
echo ""

echo "[3] PulseAudio Configuration:"
echo "  Default fragments:"
grep -E "^default-fragments" /etc/pulse/daemon.conf 2>/dev/null | sed 's/^/    /' || echo "    (not set, using defaults)"
echo "  Fragment size:"
grep -E "^default-fragment-size-msec" /etc/pulse/daemon.conf 2>/dev/null | sed 's/^/    /' || echo "    (not set, using defaults)"
echo ""

echo "[4] PulseAudio Sinks:"
pactl list sinks | grep -E "(Name:|Latency:|Buffer:)" | sed 's/^/    /'
echo ""

echo "[5] CamillaDSP Status:"
if pgrep -x camilladsp > /dev/null; then
    echo "  ✓ Running"
    ps aux | grep camilladsp | grep -v grep | sed 's/^/    /'
else
    echo "  ✗ NOT running"
fi
echo ""

echo "[6] Current Config File:"
CAMILLA_PROC=$(pgrep -a camilladsp 2>/dev/null | grep -oP '\S+\.yml' || echo "not found")
if [[ -n "$CAMILLA_PROC" && "$CAMILLA_PROC" != "not found" ]]; then
    echo "  Using: $CAMILLA_PROC"
    if [[ "$CAMILLA_PROC" == *"lowlatency"* ]]; then
        echo "  ✓ Using low-latency config"
    else
        echo "  ⚠ Using standard config (consider camilla-lowlatency.yml)"
    fi
    echo "  Chunksize:"
    grep "chunksize" "$CAMILLA_PROC" 2>/dev/null | sed 's/^/    /' || echo "    (not found)"
else
    echo "  Cannot determine config file"
fi
echo ""

echo "[7] Network Buffer Status:"
ss -tuln | grep -E "(5000|7000)" | sed 's/^/    /' || echo "    (no shairport ports found)"
echo ""

echo "[8] Buffer Chain Analysis:"
echo "  Estimated total latency:"
echo "    - Shairport buffer: ~0.25s (if using optimized config)"
echo "    - PulseAudio buffer: ~0.05s (if optimized)"
echo "    - CamillaDSP buffer: ~0.012s (512 samples @ 44.1kHz)"
echo "    - ALSA buffer: varies by hardware"
echo "    Total: ~0.3-0.5s (acceptable for video)"
echo ""
echo "  If seeing 30s delays, check:"
echo "    1. Network issues (WiFi congestion)"
echo "    2. PulseAudio default buffer settings"
echo "    3. Multiple audio streams queued"
echo "    4. CPU throttling: check temperature"
echo ""

echo "[9] Recent Shairport Logs (last 20 lines):"
journalctl -u shairport-sync --no-pager -n 20 2>/dev/null | tail -20 | sed 's/^/    /' || echo "    (no logs available)"
echo ""

echo "=== Diagnostic Complete ==="
echo ""
echo "To fix latency issues, run:"
echo "  sudo ./fix-shairport-latency.sh"
