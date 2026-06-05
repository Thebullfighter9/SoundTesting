# Architecture

This project uses a Rojo layout:

```text
src/replicatedfirst -> ReplicatedFirst
src/startergui -> StarterGui
src/shared -> ReplicatedStorage/Shared
src/server -> ServerScriptService/Server
src/client -> StarterPlayer/StarterPlayerScripts/Client
```

## UI

`src/startergui/ArrayWaveGui.model.json` is the static UI model. `UIController` binds named instances from that model and does not build the UI tree at runtime.

The top pill holds the song ID, status text, and a small analyzer truth label. The bottom dock starts collapsed with Base, Demo, current view, and Tune.

## Client

`AudioController` produces typed audio frames and diagnostics.

`ResonanceController` creates the local-only sculpture under `Workspace.ArrayWaveClientVisuals`:

- 441 grid tiles
- 96 row bars and peak caps
- 128 radial circle bars
- pooled pulse rings and light streaks

The visual controller reads `AnalyzerTruthMode` before updating the shapes. Spectrum mode favors direct band response. Loudness-only mode uses amplitude waves. Demo mode uses the synthetic demo signal.

## Server

Server modules build the static place support and optional remote-backed effects. They do not receive per-frame audio or visualizer data.

## Lifecycle

Modules expose `Init()` and `Start()`. Requiring a module does not connect loops or start playback. Bootstrap initializes controllers first, then starts them.
