#!/bin/bash
# Monitor Bluetooth connections and play sound when device connects
# This script runs continuously and monitors bluetoothctl

CONNECTION_SOUND="/home/josh/Audio_Player/play-connection-sound.sh"
LAST_DEVICE=""
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

echo "Monitoring Bluetooth connections..."

# Monitor bluetoothctl for device connections
bluetoothctl | while read -r line; do
    # Check for connection events
    if echo "$line" | grep -q "Connection successful"; then
        echo "Bluetooth device connected!"
        trigger_connection_sound
    fi
    
    # Alternative: check for device property changes
    if echo "$line" | grep -q "\[CHG\] Device.*Connected: yes"; then
        DEVICE=$(echo "$line" | grep -oP 'Device \K[0-9A-F:]{17}')
        if [[ "$DEVICE" != "$LAST_DEVICE" ]]; then
            echo "Device $DEVICE connected"
            LAST_DEVICE="$DEVICE"
            trigger_connection_sound
        fi
    fi
done
