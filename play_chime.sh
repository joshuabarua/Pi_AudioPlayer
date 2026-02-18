#!/bin/bash
# Plays PSX chime quietly through camilla_sink
exec paplay --device=camilla_sink /home/josh/psx.wav --volume=6000 --fade-in-msec=400
