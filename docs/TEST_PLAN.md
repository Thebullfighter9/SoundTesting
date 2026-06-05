# Test Plan

Use Roblox Studio with Rojo connected to `default.project.json`.

## Studio Checks

- Start a play session and confirm `ArrayWaveGui` appears from the static `StarterGui` model.
- Confirm `SongIdBox.Text` starts as `9043887091`.
- Confirm the top pill shows one of `Spectrum`, `Loudness`, `Demo`, or `Silent`.
- Confirm the bottom dock starts collapsed with Base, Demo, current view, and Tune.
- Confirm all UI actions use `GuiButton.Activated`.
- Confirm no project keybinds trigger audio, camera, UI, or visualizer behavior.

## Visual Counts

- Confirm `Workspace.ArrayWaveClientVisuals` exists on the client.
- Confirm `GridArray` contains 441 tiles.
- Confirm `RowBars` contains 96 bars.
- Confirm row peak caps exist under `AccentLights.RowPeakCaps`.
- Confirm `RadialCircle` contains 128 bars.

## Truth Mode Checks

- In Spectrum mode, confirm `UsingRealSpectrum` is true, `SpectrumBinCount` is greater than 0, and `SpectrumVariance` is greater than 0.
- In Spectrum mode, switch to Row and confirm `RowSpectrumCorrelation` is not `-1`.
- In Loudness mode, confirm `UsingRealSpectrum` is false and `AnalyzerTruthMode` is `LoudnessOnly`.
- In Loudness mode, confirm Row looks like an amplitude wave, not a fake per-frequency equalizer.
- In Demo mode, confirm `AnalyzerTruthMode` is `Demo`.
- Press Stop and confirm `AnalyzerTruthMode` becomes `Silent` and the sculpture settles.

## Shape Checks

- Grid: confirm `GridHeightVariance` rises during active audio or Demo.
- Row: confirm `RowHeightVariance` rises during active audio or Demo.
- Circle: confirm `CircleLengthVariance` rises during active audio or Demo.
- Pulse: confirm `GridRippleCount` or `CircleActiveWaves` increases after pressing Pulse.

## Code Checks

- Confirm every Lua source file starts with `--!strict`.
- Confirm no keyboard shortcut APIs appear in source.
- Confirm no per-frame remotes exist.
- Confirm normal play produces no Output errors.
