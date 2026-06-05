# SoundTesting: ArrayWave

ArrayWave is a premium Roblox Luau audio visualizer proof-of-concept. The visualizer is the product: a strong audio-reactive field with springy local geometry, pooled light bursts, compact UI controls, and a custom loading screen.

The built-in base song is Roblox audio asset `9043887091`. If Roblox audio permissions make that asset private, blocked, or unavailable to the experience, the client reports `Base song unavailable - using demo signal` and switches to Demo mode so the sculpture moves immediately.

There are no rounds, quests, NPCs, coins, XP, lore systems, shops, tycoon systems, or DataStores. All project controls are UI-only, and project features are not bound to keyboard input.

## Controls

The UI is a static `StarterGui` asset. `UIController` only binds named instances and uses `GuiButton.Activated` for mouse, touch, and gamepad activation.

The top-center `NowPlayingPill` shows the current source, a highlighted `SongIdBox`, and the current status. `SongIdBox` starts with `9043887091`; focusing it selects the text for quick replacement, and `Play Asset` uses the current box value.

The bottom-center `BottomControlDock` keeps controls compact and away from the field:

- Play Base
- Demo
- Mic
- Play Asset
- Stop
- Visual modes: Grid, Row, Circle, All, Minimal
- Sensitivity, Motion, and Spray controls
- Pulse Test
- Reset View
- Drop Marble when the optional marble remote exists

## Visual Modes

- Grid: 21 x 21 pooled tiles form a physical-looking field with spring-damper jumps, height scaling, bass domes, mid waves, high shimmer, and beat ripples.
- Row: 96 pooled equalizer bars use audio bands plus peak hold caps.
- Circle: 128 pooled radial bars breathe with bass and emit reusable sound-wave rings on transients.
- All: Grid, Row, and Circle are composed together without hiding the main field.
- Minimal: a restrained grid and faint circle with calmer motion and lower spray output.

## Audio Analysis

Client audio frames include RMS, peak, bass, low-mid, mid, high, air, visual energy, spectral centroid, spectral flux, transient, beat, beat strength, and 96 smoothed bands.

Asset and Mic modes try modular Roblox audio first:

- `AudioPlayer`
- `AudioAnalyzer`
- `Wire`
- `AudioDeviceOutput`
- `AudioDeviceInput` for Mic when supported

When `AudioAnalyzer:GetSpectrum()` is available, the controller uses it. If spectrum data is not available, the controller synthesizes useful bands from RMS, peak, and time. If modular audio fails, Asset mode falls back to local `Sound.PlaybackLoudness`; if that also fails, Demo mode takes over.

The analyzer uses rolling peak/RMS normalization and clamped visual auto-gain so quiet assets still produce readable movement. The beat detector uses smoothed bands, short and long energy envelopes, positive spectral flux, transient energy, and a cooldown. Demo mode creates kick-like bass, snare-like mids, high-hat shimmer, groove variation, and non-flat bands.

## Loading Screen

`src/replicatedfirst/Loading.client.lua` replaces the Roblox default loading screen with a dark ArrayWave screen, animated procedural bars, short status messages, and a fade-out after the client marks `ArrayWaveClientReady` or the timeout is reached.

## Privacy And Networking

Audio analysis stays client-side. Raw audio, mic data, spectrum arrays, RMS, peak, bands, beat data, and loudness are never saved and never sent to the server.

The only client-to-server remote is the optional `MarbleRequested` remote. Its payload contains only `{ energy = number }`, and the server validates, clamps, rate-limits, and owns marble spawning.

## Performance

Visualizer instances are created once under `Workspace/ArrayWaveClientVisuals` and updated in place from one client render loop. Child folders are:

- `GridArray`
- `RowBars`
- `RadialCircle`
- `Shockwaves`
- `AccentLights`
- `LightSprays`

The default pooled visual counts are 441 grid tiles, 96 row bars, 128 radial bars, 8 shockwave rings, 10 accent lights, and 120 local light spray streaks.

## Run With Rojo

```sh
rojo serve default.project.json
```

Connect Roblox Studio to the Rojo server and start a play session.

## Folder Structure

```text
src/replicatedfirst
src/startergui
src/shared
src/server
src/client
docs
```
