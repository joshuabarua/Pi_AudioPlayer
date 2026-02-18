#!/bin/bash
# Health check script for Audio Player
# Returns exit code 0 if healthy, 1 if issues found

ERRORS=0

echo "=== Audio Player Health Check ==="
echo ""

# Check if CamillaDSP is running
if pgrep -x camilladsp > /dev/null; then
    echo "✓ CamillaDSP is running"
else
    echo "✗ CamillaDSP is NOT running"
    ERRORS=$((ERRORS + 1))
fi

# Check if Music Display is running
if pgrep -f "music_display.py" > /dev/null; then
    echo "✓ Music Display is running"
else
    echo "✗ Music Display is NOT running"
    ERRORS=$((ERRORS + 1))
fi

# Check if USB Audio CODEC is accessible
USB_CARD=$(aplay -l | grep "USB Audio CODEC" | head -1 | awk '{print $2}' | tr -d ':')
if [[ -n "$USB_CARD" ]]; then
    # Check if device is busy (PulseAudio has it)
    if lsof /dev/snd/pcmC${USB_CARD}D0p 2>/dev/null | grep -q pulseaudio; then
        echo "⚠ USB Audio CODEC is held by PulseAudio (CamillaDSP may fail)"
    else
        echo "✓ USB Audio CODEC is available"
    fi
else
    echo "✗ USB Audio CODEC not found"
    ERRORS=$((ERRORS + 1))
fi

# Check if camilla_sink exists
if pactl list sinks | grep -q "camilla_sink"; then
    echo "✓ camilla_sink is configured"
    
    # Check volume
    VOL=$(pactl list sinks | grep -A10 "Name: camilla_sink" | grep "Volume:" | head -1 | grep -oP '\d+%' | head -1)
    if [[ "$VOL" == "100%" ]]; then
        echo "✓ camilla_sink volume is at 100%"
    else
        echo "⚠ camilla_sink volume is at $VOL (should be 100%)"
    fi
else
    echo "✗ camilla_sink is NOT configured"
    ERRORS=$((ERRORS + 1))
fi

# Check if Sense HAT is accessible
if python3 -c "from sense_hat import SenseHat; s = SenseHat(); s.clear()" 2>/dev/null; then
    echo "✓ Sense HAT is accessible"
else
    echo "⚠ Sense HAT is NOT accessible (display won't work)"
fi

# Check CPU temperature
if [[ -f /sys/class/thermal/thermal_zone0/temp ]]; then
    TEMP=$(cat /sys/class/thermal/thermal_zone0/temp)
    TEMP_C=$((TEMP / 1000))
    if [[ $TEMP_C -gt 80 ]]; then
        echo "⚠ CPU temperature is high: ${TEMP_C}°C"
    else
        echo "✓ CPU temperature is normal: ${TEMP_C}°C"
    fi
fi

# Check disk space
DISK_USAGE=$(df / | tail -1 | awk '{print $5}' | tr -d '%')
if [[ $DISK_USAGE -gt 90 ]]; then
    echo "⚠ Disk usage is high: ${DISK_USAGE}%"
else
    echo "✓ Disk usage is OK: ${DISK_USAGE}%"
fi

echo ""
if [[ $ERRORS -eq 0 ]]; then
    echo "=== All checks passed! ==="
    exit 0
else
    echo "=== Found $ERRORS issue(s) ==="
    echo "Run './start.sh' to restart services"
    exit 1
fi
