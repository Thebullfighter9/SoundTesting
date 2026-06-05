# Test Plan

Use Roblox Studio with Rojo connected to `default.project.json`.

## Studio Checklist

- Start a play session and confirm the premium `ArrayWaveLoadingGui` appears immediately.
- Confirm the loading screen shows animated procedural bars or dots.
- Confirm the loading screen fades out after the client is ready.
- Confirm `ArrayWaveGui` appears in `PlayerGui`.
- Confirm `ArrayWaveGui` is cloned from the static `StarterGui` asset and is not constructed by `UIController` at runtime.
- Confirm the UI does not show project keybind text.
- Confirm all UI buttons activate through `Activated`.
- Confirm the asset field is prefilled with `9043887091`.
- Use `Play Base` and confirm it attempts the base song.
- If the base song cannot play, confirm Demo fallback starts with `Base song unavailable - using demo signal`.
- Confirm the analyzer mini-strip in the UI moves.
- Confirm `Workspace/ArrayWaveClientVisuals` exists on the client.
- Confirm `GridArray` contains 441 tiles by default.
- Confirm `RowBars` contains 96 bars and peak caps are visible.
- Confirm `RadialCircle` contains 128 radial bars.
- Confirm `Shockwaves` contains the pooled ring or wave objects.
- Confirm Grid mode shows clear field waves within 3 seconds in Demo fallback.
- Confirm Row mode shows non-flat equalizer bars.
- Confirm Circle mode shows radial bars and faint expanding sound-wave rings.
- Confirm All mode shows Grid, Row, and Circle together.
- Confirm Minimal mode is restrained and clean.
- Confirm beat or transient events create a visible shockwave or ripple.
- Use `Pulse Test` and confirm it triggers a local-only shockwave.
- Use `Demo`, `Mic`, `Play Asset`, and `Stop` and confirm each reports a clear status.
- Paste invalid asset input and confirm it reports `Invalid asset ID`.
- Try a private or invalid numeric asset and confirm it falls back without errors.
- Try a valid audio asset and confirm visuals follow analyzer or loudness data when available.
- Use `Drop Marble` and confirm server-spawned marbles appear when the remote exists.
- Rapidly use `Drop Marble` and confirm rate limiting prevents spam.
- Run a multi-client local server test and confirm each player has an independent marble limit.
- Use the mobile emulator and confirm the compact UI remains usable.
- Confirm mouse, touch, and gamepad selection can operate the UI.
- Confirm project key input does not trigger audio, visualizer, marble, camera, or UI features.
- Confirm there are no per-frame remotes.
- Confirm normal flow produces no Output errors.

## Code Checks

- Confirm every Lua source file starts with `--!strict`.
- Confirm `ContextActionService`, `UserInputService`, `BindAction`, `KeyCode`, and `InputBegan` do not appear in project client code.
- Confirm legacy scheduler calls do not appear in source.
- Confirm deprecated `.Velocity` and `GetMouse` do not appear in source.
- Confirm no temporary debug UI is enabled by default.
- Confirm audio frame data is not sent to the server.
- Confirm the server controls marble spawn position, velocity, size, and ownership.
