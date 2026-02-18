#!/bin/bash
# Optimize Raspberry Pi for Audio Processing
# Run with: sudo ./optimize-audio.sh

if [[ $EUID -ne 0 ]]; then
    echo "This script must be run with sudo"
    exit 1
fi

echo "=== Optimizing Raspberry Pi for Audio ==="

# 1. Set CPU governor to performance for consistent audio processing
echo "Setting CPU governor to performance..."
for cpu in /sys/devices/system/cpu/cpu[0-9]*; do
    echo performance > "$cpu/cpufreq/scaling_governor" 2>/dev/null || true
done
echo "✓ CPU governor set"

# 2. Disable screen blanking (if using HDMI display)
echo "Disabling screen blanking..."
sudo raspi-config nonint do_blanking 1 2>/dev/null || true
echo "✓ Screen blanking disabled"

# 3. Increase audio buffer sizes in kernel
echo "Optimizing kernel audio buffers..."
if ! grep -q "vm.swappiness=10" /etc/sysctl.conf; then
    echo "vm.swappiness=10" >> /etc/sysctl.conf
    sysctl -p 2>/dev/null || true
fi
echo "✓ Kernel buffers optimized"

# 4. Disable unnecessary services that might cause audio glitches
echo "Checking for conflicting services..."
systemctl disable triggerhappy.service 2>/dev/null || true
systemctl stop triggerhappy.service 2>/dev/null || true
echo "✓ Disabled triggerhappy service"

# 5. Optimize USB Audio (if applicable)
if lsusb | grep -qi "audio"; then
    echo "USB Audio detected - optimizing..."
    # Increase USB buffer size
    if ! grep -q "options snd-usb-audio nrpacks=1" /etc/modprobe.d/alsa-base.conf 2>/dev/null; then
        echo "options snd-usb-audio nrpacks=1" >> /etc/modprobe.d/alsa-base.conf
        echo "Note: Reboot required for USB audio optimization to take effect"
    fi
fi

# 6. Create a real-time priority group for audio
echo "Setting up real-time audio priorities..."
if ! grep -q "@audio" /etc/security/limits.conf; then
    cat >> /etc/security/limits.conf << 'EOF'
# Audio real-time priorities
@audio   -  rtprio     95
@audio   -  memlock    unlimited
EOF
    echo "✓ Real-time priorities configured (reboot to apply)"
fi

# 7. Optimize NetworkManager for faster reconnections
echo "Optimizing network settings..."
if [[ -f /etc/NetworkManager/NetworkManager.conf ]]; then
    if ! grep -q "wifi.scan-rand-mac-address=no" /etc/NetworkManager/NetworkManager.conf; then
        echo -e "\n[device]\nwifi.scan-rand-mac-address=no" >> /etc/NetworkManager/NetworkManager.conf
        echo "✓ NetworkManager optimized"
    fi
fi

# 8. Create tmpfs for temporary files (reduces SD card wear)
if ! grep -q "/tmp tmpfs" /etc/fstab; then
    echo "tmpfs /tmp tmpfs defaults,noatime,nosuid,size=100m 0 0" >> /etc/fstab
    echo "✓ Added tmpfs for /tmp"
fi

echo ""
echo "=== Optimization Complete ==="
echo ""
echo "Recommendations:"
echo "  1. Reboot for all changes to take effect"
echo "  2. Consider using a good quality USB power supply"
echo "  3. Keep the Pi cool for consistent performance"
echo ""
echo "To make optimizations permanent after reboot, add to /etc/rc.local:"
echo "  /home/josh/Audio_Player/optimize-audio.sh"
