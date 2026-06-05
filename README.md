# SoundTesting: ArrayWave

ArrayWave is a Roblox audio visualizer built from Luau, anchored parts, and a local audio analyzer.

It starts with audio asset `9043887091`. Click the song ID at the top of the screen to replace it, then use Asset to try the new ID. If Roblox cannot play or analyze the asset in the place, the client falls back to a local demo signal.

The visualizer has three main shapes:

- Grid tiles use spring motion, bass domes, diagonal waves, and beat ripples.
- Row bars act like an equalizer, with each bar mapped to its own band response and peak cap.
- Circle bars radiate around the field with traveling sound-wave motion.

Tune opens the extra controls. The collapsed UI only keeps the small media controls visible: Base, Demo, the current view, and Tune.

All controls are UI-only. There are no project keybinds. Audio analysis, spectrum bands, camera state, and visualizer state stay on the client.

## Running

```sh
rojo serve default.project.json
```

Connect Roblox Studio to the Rojo server and start a play session.
