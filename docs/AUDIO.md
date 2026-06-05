# Audio

ArrayWave keeps audio analysis local to the client. Audio frames are presentation data and do not cross the network.

## Base Song

The default base song is Roblox audio asset `9043887091`. `AudioController` attempts this asset automatically on startup, and the UI asset field is prefilled with the same ID.

If the asset is private, blocked for the experience, unavailable, or the audio graph fails, the controller reports `Base song unavailable - using demo signal` and starts Demo mode without errors.

## Audio Frame

Each frame exposes:

- `rms`
- `peak`
- `bass`
- `lowMid`
- `mid`
- `high`
- `air`
- `visualEnergy`
- `beat`
- `beatStrength`
- `transient`
- `spectralFlux`
- `centroid`
- `bands`
- `time`

The controller clamps values to `0..1` and uses `NumberUtil.sanitizeFiniteNumber` to reject NaN and infinite values.

## Visual Gain

Analyzer values can be small even when the audible track feels active. `AudioController` keeps rolling peak and RMS envelopes, derives a clamped `autoGain` between `1.0` and `MAX_VISUAL_GAIN`, and applies a curved response of `1 - exp(-value * 2.4)` before smoothing visual bands.

This gain staging raises quiet tracks without letting loud tracks explode the scene. The final frame exposes normalized bands and `visualEnergy` for grid motion, camera movement/FOV, UI meters, and pooled burst effects.

## Modular Audio Path

Asset mode first attempts a modular audio graph:

- `AudioPlayer`
- `AudioAnalyzer`
- `Wire`
- `AudioDeviceOutput`

Mic mode attempts:

- `AudioDeviceInput`
- `AudioAnalyzer`
- `Wire`

Graph construction, property assignment, wiring, playback, and analyzer reads are wrapped with `pcall`. Analyzer reads prefer `RmsLevel`, `PeakLevel`, and `GetSpectrum()` when supported.

## Fallbacks

If spectrum data is unavailable, the controller synthesizes detailed bands from RMS, peak, and time so the visualizer still has a musical shape.

If the modular asset path cannot play or analyze, the client tries a local `Sound` with `SoundId = "rbxassetid://9043887091"` for the base song or the requested asset ID, then reads `PlaybackLoudness`.

If the classic `Sound` path also fails, or if microphone support is unavailable, Demo mode starts. Demo mode creates kick-like bass pulses, snare-like mid hits, high-hat shimmer, slow groove variation, and 96 non-flat bands.

## Beat Detection

The analysis pipeline maintains:

- attack/release-smoothed bands
- short and long energy envelopes
- positive spectral flux
- transient energy from envelope difference
- normalized spectral centroid
- dynamic threshold and cooldown for beat detection

Bass bands use heavier smoothing, while high and air bands respond faster.

`beatStrength`, `transient`, and `spectralFlux` drive crisp visual impulses. Bass pulls motion toward the center grid dome, low-mid creates rolling diagonal waves, mid drives readable tile/bar variation, high and air add edge shimmer and light sprays, and centroid shifts emphasis from center-heavy to edge-heavy motion.

## Privacy

Raw audio samples, raw microphone data, spectrum arrays, RMS, peak, band values, loudness, beat values, camera state, and visualizer state are never saved and never sent to the server.
