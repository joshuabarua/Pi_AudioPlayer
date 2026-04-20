#!/bin/bash
# Release USB Audio CODEC from PulseAudio for CamillaDSP

USB_CARD=$(/usr/bin/aplay -l | /usr/bin/grep "USB Audio CODEC" | /usr/bin/head -1 | /usr/bin/awk '{print $2}' | /usr/bin/tr -d ':')
if [ -n "$USB_CARD" ]; then
    USB_MODULE=$(/usr/bin/pactl list short modules 2>/dev/null | /usr/bin/awk -v card="$USB_CARD" '$2 == "module-alsa-card" && $0 ~ "device_id=\"" card "\"" {print $1; exit}')
    if [ -n "$USB_MODULE" ]; then
        /usr/bin/pactl unload-module "$USB_MODULE" 2>/dev/null || true
        echo "Released USB Audio card $USB_CARD from PulseAudio module $USB_MODULE"
    fi
fi
