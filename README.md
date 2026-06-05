# SoundTesting: Resonance Field

A Roblox Luau audio visualizer built as a small kinetic sculpture.

The default audio asset is `9043887091`. The client tries to read real spectrum data from Roblox's audio analyzer. When Roblox only exposes loudness, the project says so and uses a broad amplitude wave instead of pretending it has per-frequency data. Demo mode is separate and labeled as Demo.

The piece has three main views:

- Grid: a field of local parts that rises from band or amplitude energy.
- Row: the clearest readout. In Spectrum mode each bar follows a band; in Loudness mode the row becomes an amplitude wave.
- Circle: a radial version of the same signal with restrained motion.

The UI is intentionally small: base song, demo, current view, tune, and the song ID field. There are no keybinds, rounds, quests, NPCs, or simulator panels.

## Running

```sh
rojo serve default.project.json
```

Connect Roblox Studio to the Rojo server and start a play session.
