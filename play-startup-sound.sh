#!/bin/bash
# Play startup sound when audio system initializes.
# This returns immediately so it cannot delay playback start.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STARTUP_SOUND="$SCRIPT_DIR/psx.wav"
VOLUME="0.3"  # 30% volume - subtle but audible

(
    if [[ -f "$STARTUP_SOUND" ]]; then
        sox "$STARTUP_SOUND" -t wav - vol "$VOLUME" | paplay --device=camilla_sink --volume=30000 2>/dev/null
    else
        # Fallback chime if the PSX WAV is missing.
        sox -n -t wav - synth 0.15 sine 523.25 vol 0.25 | paplay --device=camilla_sink --volume=25000 2>/dev/null
        sleep 0.05
        sox -n -t wav - synth 0.15 sine 659.25 vol 0.25 | paplay --device=camilla_sink --volume=25000 2>/dev/null
        sleep 0.05
        sox -n -t wav - synth 0.3 sine 783.99 vol 0.25 fade h 0.05 0.3 0.1 | paplay --device=camilla_sink --volume=25000 2>/dev/null
    fi
) >/dev/null 2>&1 &

exit 0
