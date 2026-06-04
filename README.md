# SoundTesting: Resonance Field

Resonance Field is a minimal Roblox Luau audio physics visualizer: a quiet gallery installation where a tiled speaker-membrane sculpture responds to a demo signal, asset audio, or microphone analyzer data when available.

It exists as a scripting portfolio piece. There are no rounds, quests, NPCs, coins, XP, lore systems, monetization, or DataStores.

## Controls

- `H`: hide or show UI
- `D`: Demo mode
- `M`: try Mic mode
- `A`: play the current asset ID
- `V`: cycle visual style
- `E`: drop a server-validated resonance marble
- `R`: reset camera framing

## Features

- Demo mode animates immediately and needs no external assets.
- Asset mode attempts a modular Roblox audio graph, then falls back to local `Sound` loudness.
- Mic mode attempts modular microphone analysis and falls back cleanly if unavailable.
- Visual styles: Field, Orbit, Marbles, Minimal.
- Server-built matte gallery environment with a 17x17 anchor grid.
- Local-only tiled field, shockwave ring, orbit points, and subtle speaker pulses.
- One narrow client-to-server remote for rate-limited marble spawning.
- Generated UI kept small, bottom-left, and secondary to the sculpture.

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

Demo mode generates a synthetic audio frame every render step. It creates smooth bands, RMS, peak, bass, and beat values so the field moves immediately in the first few seconds.

## Asset Mode

Paste a numeric Roblox audio asset ID and press `Play`, or press `A`. The client first attempts:

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

Audio frames, microphone state, spectrum data, RMS, peak, bass, and beat values stay client-side. The only remote is `MarbleRequested`, and its payload contains only optional cosmetic energy. The server decides spawn position, size, velocity, physical properties, lifetime, and network ownership.

## Performance Notes

The field visuals are created once and updated in place from one render connection. UI readouts are throttled. The server only handles limited marble spawns and cleanup.

## Screenshots
