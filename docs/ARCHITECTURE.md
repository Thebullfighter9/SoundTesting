# Architecture

ArrayWave uses a Rojo layout with a server/client/shared split.

```text
src/replicatedfirst -> ReplicatedFirst
src/startergui -> StarterGui
src/shared -> ReplicatedStorage/Shared
src/server -> ServerScriptService/Server
src/client -> StarterPlayer/StarterPlayerScripts/Client
```

## Shared

Shared modules contain constants, exported types, remote names, and small utilities. They do not connect events or start loops at require time.

`Constants.lua` defines the default song, visual counts, visual tuning, camera settings, palette, and UI sizing.

## StarterGui

`ArrayWaveGui.model.json` is the static UI model. `UIController` binds named instances from that model and does not build the UI tree at runtime.

The first-join UI is intentionally small: a top song pill and a collapsed bottom dock. Tune opens the extra source, view, feel, camera, and pulse controls. The optional marble button is kept out of the normal visible UI.

## Server

Server modules own replicated world setup and optional server effects:

- `RemoteService` creates the remotes folder and `MarbleRequested`.
- `GalleryService` rebuilds the gallery room, platform, anchor grid, and marble container.
- `MarbleService` validates marble requests and spawns temporary server-owned marbles.

The server does not receive per-frame audio, mic, spectrum, band, beat, camera, or visualizer state.

## Client

Client controllers own presentation and UI-only controls:

- `AudioController` produces local audio frames in Demo, Asset, or Mic mode.
- `ResonanceController` creates and updates the local-only visualizer under `Workspace/ArrayWaveClientVisuals`.
- `CameraController` owns the scriptable orbit camera and local avatar hiding.
- `UIController` binds the static UI and sends the optional marble request only when that hidden control is used.

`ResonanceController` creates pooled visuals once, then updates them from one client render loop:

- 441 grid tiles
- 96 row bars and 96 peak caps
- 128 radial circle bars
- reusable shockwave rings
- faint persistent waveform rings
- accent lights
- 120 light spray streaks

Grid, Row, and Circle each keep per-element motion state. Bars and tiles are assigned band indices, secondary bands, phase offsets, smoothing values, glow, and spring velocity. This lets neighboring elements stay continuous without moving identically.

The controller writes low-rate test attributes to `Workspace.ArrayWaveClientVisuals`, including variance and active effect counts. These attributes are for Studio checks only and are not shown in the UI.

## Lifecycle

Modules expose `Init()` and `Start()`. Requiring a module does not start loops or connect events. Bootstrap scripts call all `Init()` methods first, then all `Start()` methods.
