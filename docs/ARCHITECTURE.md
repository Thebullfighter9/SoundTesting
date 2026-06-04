# Architecture

Resonance Field uses a Rojo layout with a clear runtime split.

```text
src/shared -> ReplicatedStorage/Shared
src/server -> ServerScriptService/Server
src/client -> StarterPlayer/StarterPlayerScripts/Client
```

## Shared

Shared modules contain constants, exported types, remote names, and small utilities. They do not connect events or start loops at require time.

## Server

Server modules own replicated state:

- `RemoteService` creates the remotes folder and `FieldPulseRequested`.
- `LabWorldService` rebuilds the matte field sculpture environment.
- `FieldPulseService` validates pulse requests and spawns temporary pulse masses.

## Client

Client controllers own presentation and input:

- `AudioInputController` produces audio frames in Demo, Asset, or Mic mode.
- `VisualizerController` updates local-only field pins, surface tiles, wave segments, and orbit masses.
- `EffectsController` handles restrained pulse feedback and toast messages.
- `UIController` builds the compact generated UI.
- `InputController` binds keys and sends narrow pulse requests.

## Audio Boundary

Audio analysis is local presentation state. Spectrum, RMS, peak, beat, microphone state, and asset loudness are not sent to the server.

## Remote Boundary

The only gameplay remote is `FieldPulseRequested`, sent client -> server. It accepts optional cosmetic intensity only. The server ignores client position, velocity, color, size, and ownership claims.

## Lifecycle

Modules expose `Init()` and `Start()`. Requiring a module does not start loops or connect events. Bootstrap scripts call all `Init()` methods first, then all `Start()` methods.
