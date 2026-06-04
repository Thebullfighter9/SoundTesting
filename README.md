# SoundTesting: Resonance Field

Resonance Field is a minimal Roblox Luau audio physics visualizer. It is a clean kinetic sculpture: a measured field of pins, rings, surface tiles, and pulse masses driven by a demo signal, asset audio, or microphone analyzer data when available.

This is a scripting portfolio piece, not a game loop. There are no rounds, quests, NPCs, combat, lore, monetization, or simulator-style progression.

## Controls

- `E`: send a server-validated field pulse
- `Space`: send a field pulse while allowing default jump to continue
- `B`: cycle field preset
- `M`: try Mic mode
- `N`: return to Demo mode
- UI: mode selection, asset analysis, reset, preset, sensitivity, intensity, pulse

## Features

- Demo mode starts immediately and needs no external assets.
- Asset mode attempts a modular Roblox audio graph, then falls back to local `Sound` loudness.
- Mic mode attempts modular microphone analysis and falls back cleanly if unavailable.
- Presets: Field, Wave, Orbit, Still.
- Server-built matte gallery environment with field anchors and reference rings.
- Local-only kinetic field visuals with reused instances.
- One narrow client-to-server remote for rate-limited pulse mass spawning.
- Generated UI kept small and utilitarian.

## Systems Demonstrated

- Rojo project mapping.
- Strict Luau ModuleScripts.
- Shared/server/client separation.
- Explicit `Init()` and `Start()` lifecycle.
- Local audio analysis with privacy-preserving networking.
- Server-side remote validation and rate limiting.
- Low-instance-count visual updates with no per-frame allocation.
- Maid-style cleanup helpers.

## Run With Rojo

```sh
rojo serve default.project.json
```

Connect Roblox Studio to the Rojo server and press Play.

## Demo Mode

Demo mode generates a synthetic audio frame every render step. It creates smooth bands, RMS, peak, bass, and beat values so the field moves immediately even in an empty place.

## Asset Mode

Paste a numeric Roblox audio asset ID and press `Analyze`. The client first attempts:

- `AudioPlayer`
- `AudioAnalyzer`
- `AudioDeviceOutput`
- `Wire`

If modular audio is unavailable, it tries a local `Sound` and reads `PlaybackLoudness`. Invalid or private assets fall back without crashing.

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

Audio frames, microphone state, spectrum data, RMS, peak, bass, and beat values stay client-side. The only remote is `FieldPulseRequested`, and its payload contains only optional cosmetic intensity. The server decides spawn position, size, velocity, physical properties, lifetime, and network ownership.

## Performance Notes

The field visuals are created once and updated in place from one render connection. UI readouts are throttled. The server only handles limited pulse mass spawns and cleanup.

## Screenshots
