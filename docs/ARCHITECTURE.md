# Architecture

PulseForge uses a Rojo layout that maps shared modules, server code, and client code into separate Roblox runtime locations.

```text
src/shared -> ReplicatedStorage/Shared
src/server -> ServerScriptService/Server
src/client -> StarterPlayer/StarterPlayerScripts/Client
```

## Runtime Split

Shared modules contain constants, exported types, remote names, and utility modules. They do not start loops, connect events, or mutate world state at require time.

Server modules own replicated world setup and beat-orb spawning:

- `RemoteService` creates `ReplicatedStorage/Remotes` and the one RemoteEvent.
- `LabWorldService` rebuilds the neon lab, spawn, anchors, orb container, and lighting.
- `BeatOrbService` validates remote requests and spawns temporary physics orbs.

Client controllers own local-only audio analysis, UI, visuals, input, and effects:

- `AudioInputController` produces the current audio frame in Demo, Asset, or Mic mode.
- `VisualizerController` reuses local visual parts and updates them each render step.
- `EffectsController` handles beat flash, particles, FOV pulse, and toast messages.
- `UIController` builds the generated UI under `PlayerGui`.
- `InputController` binds keyboard actions and sends narrow beat-orb requests.

## Audio Is Local

Audio analysis stays on the client because it is presentation state. RMS, peak, spectrum bands, microphone state, and local asset loudness are not sent to the server. This avoids per-frame network traffic and keeps microphone/audio information private to the local player.

## Remote Boundary

The only required remote is `BeatOrbRequested`, sent from client to server. Its payload contains optional cosmetic energy only. The server ignores client position, velocity, color, size, and ownership claims.

## Lifecycle

Every service and controller exposes `Init()` and `Start()`. `Init()` stores dependencies and prepares state. `Start()` connects events, starts render work, or builds world/UI instances.

No module starts loops or connects events at require time. This keeps boot order explicit and makes modules easier to inspect, test, and replace.
