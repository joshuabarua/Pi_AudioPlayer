#!/bin/bash
# Play connection sound when a device connects (AirPlay/Bluetooth)
# Called by device connection hooks

VOLUME="0.25"  # 25% volume - very subtle

# Simple pleasant connection sound - ascending two tones
(
    sox -n -t wav - synth 0.1 sine 880 vol $VOLUME | paplay --device=camilla_sink --volume=22000 2>/dev/null
    sleep 0.1
    sox -n -t wav - synth 0.2 sine 1100 vol $VOLUME fade h 0.05 0.2 0.1 | paplay --device=camilla_sink --volume=22000 2>/dev/null
) &
