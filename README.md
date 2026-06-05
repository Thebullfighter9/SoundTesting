# SoundTesting: ArrayWave

ArrayWave is a small Roblox Luau project that turns audio into a moving field of parts.

It starts with Roblox audio asset `9043887091`. If that asset is blocked or unavailable in the place, the client switches to a local demo signal so the visuals still run.

## Overview

The scene is built around one client-side visualizer and a slow orbit camera. The local character is hidden so it does not get between the camera and the field.

- `Grid`: a 21 x 21 field of anchored tiles using spring-style motion.
- `Row`: 96 equalizer bars with peak caps.
- `Circle`: 128 radial bars with expanding ring pulses.
- `All`: shows the main visual layers together.
- `Minimal`: keeps the same system quieter and less busy.

The visualizer also uses pooled shockwaves, accent lights, and short light streaks for beat and pulse moments. These parts are created once and reused.

## UI

The UI is defined in `src/startergui/ArrayWaveGui.model.json`.

`UIController` does not build the interface at runtime. It finds the named instances from the static `StarterGui` model and wires the buttons with `GuiButton.Activated`.

At the top of the screen, `SongIdBox` shows the current audio asset ID. It starts with `9043887091`, and the Asset button uses whatever value is in that box.

The bottom dock is collapsed by default. It shows the base audio control, current visual mode, Tune, and camera mode. Tune opens the extra controls:

- Play Base
- Demo
- Mic
- Asset
- Stop
- Grid, Row, Circle, All, Minimal
- Sens, Motion, and Spray controls
- Pulse
- Marble, when the optional server remote exists

All project controls are handled through the UI.

## Audio

Audio analysis is local to the client. The controller reads analyzer data when Roblox's modular audio path is available, falls back to local `Sound.PlaybackLoudness` when needed, and uses Demo mode if neither path gives usable data.

The frame data includes RMS, peak, frequency bands, bass/mid/high ranges, transient energy, beat strength, spectral flux, centroid, and a normalized visual energy value. Quiet audio is raised with clamped auto-gain so the field does not go flat.

Raw audio, mic data, spectrum arrays, band data, beat values, camera state, and visualizer state are not sent to the server.

## Networking

The server builds the gallery space and owns the optional marble effect.

The only client-to-server visual request is `MarbleRequested`. It sends a small `{ energy = number }` payload, which the server clamps, rate-limits, and uses to spawn a temporary server-owned marble.

## Project Layout

```text
src/replicatedfirst
src/startergui
src/shared
src/server
src/client
docs
```

## Running

```sh
rojo serve default.project.json
```

Then connect Roblox Studio to the Rojo server and start a play session.
