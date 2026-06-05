# Audio Notes

Audio analysis is client-only. Nothing sends spectrum, loudness, mic data, bands, beats, or camera state to the server.

The base song is `9043887091`. `AudioController` tries that asset on startup, and the song box starts with the same ID.

## Signal Labels

`AudioController` marks every frame with one truth mode:

- `Spectrum`: usable `AudioAnalyzer:GetSpectrum()` data came back.
- `LoudnessOnly`: there is volume data, but no usable spectrum.
- `Demo`: the local demo signal is running.
- `Silent`: the field should settle.

This matters most in Row mode. When the label says `Spectrum`, the row bars are mapped to real bands. When it says `Loudness`, the row is only an amplitude wave. It can look good, but it cannot match the song frequency-by-frequency.

## Diagnostics

Use `AudioController:GetDiagnostics()` when checking the current source. It returns:

- audio mode
- truth mode
- asset ID
- real-spectrum flag
- spectrum bin count
- spectrum variance
- loudness, RMS, and peak
- fallback reason

The same values are also written at a low rate to `Workspace.ArrayWaveClientVisuals` when the visual root exists.
