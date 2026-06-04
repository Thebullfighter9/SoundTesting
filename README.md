# SoundTesting: PulseForge Audio Physics Visualizer

PulseForge is a focused Roblox Luau proof-of-concept for audio-reactive visuals, local audio analysis, generated UI, server-validated physics, and clean client/server architecture.

It starts in Demo mode, so it is playable immediately without uploaded audio assets or microphone access. Players can switch visual presets, paste a Roblox audio asset ID, try microphone analysis where modular audio APIs and permissions allow it, and drop server-spawned beat orbs from UI or keyboard input.

## Why It Exists

This repository is a scripting portfolio demo. It favors maintainable Roblox systems over a large content-heavy game: clear ModuleScripts, explicit lifecycle setup, narrow networking, local-only audio processing, reusable generated UI, and a server-authoritative physics interaction.

## Controls

- `E`: request a beat orb
- `Space`: request a beat orb while allowing default jump to continue
- `B`: cycle visual preset
- `M`: try Mic mode
- `N`: return to Demo mode
- UI buttons: mode selection, asset playback, stop, preset cycling, sensitivity, intensity, beat-orb request

## Features

- Procedural Demo mode that generates a synthetic 32-band audio frame.
- Asset mode that first attempts a modular audio graph and falls back to a local `Sound` when needed.
- Mic mode that attempts modular microphone input and falls back to Demo mode if unavailable.
- Presets: Bars, Ring, Orbit, Physics, Calm, Chaos.
- Server-created neon lab built from Roblox primitives.
- Local-only visualizer bars, ring, orbit objects, speaker pulses, particles, FOV pulse, and beat flash.
- Server-owned beat orb spawning with validation and rate limiting.
- Generated responsive UI under `PlayerGui`.

## Systems Demonstrated

- Rojo project mapping.
- `Init()` and `Start()` lifecycle.
- Server/client/shared separation.
- Remote validation and throttling.
- Client-local audio analysis and visual effects.
- Reused visual instances with no per-frame instance creation.
- Maid-style cleanup.
- Strict Luau modules.

## Run With Rojo

1. Install Rojo if it is not already available.
2. From this repository root, run:

   ```sh
   rojo serve default.project.json
   ```

3. Open Roblox Studio.
4. Connect Studio to the Rojo server.
5. Press Play.

## Test Demo Mode

Demo mode starts automatically. The bars, ring, orbit objects, speaker pulses, UI readouts, and beat effects should move without any asset ID or microphone permission.

## Test Asset Mode

Paste a numeric Roblox audio asset ID into the UI text box and press `Play Asset`. The client attempts `AudioPlayer`, `AudioAnalyzer`, `AudioDeviceOutput`, and `Wire` first. If that graph is unavailable, it tries a local `Sound` and uses `PlaybackLoudness`.

Invalid, private, empty, negative, nonnumeric, or too-long IDs are rejected or fall back to Demo mode without crashing.

## Test Mic Mode

Press `M` or the `Mic` button. The client attempts `AudioDeviceInput`, `AudioAnalyzer`, and `Wire`. Raw microphone samples are not exposed, saved, or sent to the server. If the API, eligibility, or permission path is unavailable, the UI reports the fallback and returns to Demo mode.

## Limitations

- Audio API availability can vary by Studio/client version and permission state.
- Mic mode depends on Roblox microphone eligibility and runtime support.
- Asset mode depends on the target asset being public and loadable by the local player.
- This project intentionally does not include monetization, DataStores, NPCs, combat, or external assets.

## Folder Structure

```text
src/shared
src/server
src/client
docs
```

Shared modules hold constants, types, remotes, and utilities. Server modules own the replicated lab and physics orb spawning. Client controllers own audio analysis, generated UI, local visuals, input, and effects.

## Security Notes

Audio frames, microphone state, spectrum data, RMS, and peak values remain client-side. The only client-to-server remote is `BeatOrbRequested`, and the server accepts only optional cosmetic energy. The server ignores client position, velocity, color, size, and ownership claims.

## Performance Notes

The visualizer creates instances once and updates them from one render connection. The server spawns a limited number of temporary physics orbs per player. There is no per-frame remote traffic and no per-frame instance creation.

## Screenshots
