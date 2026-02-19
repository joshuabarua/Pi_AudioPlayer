#!/bin/bash
# Optimize Raspberry Pi for Audio Processing
# Run with: sudo ./optimize-audio.sh

set -e

if [[ $EUID -ne 0 ]]; then
    echo "This script must be run with sudo"
    exit 1
fi

echo "=== Optimizing Raspberry Pi for Audio ==="
echo ""

# 1. CPU Performance Tuning
echo "[1/10] CPU governor and performance..."
for cpu in /sys/devices/system/cpu/cpu[0-9]*; do
    GOVERNOR=$(cat "$cpu/cpufreq/scaling_governor" 2>/dev/null || echo "unknown")
    if [[ "$GOVERNOR" != "performance" ]]; then
        echo performance > "$cpu/cpufreq/scaling_governor" 2>/dev/null || true
    fi
done
echo "✓ CPU governor set to performance"

# 2. Disable screen blanking (saves power, prevents HDMI interrupts)
echo "[2/10] Disabling screen blanking..."
if command -v raspi-config &> /dev/null; then
    raspi-config nonint do_blanking 1 2>/dev/null || true
fi
echo "✓ Screen blanking disabled"

# 3. Kernel parameter tuning for audio
echo "[3/10] Tuning kernel parameters..."
SYSCTL_OPTS=(
    "vm.swappiness=10"
    "vm.dirty_ratio=10"
    "vm.dirty_background_ratio=5"
    "kernel.sched_rt_runtime_us=980000"
)
for opt in "${SYSCTL_OPTS[@]}"; do
    KEY="${opt%%=*}"
    if ! grep -q "^$KEY" /etc/sysctl.conf 2>/dev/null; then
        echo "$opt" >> /etc/sysctl.conf
    fi
done
sysctl -p 2>/dev/null || true
echo "✓ Kernel tuned"

# 4. Disable unnecessary services
echo "[4/10] Disabling conflicting services..."
UNNEEDED_SERVICES=(
    "triggerhappy.service"
    "bluetooth.service"  # Only if you don't use Bluetooth audio
    "avahi-daemon.service"  # Optional: if you don't need mDNS
)
for svc in "${UNNEEDED_SERVICES[@]}"; do
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
        systemctl disable "$svc" 2>/dev/null || true
        systemctl stop "$svc" 2>/dev/null || true
        echo "  - Disabled $svc"
    fi
done
echo "✓ Services optimized"

# 5. USB Audio optimization
echo "[5/10] USB Audio optimization..."
if lsusb | grep -qi "audio"; then
    MODPROBE_CONF="/etc/modprobe.d/audio-optimize.conf"
    if ! grep -q "options snd-usb-audio" "$MODPROBE_CONF" 2>/dev/null; then
        cat > "$MODPROBE_CONF" << 'EOF'
# Audio optimization for USB sound cards
options snd-usb-audio nrpacks=2
options snd-usb-audio buffering=1
options snd-usb-audio implicit_fb=1
EOF
        echo "  - Created $MODPROBE_CONF (reboot required)"
    fi
    echo "✓ USB Audio configured"
fi

# 6. Real-time scheduling for audio user
echo "[6/10] Setting up real-time audio priorities..."
if ! grep -q "@audio" /etc/security/limits.conf 2>/dev/null; then
    cat >> /etc/security/limits.conf << 'EOF'
# Audio real-time priorities
@audio   -  rtprio     95
@audio   -  memlock    unlimited
@audio   -  nice      -10
EOF
    echo "  - Added to /etc/security/limits.conf"
fi
echo "✓ Real-time scheduling configured"

# 7. Add user to audio group
echo "[7/10] Ensuring user is in audio group..."
if ! groups $SUDO_USER 2>/dev/null | grep -q audio; then
    usermod -a -G audio "$SUDO_USER" 2>/dev/null || true
    echo "  - Added $SUDO_USER to audio group (reboot required)"
fi
echo "✓ User permissions configured"

# 8. I/O scheduler optimization
echo "[8/10] Setting I/O scheduler for low latency..."
if [[ -f /sys/block/mmcblk0/queue/scheduler ]]; then
    echo "deadline" > /sys/block/mmcblk0/queue/scheduler 2>/dev/null || true
    echo "  - Set deadline scheduler (SD card)"
elif [[ -f /sys/block/sda/queue/scheduler ]]; then
    echo "deadline" > /sys/block/sda/queue/scheduler 2>/dev/null || true
    echo "  - Set deadline scheduler (USB drive)"
fi
echo "✓ I/O scheduler optimized"

# 9. Network tuning for faster device discovery
echo "[9/10] Network optimization..."
if [[ -f /etc/sysctl.conf ]]; then
    if ! grep -q "net.ipv4.tcp_congestion_control" /etc/sysctl.conf; then
        echo "net.ipv4.tcp_congestion_control = cubic" >> /etc/sysctl.conf
        sysctl -w net.ipv4.tcp_congestion_control=cubic 2>/dev/null || true
    fi
    if ! grep -q "net.core.rmem_max" /etc/sysctl.conf; then
        echo "net.core.rmem_max = 26214400" >> /etc/sysctl.conf
        echo "net.core.wmem_max = 26214400" >> /etc/sysctl.conf
    fi
fi
echo "✓ Network tuned"

# 10. Create tmpfs mounts for audio cache
echo "[10/10] Setting up tmpfs for temporary files..."
TMPFS_MOUNTS=(
    "/tmp 200m"
    "/var/tmp 100m"
)
for mount in "${TMPFS_MOUNTS[@]}"; do
    DIR="${mount%%[[:space:]]*}"
    grep -q "$DIR tmpfs" /etc/fstab 2>/dev/null || echo "$DIR tmpfs tmpfs defaults,noatime,nosuid,size=${mount##*[[:space:]]} 0 0" >> /etc/fstab
done
echo "✓ tmpfs configured"

echo ""
echo "=== Optimization Complete ==="
echo ""
echo "Changes applied. Some require a reboot:"
echo "  - USB audio module changes"
echo "  - Real-time scheduling (limits.conf)"
echo "  - I/O scheduler"
echo ""
echo "To finish optimization, reboot and then run:"
echo "  sudo ./verify-optimizations.sh"
echo ""
echo "For immediate testing without reboot, try:"
echo "  sudo sysctl -p"
echo "  sudo usermod -a -G audio $USER"
echo ""
echo "Note: Current user ($SUDO_USER) may need to log out/in for group changes."

