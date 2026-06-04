# SoundTesting: ArrayWave

ArrayWave is a focused Roblox Luau audio visualizer. The default base song is Roblox audio asset `9043887091`; if that asset is unavailable to the experience, the client falls back to a synthetic Demo signal so the visualizer still moves immediately.

The visualizer is the product. There are no rounds, quests, NPCs, coins, XP, lore systems, monetization, or DataStores.

## Controls

All project controls are UI-only through the small `ArrayWave` dock. The dock includes:

- Play Base
- Demo
- Mic
- Asset ID field, prefilled with `9043887091`
- Play Asset
- Stop
- Visual modes: Grid, Row, Circle, All, Minimal
- Sensitivity and intensity adjustment
- Pulse Test
- Drop Marble when the marble remote is available

No project keyboard shortcuts are used.

## Features

- Base song attempts to play automatically on startup.
- Demo mode remains the reliable fallback for unavailable or private audio.
- Asset mode attempts a modular Roblox audio graph, then falls back to local `Sound` loudness.
- Mic mode attempts modular microphone analysis and falls back cleanly if unavailable.
- Visualizer modes: Grid, Row, Circle, All, Minimal.
- Server-built matte gallery environment with a 17x17 anchor grid.
- Local-only 21x21 grid array, 64 row bars, 96 radial circle bars, and pooled shockwaves.
- One narrow client-to-server remote for optional, rate-limited marble spawning.

## Systems Demonstrated

- Rojo project mapping.
- Strict Luau ModuleScripts.
- Shared/server/client separation.
- Explicit `Init()` and `Start()` lifecycle.
- Local audio analysis with privacy-preserving networking.
- Server-side remote validation and rate limiting.
- Pooled visualizer parts with no per-frame allocation.
- Compact generated UI that uses `Activated` for mouse, touch, and gamepad activation.

## Run With Rojo

```sh
rojo serve default.project.json
```

Connect Roblox Studio to the Rojo server and start a play session.

## Base Song

The default asset ID is `9043887091`. Roblox audio permission rules may prevent an asset from loading in a given experience. If the base song cannot be played or analyzed, the UI reports the fallback and Demo mode starts without errors.

## Demo Mode

Demo mode generates a synthetic audio frame every render step. It creates changing bands, RMS, peak, bass, and beat values so Grid, Row, and Circle modes visibly animate in the first few seconds.

## Asset Mode

Paste a numeric Roblox audio asset ID and use the UI `Play Asset` button. The client first attempts:

- `AudioPlayer`
- `AudioAnalyzer`
- `AudioDeviceOutput`
- `Wire`

If modular audio is unavailable, it tries a local `Sound` and reads `PlaybackLoudness`. Invalid, private, or blocked assets fall back without crashing.

## Mic Mode

Mic mode attempts:

- `AudioDeviceInput`
- `AudioAnalyzer`
- `Wire`

Raw microphone samples are never read, saved, or sent to the server. Microphone support depends on Roblox runtime support, permissions, and player eligibility.

## Folder Structure

```text
src/shared
src/server
src/client
docs
```

## Security Notes

Audio frames, microphone state, spectrum data, RMS, peak, bass, and beat values stay client-side. The only remote is `MarbleRequested`, and its payload contains only optional cosmetic energy. The server decides spawn position, size, velocity, physical properties, lifetime, and network ownership.

## Performance Notes

The visualizer instances are created once under `Workspace/ArrayWaveClientVisuals` and updated in place from one render connection. The server only handles limited marble spawns and cleanup.
