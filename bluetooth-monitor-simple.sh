#!/bin/bash
# Simple Bluetooth connection monitor using dbus
# Plays sound when a Bluetooth audio device (A2DP) connects

CONNECTION_SOUND="/home/josh/Audio_Player/play-connection-sound.sh"
LAST_TRIGGER_TS=0
COOLDOWN_SECONDS=5

trigger_connection_sound() {
    local now
    now=$(date +%s)
    if (( now - LAST_TRIGGER_TS < COOLDOWN_SECONDS )); then
        return
    fi

    LAST_TRIGGER_TS=$now
    sleep 0.5
    "$CONNECTION_SOUND" >/dev/null 2>&1 &
}

# Monitor dbus for BlueZ connection events
dbus-monitor --system "type='signal',sender='org.bluez',interface='org.freedesktop.DBus.Properties',member='PropertiesChanged'" 2>/dev/null | while read -r line; do
    # Look for Connected property changes
    if echo "$line" | grep -q "Connected"; then
        read -r next_line
        if echo "$next_line" | grep -q "true"; then
            echo "Bluetooth audio device connected"
            trigger_connection_sound
        fi
    fi
done
