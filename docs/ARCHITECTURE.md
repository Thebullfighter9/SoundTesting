# Architecture

ArrayWave Visualizer uses a Rojo layout with a clear server/client/shared split.

```text
src/shared -> ReplicatedStorage/Shared
src/server -> ServerScriptService/Server
src/client -> StarterPlayer/StarterPlayerScripts/Client
```

## Shared

Shared modules contain constants, exported types, remote names, and small utilities. They do not connect events or start loops at require time.

## Server

Server modules own replicated state:

- `RemoteService` creates the remotes folder and `MarbleRequested`.
- `GalleryService` rebuilds the matte gallery room, platform, anchor grid, and marble container.
- `MarbleService` validates marble requests and spawns temporary server-owned marbles.

## Client

Client controllers own presentation and input:

- `AudioController` produces audio frames in Demo, Asset, or Mic mode.
- `ResonanceController` creates and updates the local-only ArrayWave visualizer under `Workspace/ArrayWaveClientVisuals`.
- Visual child folders are `GridArray`, `RowBars`, `RadialCircle`, `Shockwaves`, and `DebugMarkers`.
- The visualizer pools 21x21 grid tiles, 64 row bars, 96 radial bars, and six reusable shockwave rings.
- `CameraController` frames the sculpture and applies clamped FOV feedback.
- `UIController` builds the compact generated UI.
- `InputController` binds keys and sends narrow marble requests.

## Audio Boundary

Audio analysis is local presentation state. Spectrum, RMS, peak, beat, microphone state, and asset loudness are not sent to the server. The client only sends a marble request when the player explicitly requests one.

## Remote Boundary

The only gameplay remote is `MarbleRequested`, sent client -> server. It accepts optional cosmetic energy only. The server ignores client position, velocity, color, size, and ownership claims.

## Lifecycle

Modules expose `Init()` and `Start()`. Requiring a module does not start loops or connect events. Bootstrap scripts call all `Init()` methods first, then all `Start()` methods.
