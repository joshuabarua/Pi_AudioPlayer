#!/bin/bash
# Simple Bluetooth connection monitor using dbus
# Plays sound when a Bluetooth audio device (A2DP) connects

CONNECTION_SOUND="/home/josh/Audio_Player/play-connection-sound.sh"

# Monitor dbus for BlueZ connection events
dbus-monitor --system "type='signal',sender='org.bluez',interface='org.freedesktop.DBus.Properties',member='PropertiesChanged'" 2>/dev/null | while read -r line; do
    # Look for Connected property changes
    if echo "$line" | grep -q "Connected"; then
        read -r next_line
        if echo "$next_line" | grep -q "true"; then
            echo "Bluetooth audio device connected"
            sleep 0.5
            "$CONNECTION_SOUND" 2>/dev/null &
        fi
    fi
done
