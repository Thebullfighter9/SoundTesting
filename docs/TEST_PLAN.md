# Test Plan

Use Roblox Studio with Rojo connected to `default.project.json`.

## Studio Checklist

- Open the project through Rojo.
- Start a play session and confirm the `ArrayWave` control dock appears in `PlayerGui/ArrayWaveGui`.
- Confirm the asset field is prefilled with `9043887091`.
- Use `Play Base` and confirm it attempts the base song.
- If the base song cannot play, confirm Demo fallback starts and reports the fallback status.
- Confirm `Workspace/ArrayWaveClientVisuals` exists on the client.
- Confirm `GridArray` contains 441 parts by default.
- Confirm `RowBars` contains 64 parts.
- Confirm `RadialCircle` contains 96 parts.
- Confirm Grid mode visibly animates.
- Confirm Row mode shows a readable equalizer row.
- Confirm Circle mode shows radial bars and expanding wave rings.
- Confirm All mode shows Grid, Row, and Circle together.
- Confirm Minimal mode shows a quiet reduced grid and faint circle.
- Use the UI `Pulse Test` button and confirm it triggers a local shockwave without spawning a server marble.
- Use the UI `Demo`, `Mic`, `Play Asset`, and `Stop` controls and confirm each reports a clear status.
- Paste invalid asset input and confirm it reports `Invalid asset ID`.
- Try a private or invalid numeric asset and confirm it falls back without errors.
- Try a valid audio asset and confirm the visualizer follows analyzer or loudness data when available.
- Use the UI `Drop Marble` button and confirm server-spawned marbles appear when the remote exists.
- Rapidly use `Drop Marble` and confirm rate limiting prevents spam.
- Run a multi-client local server test and confirm each player has an independent marble limit.
- Use the mobile emulator and confirm the compact UI remains usable.
- Confirm click, touch, and gamepad UI activation work through `Activated`.
- Confirm normal flow produces no Output errors.

## Keybind Removal

- Confirm no project keybinds exist.
- Confirm README contains no keyboard shortcut instructions.
- Confirm keyboard input does not trigger project audio, visualizer, marble, or UI features.
- Confirm `ContextActionService`, `UserInputService`, `BindAction`, `KeyCode`, and `InputBegan` do not appear in project client code.

## Manual Review

- Confirm there is no per-frame remote traffic.
- Confirm client audio frame data is not sent to the server.
- Confirm the server controls marble spawn position, velocity, size, and ownership.
