# Audio

ArrayWave keeps audio analysis on the client. Audio frames are presentation data and are not replicated.

## Base Song

The default base song is Roblox audio asset `9043887091`. `AudioController` tries it on startup, and the UI song field starts with the same ID.

If the asset is blocked, private, unavailable, or the audio graph fails, the controller switches to Demo mode.

## Frame Data

Each frame exposes RMS, peak, 96 normalized bands, bass, low-mid, mid, high, air, transient energy, spectral flux, beat strength, centroid, visual energy, and time.

Analyzer and fallback values are sanitized with `NumberUtil.sanitizeFiniteNumber` and clamped to `0..1`.

## Normalization

Analyzer values are often small, so `AudioController` keeps rolling RMS, rolling peak, and per-band peak memory. It derives smooth auto-gain for the full signal and for each band, then uses a curved visual response:

```lua
visual = 1 - math.exp(-raw * gain * curve)
```

This raises quiet tracks without making loud tracks hit full motion all the time. A small visual floor is only applied when real energy is present, so silence still settles.

## Band Mapping

The visualizer samples bands with interpolation instead of integer-only indexing.

Row bars use curved band placement, a secondary harmonic band, per-bar attack/release, spring motion, and peak caps.

Grid tiles combine assigned bands with bass center motion, low-mid diagonal waves, mid sculpting, high/air edge shimmer, and pooled beat ripples.

Circle bars combine direct bands, neighboring bands, centroid focus, beat pulses, and phase offsets so energy travels around the rim instead of pulsing all bars at once.

## Demo Mode

Demo mode creates kick-like bass pulses, snare-like mid hits, high-hat shimmer, slow groove movement, and 96 non-flat bands. It is meant to exercise Grid, Row, and Circle without depending on an available asset.

## Network Boundary

Raw audio, microphone data, spectrum arrays, RMS, peak, bands, beat values, camera state, and visualizer state are never sent to the server.
