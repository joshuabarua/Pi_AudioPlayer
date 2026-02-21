#!/bin/bash
# Play a softer connection sound when a device connects.

VOLUME="0.03"
PULSE_VOLUME="3500"

sox -n -t wav - synth 0.06 sine 440 vol "$VOLUME" fade q 0.01 0.06 0.04 | paplay --device=camilla_sink --volume="$PULSE_VOLUME" 2>/dev/null
sleep 0.04
sox -n -t wav - synth 0.08 sine 554.37 vol "$VOLUME" fade q 0.01 0.08 0.05 | paplay --device=camilla_sink --volume="$PULSE_VOLUME" 2>/dev/null
