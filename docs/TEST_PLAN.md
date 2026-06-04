# Test Plan

Use Roblox Studio with Rojo connected to `default.project.json`.

## Studio Checklist

- Open the project through Rojo.
- Press Play and confirm Demo mode starts immediately.
- Confirm `Workspace/ArrayWaveClientVisuals` exists on the client.
- Confirm `GridArray` contains 441 parts by default.
- Confirm `RowBars` contains 64 parts.
- Confirm `RadialCircle` contains 96 parts.
- Confirm Grid mode visibly animates immediately.
- Confirm Row mode shows a readable equalizer row.
- Confirm Circle mode shows radial bars and expanding wave rings.
- Confirm All mode shows Grid, Row, and Circle together.
- Confirm Minimal mode shows a quiet reduced grid and faint circle.
- Press the UI `Pulse Test` button and confirm it triggers a local shockwave without spawning a server marble.
- Press `H` and confirm the UI hides and shows.
- Press `V` and confirm it cycles visualizer modes.
- Press `1`, `2`, `3`, `4`, and `5` and confirm they switch directly to Grid, Row, Circle, All, and Minimal.
- Paste invalid asset input and confirm it reports `Invalid asset ID`.
- Try a private or invalid numeric asset and confirm it falls back without errors.
- Try a valid audio asset and confirm the visualizer follows analyzer or loudness data when available.
- Press `M` or the `Mic` button and confirm Mic mode either works or gracefully falls back.
- Press `E` and the UI `Drop Marble` button and confirm server-spawned marbles appear.
- Rapidly drop marbles and confirm rate limiting prevents spam.
- Run a multi-client local server test and confirm each player has an independent marble limit.
- Use the mobile emulator and confirm the compact UI remains usable.
- Confirm normal flow produces no Output errors.

## Manual Review

- Confirm there is no per-frame remote traffic.
- Confirm client audio frame data is not sent to the server.
- Confirm the server controls marble spawn position, velocity, size, and ownership.
