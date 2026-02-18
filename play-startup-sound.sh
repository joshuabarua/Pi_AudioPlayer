#!/bin/bash
# Play startup sound when audio system initializes
# This script is called by the systemd service

VOLUME="0.3"  # 30% volume - subtle but audible

# Check if we have a startup sound
STARTUP_SOUND="/home/$USER/Audio_Player/sounds/startup.wav"

if [[ -f "$STARTUP_SOUND" ]]; then
    # Play with sox at reduced volume
    sox "$STARTUP_SOUND" -t wav - vol $VOLUME | paplay --device=camilla_sink --volume=30000 2>/dev/null &
else
    # Create a simple pleasant startup chime using sox
    # Two-tone chime: C major chord arpeggio
    sox -n -t wav - synth 0.15 sine 523.25 vol 0.25 | paplay --device=camilla_sink --volume=25000 2>/dev/null &
    sleep 0.05
    sox -n -t wav - synth 0.15 sine 659.25 vol 0.25 | paplay --device=camilla_sink --volume=25000 2>/dev/null &
    sleep 0.05
    sox -n -t wav - synth 0.3 sine 783.99 vol 0.25 fade h 0.05 0.3 0.1 | paplay --device=camilla_sink --volume=25000 2>/dev/null &
fi
