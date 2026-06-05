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
- `beat`
- `beatStrength`
- `transient`
- `spectralFlux`
- `centroid`
- `bands`
- `time`

The controller clamps values to `0..1` and uses `NumberUtil.sanitizeFiniteNumber` to reject NaN and infinite values.

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

## Privacy

Raw audio samples, raw microphone data, spectrum arrays, RMS, peak, band values, loudness, and beat values are never saved and never sent to the server.
