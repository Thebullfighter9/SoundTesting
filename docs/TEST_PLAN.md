# Test Plan

Use Roblox Studio with Rojo connected to `default.project.json`.

## Studio Checklist

- Open the project through Rojo.
- Press Play and confirm Demo mode starts immediately.
- Confirm the field pins, surface tiles, wave ring, and orbit masses move without an asset ID.
- Press `B` and the `Preset` button to cycle Field, Wave, Orbit, and Still.
- Paste invalid asset input and confirm it reports `Invalid asset ID`.
- Try a private or invalid numeric asset and confirm it falls back without errors.
- Try a valid audio asset and confirm the field follows analyzer or loudness data when available.
- Press `M` or the `Mic` button and confirm Mic mode either works or gracefully falls back.
- Press `E` and the UI `Send Pulse` button and confirm server-spawned pulse masses appear.
- Rapidly send pulses and confirm rate limiting prevents spam.
- Run a multi-client local server test and confirm each player has an independent pulse limit.
- Use the mobile emulator and confirm the compact UI remains usable.
- Confirm normal flow produces no Output errors.

## Manual Review

- Confirm there is no per-frame remote traffic.
- Confirm client audio frame data is not sent to the server.
- Confirm the server controls pulse spawn position, velocity, size, and ownership.
