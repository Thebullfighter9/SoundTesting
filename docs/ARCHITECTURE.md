# Architecture

ArrayWave uses a Rojo layout with a clear server/client/shared split.

```text
src/replicatedfirst -> ReplicatedFirst
src/startergui -> StarterGui
src/shared -> ReplicatedStorage/Shared
src/server -> ServerScriptService/Server
src/client -> StarterPlayer/StarterPlayerScripts/Client
```

## ReplicatedFirst

`Loading.client.lua` removes the default Roblox loading screen and creates `ArrayWaveLoadingGui` immediately. It waits for the local player attribute `ArrayWaveClientReady`, with a short minimum display time and a timeout so loading cannot block forever.

`Bootstrap.client.lua` sets `ArrayWaveClientReady` to `false` before controller startup and sets it to `true` after all client controllers have started.

## Shared

Shared modules contain constants, exported types, remote names, and small utilities. They do not connect events or start loops at require time.

Shared constants define the default base song, visual styles, palette, loading timings, visual counts, audio band count, and UI analyzer count.

## StarterGui

`ArrayWaveGui.model.json` defines the top-center `NowPlayingPill`, `SongIdBox`, bottom-center `BottomControlDock`, analyzer strip, and buttons as a static Rojo UI asset. Client code does not create the UI tree at runtime.

`NowPlayingPill` owns the current source/status readout and the highlighted song ID field. `BottomControlDock` owns transport, visual mode, Sensitivity, Motion, Spray, Pulse, View, and optional Marble controls.

## Server

Server modules own replicated world setup and optional server effects:

- `RemoteService` creates the remotes folder and `MarbleRequested`.
- `GalleryService` rebuilds the matte gallery room, platform, anchor grid, and marble container.
- `MarbleService` validates marble requests and spawns temporary server-owned marbles.

The server does not receive per-frame audio, mic, spectrum, band, or beat data.

## Client

Client controllers own presentation and UI-only controls:

- `AudioController` produces rich audio frames in Demo, Asset, or Mic mode.
- `ResonanceController` creates and updates the local-only ArrayWave visualizer under `Workspace/ArrayWaveClientVisuals`.
- `CameraController` frames the sculpture and applies subtle bass or beat-strength FOV feedback.
- `UIController` binds behavior to the static `ArrayWaveGui` instances, owns all project controls, and sends optional marble requests.

Visual child folders are:

- `GridArray`
- `RowBars`
- `RadialCircle`
- `Shockwaves`
- `AccentLights`
- `LightSprays`

The visualizer pools 441 grid tiles, 96 row bars, 128 radial bars, 8 reusable shockwave rings, a small accent light set, and 120 local light spray streaks. It updates those instances from one client render loop.

Grid tiles keep per-tile spring state (`currentY`, `velocityY`, `currentHeight`, glow, ripple, and last target). The controller updates both `Size` and `CFrame` so the field rises and scales on beats without creating or destroying parts per frame.

## Audio Boundary

Audio analysis is local presentation state. Spectrum, RMS, peak, beat, band values, microphone state, and asset loudness are not sent to the server.

The client only sends a marble request when the player uses the optional UI control. The payload contains optional cosmetic energy only.

## Remote Boundary

The only gameplay remote is `MarbleRequested`, sent client to server. The server ignores client position, velocity, color, size, and ownership claims. It clamps energy, rate-limits requests, enforces the active marble limit, and owns the spawned physics bodies.

## Lifecycle

Modules expose `Init()` and `Start()`. Requiring a module does not start loops or connect events. Bootstrap scripts call all `Init()` methods first, then all `Start()` methods.
