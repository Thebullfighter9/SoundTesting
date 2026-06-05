# Test Plan

Use Roblox Studio with Rojo connected to `default.project.json`.

## Studio Checklist

- Start a play session and confirm `ArrayWaveLoadingGui` appears, then fades after the client is ready.
- Confirm `ArrayWaveGui` appears in `PlayerGui` from the static `StarterGui` model.
- Confirm `SongIdBox.Text` starts as `9043887091`.
- Confirm clicking the song ID selects or highlights it for replacement.
- Confirm the local avatar is hidden after spawn and respawn.
- Confirm `Workspace.CurrentCamera.CameraType` is `Scriptable`.
- Confirm the camera starts in Auto mode and slowly orbits the visualizer.
- Confirm Auto, Still, Wide, and Close camera buttons work from Tune.
- Confirm `BottomControlDock` starts collapsed.
- Confirm collapsed controls only show Base, Demo, current view, and Tune.
- Confirm Tune opens and closes without covering much of the visualizer.
- Confirm the analyzer strip is hidden by default or extremely minimal.
- Confirm all UI buttons use `GuiButton.Activated`.
- Confirm non-UI input does not trigger audio, visualizer, marble, camera, or UI behavior.
- Confirm `Workspace.ArrayWaveClientVisuals` exists on the client.
- Confirm `GridArray` contains 441 tiles.
- Confirm `RowBars` contains 96 bars.
- Confirm row peak caps exist under `AccentLights.RowPeakCaps`.
- Confirm `RadialCircle` contains 128 bars.
- Confirm pooled shockwaves, waveform rings, accent lights, and light sprays exist.

## Visual Checks

- In Demo mode, Grid tiles move with a center bass dome, diagonal waves, and beat ripples.
- Confirm `GridHeightVariance` becomes meaningfully greater than `0.04` during Demo mode.
- Confirm `GridRippleCount` increases on beat or Pulse.
- Confirm `MaxRecentGridJump` rises on strong Demo pulses.
- In Row mode, confirm bars are not flat after 5 seconds.
- Confirm adjacent row bars are continuous but not identical.
- Confirm low row bars feel heavier than high row bars.
- Confirm row peak caps jump and decay smoothly.
- Confirm `RowHeightVariance` becomes meaningfully greater than `0.04` during Demo mode.
- Confirm `RowActiveCaps` becomes greater than `0` during active music.
- In Circle mode, confirm bars are not uniform.
- Confirm the circle looks like sound radiating from the center.
- Confirm strong beats create clean outward wave rings.
- Confirm `CircleLengthVariance` becomes meaningfully greater than `0.04` during Demo mode.
- Confirm `CircleActiveWaves` increases on Pulse.
- Use `Motion +` and confirm visual movement becomes stronger.
- Use `Spray +` and confirm spray count increases without messy bursts.
- Use `Pulse` and confirm a local ripple, wave ring, accent flash, and clean spray burst.
- Confirm normal beat sprays are rare and clean.

## Audio Checks

- Use Base and confirm it attempts asset `9043887091`.
- If the asset cannot play, confirm Demo fallback starts without Output errors.
- Use Demo, Mic, Asset, and Stop and confirm each reports a clear status.
- Paste invalid asset input and confirm it reports `Invalid asset ID`.
- Try a private or unavailable numeric asset and confirm it falls back without errors.
- Confirm audio frame data stays local and is not sent to the server.

## Optional Marble Checks

- Confirm `MarbleRequested` exists when the server remote is kept.
- Fire the remote through the hidden/extra control path or a Studio test and confirm the server validates the request.
- Rapid requests should be rate-limited.

## Code Checks

- Confirm every Lua source file starts with `--!strict`.
- Confirm no project keyboard shortcut APIs appear in source.
- Confirm legacy scheduler calls do not appear in source.
- Confirm deprecated velocity and legacy mouse APIs do not appear in source.
- Confirm no temporary debug UI is enabled by default.
- Confirm there are no per-frame remotes.
- Confirm normal play produces no Output errors.
