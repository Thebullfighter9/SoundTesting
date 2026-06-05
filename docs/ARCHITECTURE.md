# Architecture Notes

Rojo maps the project like this:

```text
src/replicatedfirst -> ReplicatedFirst
src/startergui -> StarterGui
src/shared -> ReplicatedStorage/Shared
src/server -> ServerScriptService/Server
src/client -> StarterPlayer/StarterPlayerScripts/Client
```

## UI

`src/startergui/ArrayWaveGui.model.json` is the UI. It is not built again every time the client runs.

`UIController` only binds named objects from that static model. The top pill has the song ID, status text, and the tiny `Spectrum` / `Loudness` / `Demo` / `Silent` label.

## Client

`AudioController` owns playback, analysis, fallback mode, and diagnostics.

`ResonanceController` builds the local visualizer under `Workspace.ArrayWaveClientVisuals`:

- 441 grid tiles
- 96 row bars
- 96 row peak caps
- 128 circle bars
- pooled pulse rings and light streaks

The visual controller checks the audio truth mode before it moves anything. Real spectrum gets direct band response. Loudness-only gets amplitude motion. Demo gets the local test signal.

## Server

The server builds the place support pieces and owns the optional marble remote. It does not receive per-frame visualizer data.

## Startup

Modules expose `Init()` and `Start()`. Requiring a module should not start playback or connect render loops. Bootstrap initializes first, then starts.
