#!/bin/bash
# Performance monitor for Audio Player
# Shows CPU usage, temperature, and memory usage

echo "=== Audio Player Performance Monitor ==="
echo "Press Ctrl+C to stop"
echo ""

while true; do
    # Get CPU usage
    CPU=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
    
    # Get temperature (if available)
    if [[ -f /sys/class/thermal/thermal_zone0/temp ]]; then
        TEMP=$(cat /sys/class/thermal/thermal_zone0/temp)
        TEMP_C=$((TEMP / 1000))
        TEMP_STR="${TEMP_C}°C"
    else
        TEMP_STR="N/A"
    fi
    
    # Get memory usage
    MEM=$(free | grep Mem | awk '{printf "%.1f%%", $3/$2 * 100.0}')
    
    # Get CamillaDSP CPU usage
    CAMILLA_CPU=$(ps -p $(pgrep -x camilladsp) -o %cpu= 2>/dev/null || echo "0.0")
    
    # Get music display CPU usage
    DISPLAY_CPU=$(ps -p $(pgrep -f "music_display.py") -o %cpu= 2>/dev/null || echo "0.0")
    
    # Clear line and print
    printf "\rCPU: %5.1f%% | Temp: %s | Mem: %s | CamillaDSP: %5.1f%% | Display: %5.1f%%" \
        "$CPU" "$TEMP_STR" "$MEM" "$CAMILLA_CPU" "$DISPLAY_CPU"
    
    sleep 2
done
