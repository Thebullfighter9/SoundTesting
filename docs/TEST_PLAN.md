# Test Plan

Use Roblox Studio with Rojo connected to `default.project.json`.

## Studio Checklist

- Open the project through Rojo.
- Press Play and confirm Demo mode starts immediately.
- Confirm bars move without an asset ID.
- Confirm the ring, orbit objects, speaker cones, flash, particles, and readouts respond to Demo mode.
- Press `B` and the `Next Preset` button to cycle all presets.
- Paste invalid asset input and confirm it reports `Invalid asset ID`.
- Try a private or invalid numeric audio asset and confirm it falls back without errors.
- Try a valid audio asset and confirm the visualizer follows analyzer or loudness data when available.
- Press `M` or the `Mic` button and confirm Mic mode either works or gracefully falls back.
- Press `E` and the UI `Drop Beat Orb` button and confirm server-spawned orbs appear.
- Press the beat-orb controls rapidly and confirm rate limiting prevents spam.
- Run a multi-client local server test and confirm each player has an independent active-orb limit.
- Use the mobile emulator and confirm UI buttons remain readable and usable.
- Open the Output and Developer Console and confirm normal flow produces no errors.

## Manual Review

- Confirm no per-frame remote traffic is generated.
- Confirm client audio frame data is not sent to the server.
- Confirm server orb spawning uses server position, server velocity, server sizing, and server ownership.
