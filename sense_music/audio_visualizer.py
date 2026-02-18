#!/usr/bin/env python3
"""
Audio Visualizer for Raspberry Pi Sense HAT.
Real-time FFT visualization of audio input.
"""

import numpy as np
import sounddevice as sd
from sense_hat import SenseHat
import time
import math

# Configuration
SAMPLE_RATE = 44100
BLOCK_SIZE = 1024
N_BANDS = 8

class AudioVisualizer:
    def __init__(self):
        self.sense = SenseHat()
        self.sense.set_rotation(180)
        self.sense.low_light = True
        self.sense.clear()
        
        self.levels = np.zeros(N_BANDS)
        self.stream = None
        
    def audio_callback(self, indata, frames, time_info, status):
        """Audio input callback."""
        if status:
            print(f"Audio status: {status}")
            
        # Convert to mono
        if indata.ndim == 2:
            mono = indata.mean(axis=1)
        else:
            mono = indata
            
        # FFT
        spectrum = np.fft.rfft(mono * np.hanning(len(mono)))
        mag = np.abs(spectrum)[1:]  # Skip DC
        
        # Compute band levels
        band_size = max(1, len(mag) // N_BANDS)
        bands = []
        for i in range(N_BANDS):
            start = i * band_size
            end = (i + 1) * band_size if i < N_BANDS - 1 else len(mag)
            if end > start:
                bands.append(float(np.mean(mag[start:end])))
            else:
                bands.append(0.0)
                
        # Convert to dB and normalize
        bands = np.array(bands)
        bands = 20 * np.log10(bands + 1e-8)
        bands = (bands + 60) / 60
        bands = np.clip(bands, 0, 1)
        
        # Smooth levels
        self.levels = 0.7 * self.levels + 0.3 * bands
        
    def draw_levels(self):
        """Draw frequency levels on LED matrix."""
        self.sense.clear()
        
        for x in range(N_BANDS):
            level = self.levels[x]
            height = int(level * 8)
            height = max(0, min(8, height))
            
            for y in range(height):
                row = 7 - y
                if y <= 2:
                    color = (0, 255, 0)  # Green
                elif y <= 4:
                    color = (255, 140, 0)  # Orange
                else:
                    color = (255, 0, 0)  # Red
                    
                self.sense.set_pixel(x, row, *color)
                
    def run(self):
        """Start the visualizer."""
        print("Starting audio visualizer...")
        
        # Find audio device
        devices = sd.query_devices()
        device_id = None
        
        for i, dev in enumerate(devices):
            if dev['max_input_channels'] > 0 and 'pulse' in dev['name'].lower():
                device_id = i
                break
                
        if device_id is None:
            print("No suitable audio device found")
            return
            
        print(f"Using device {device_id}: {devices[device_id]['name']}")
        
        try:
            self.stream = sd.InputStream(
                samplerate=SAMPLE_RATE,
                blocksize=BLOCK_SIZE,
                channels=2,
                dtype='float32',
                device=device_id,
                callback=self.audio_callback
            )
            self.stream.start()
            
            print("Visualizer running. Press Ctrl+C to stop.")
            
            while True:
                self.draw_levels()
                time.sleep(0.05)
                
        except KeyboardInterrupt:
            print("\nStopping visualizer...")
        finally:
            if self.stream:
                self.stream.stop()
                self.stream.close()
            self.sense.clear()

if __name__ == "__main__":
    visualizer = AudioVisualizer()
    visualizer.run()
