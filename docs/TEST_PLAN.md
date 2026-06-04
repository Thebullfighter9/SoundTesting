# Test Plan

Use Roblox Studio with Rojo connected to `default.project.json`.

## Studio Checklist

- Open the project through Rojo.
- Press Play and confirm Demo mode starts immediately.
- Confirm the tiled field, shockwave ring, orbit points, and speaker overlays move without an asset ID.
- Press `H` and confirm the UI hides and shows.
- Press `V` and the `Style` button to cycle Field, Orbit, Marbles, and Minimal.
- Paste invalid asset input and confirm it reports `Invalid asset ID`.
- Try a private or invalid numeric asset and confirm it falls back without errors.
- Try a valid audio asset and confirm the field follows analyzer or loudness data when available.
- Press `M` or the `Mic` button and confirm Mic mode either works or gracefully falls back.
- Press `E` and the UI `Marble` button and confirm server-spawned marbles appear.
- Rapidly drop marbles and confirm rate limiting prevents spam.
- Run a multi-client local server test and confirm each player has an independent marble limit.
- Use the mobile emulator and confirm the compact UI remains usable.
- Confirm normal flow produces no Output errors.

## Manual Review

- Confirm there is no per-frame remote traffic.
- Confirm client audio frame data is not sent to the server.
- Confirm the server controls marble spawn position, velocity, size, and ownership.
