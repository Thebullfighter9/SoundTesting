# Audio

Audio stays on the client. The server never receives spectrum arrays, loudness, mic input, bands, beats, or camera state.

## Default Asset

The base song is Roblox audio asset `9043887091`. `AudioController` tries to play it on startup and the static UI pre-fills the same ID.

## Truth Modes

Each audio frame carries `analyzerTruthMode`:

- `Spectrum`: `AudioAnalyzer:GetSpectrum()` returned enough shaped bins to treat the row as a real band display.
- `LoudnessOnly`: the client has amplitude from analyzer levels or `Sound.PlaybackLoudness`, but no usable per-frequency spectrum.
- `Demo`: the local demo signal is driving the sculpture.
- `Silent`: no active signal is driving the sculpture.

In `Spectrum` mode, Row bars follow real bands and `RowSpectrumCorrelation` is written for Studio checks. In `LoudnessOnly` mode, Row becomes a broad amplitude wave. It can still look clean, but it is not a frequency visualizer.

## Diagnostics

`AudioController:GetDiagnostics()` returns audio mode, truth mode, asset ID, spectrum bin count, spectrum variance, loudness, RMS, peak, and fallback reason.

Low-rate attributes are also written to `Workspace.ArrayWaveClientVisuals` when the visual root exists, and to a client-local `PlayerGui.ArrayWaveAudioDiagnostics` folder.
