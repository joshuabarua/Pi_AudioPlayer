#!/bin/bash
# Verify Raspberry Pi optimizations are active
# Run after reboot or manually to check settings

echo "=== Verification of Audio Optimizations ==="
echo ""

ERRORS=0
WARNINGS=0

check() {
    local desc="$1"
    local cmd="$2"
    local expected="$3"
    
    result=$(eval "$cmd" 2>/dev/null)
    
    if [[ -z "$result" ]]; then
        echo "⚠ $desc: Not found (empty)"
        WARNINGS=$((WARNINGS + 1))
    elif [[ "$result" == "$expected" ]]; then
        echo "✓ $desc: $result"
    else
        echo "✗ $desc: $result (expected: $expected)"
        ERRORS=$((ERRORS + 1))
    fi
}

# Check CPU governor
CPU_GOV=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo "unknown")
if [[ "$CPU_GOV" == "performance" ]]; then
    echo "✓ CPU governor: $CPU_GOV"
else
    echo "⚠ CPU governor: $CPU_GOV (should be 'performance')"
    WARNINGS=$((WARNINGS + 1))
fi

# Check swap
SWAP=$(cat /proc/sys/vm/swappiness 2>/dev/null || echo "?")
if [[ "$SWAP" == "10" ]]; then
    echo "✓ Swappiness: $SWAP"
else
    echo "⚠ Swappiness: $SWAP (should be 10)"
    WARNINGS=$((WARNINGS + 1))
fi

# Check real-time limits
if grep -q "@audio.*rtprio.*95" /etc/security/limits.conf 2>/dev/null; then
    echo "✓ Real-time priority: configured"
else
    echo "✗ Real-time priority: not configured"
    ERRORS=$((ERRORS + 1))
fi

# Check user groups
USER_GROUPS=$(groups $USER 2>/dev/null || echo "")
if echo "$USER_GROUPS" | grep -q audio; then
    echo "✓ User in audio group: yes"
else
    echo "⚠ User in audio group: no"
    WARNINGS=$((WARNINGS + 1))
fi

# Check I2C for Sense HAT
if ls -la /dev/i2c-* 2>/dev/null | grep -q i2c; then
    echo "✓ I2C devices: present"
else
    echo "⚠ I2C devices: not found"
    WARNINGS=$((WARNINGS + 1))
fi

# Check tmpfs
if grep -q "/tmp tmpfs" /etc/fstab; then
    echo "✓ tmpfs mount: configured"
else
    echo "⚠ tmpfs mount: not configured"
    WARNINGS=$((WARNINGS + 1))
fi

# Check usb audio module
if [[ -f /etc/modprobe.d/audio-optimize.conf ]]; then
    echo "✓ USB audio optimization: configured"
else
    echo "⚠ USB audio optimization: not configured"
    WARNINGS=$((WARNINGS + 1))
fi

# Check active services
echo ""
echo "Service status:"
if pgrep -x camilladsp > /dev/null; then
    echo "  ✓ CamillaDSP: running (PID $(pgrep -x camilladsp))"
else
    echo "  ✗ CamillaDSP: not running"
    ERRORS=$((ERRORS + 1))
fi

if pgrep -f "music_display.py" > /dev/null; then
    echo "  ✓ Music Display: running"
else
    echo "  ⚠ Music Display: not running"
    WARNINGS=$((WARNINGS + 1))
fi

# Check audio devices
echo ""
echo "Audio devices:"
if aplay -l | grep -q "USB Audio CODEC"; then
    echo "  ✓ USB Audio CODEC: detected"
else
    echo "  ✗ USB Audio CODEC: not found"
    ERRORS=$((ERRORS + 1))
fi

if pactl list sinks | grep -q "camilla_sink"; then
    VOL=$(pactl list sinks | grep -A10 "Name: camilla_sink" | grep "Volume:" | head -1 | grep -oP '\d+%' | head -1)
    if [[ "$VOL" == "100%" ]]; then
        echo "  ✓ camilla_sink volume: 100%"
    else
        echo "  ⚠ camilla_sink volume: $VOL (should be 100%)"
        WARNINGS=$((WARNINGS + 1))
    fi
else
    echo "  ✗ camilla_sink: not configured"
    ERRORS=$((ERRORS + 1))
fi

# Check temperature
if [[ -f /sys/class/thermal/thermal_zone0/temp ]]; then
    TEMP=$(cat /sys/class/thermal/thermal_zone0/temp)
    TEMP_C=$((TEMP / 1000))
    echo "  CPU temperature: ${TEMP_C}°C"
    if [[ $TEMP_C -gt 70 ]]; then
        echo "    ⚠ Temperature > 70°C - consider cooling"
        WARNINGS=$((WARNINGS + 1))
    fi
fi

echo ""
echo "=== Summary ==="
echo "Errors: $ERRORS"
echo "Warnings: $WARNINGS"

if [[ $ERRORS -eq 0 ]]; then
    echo "All critical checks passed!"
    exit 0
else
    echo "Found errors that need attention."
    exit 1
fi
