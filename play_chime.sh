#!/bin/bash
# Plays a soft AirPlay start chime through camilla_sink.

VOLUME="0.025"
PULSE_VOLUME="3000"

sox -n -t wav - synth 0.05 sine 392.00 vol "$VOLUME" fade q 0.01 0.05 0.03 | paplay --device=camilla_sink --volume="$PULSE_VOLUME" 2>/dev/null
sleep 0.04
sox -n -t wav - synth 0.07 sine 493.88 vol "$VOLUME" fade q 0.01 0.07 0.04 | paplay --device=camilla_sink --volume="$PULSE_VOLUME" 2>/dev/null
