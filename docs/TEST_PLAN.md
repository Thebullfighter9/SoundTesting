# Test Notes

Run through this in Studio with Rojo connected.

## Startup

- Start Play.
- `ArrayWaveGui` should come from `StarterGui`, not from runtime-created UI.
- The song box should start with `9043887091`.
- The top pill should show `Spectrum`, `Loudness`, `Demo`, or `Silent`.
- The bottom dock should start collapsed.
- There should be no keyboard shortcuts for the project controls.

## Visual Parts

Check the client workspace:

- `Workspace.ArrayWaveClientVisuals.GridArray` has 441 tiles.
- `Workspace.ArrayWaveClientVisuals.RowBars` has 96 bars.
- `Workspace.ArrayWaveClientVisuals.AccentLights.RowPeakCaps` exists.
- `Workspace.ArrayWaveClientVisuals.RadialCircle` has 128 bars.

Switch through `Grid`, `Row`, and `Circle`. Each mode should show visible parts.

## Audio Truth

For the base track `9043887091`, read the current diagnostics.

If the label says `Spectrum`:

- `UsingRealSpectrum` should be true.
- `SpectrumBinCount` should be above zero.
- `SpectrumVariance` should be above zero.
- In Row mode, `RowSpectrumCorrelation` should not be `-1`.

If the label says `Loudness`:

- `UsingRealSpectrum` should be false.
- `AnalyzerTruthMode` should be `LoudnessOnly`.
- Row should look like an amplitude wave, not fake frequency bars.

If the label says `Demo`, the local demo signal is running.

Press `Stop`. The label should become `Silent`, and the field should settle.

## Quick Code Checks

- Lua files start with `--!strict`.
- No project keybind APIs are used.
- No per-frame remotes exist.
- Play mode should not print runtime errors.
