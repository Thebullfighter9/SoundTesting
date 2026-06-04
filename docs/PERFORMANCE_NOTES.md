# Performance Notes

PulseForge is designed as a lightweight scripting demo.

## Client

- The visualizer uses one render connection.
- Visual parts are created once and reused.
- Bars, ring segments, orbit objects, speaker cones, and beam parts are updated in place.
- Beat particles use emitters rather than creating parts per beat.
- UI readouts are throttled instead of writing text every render frame.
- Audio analysis never sends per-frame data to the server.

## Server

- The server creates the lab once at startup.
- The only runtime server gameplay work is validated beat-orb spawning.
- Active beat orbs are capped per player.
- Beat orbs self-clean after a short lifetime.
- The beat-orb remote is rate-limited per player.

## Profiling

Use Roblox Developer Console, Script Profiler, and MicroProfiler during Studio playtests. The client visualizer update should stay a small fraction of frame time, and server work should remain near idle unless players are requesting beat orbs.

If a future version adds more visual instances, prefer pooling and lower-frequency updates before adding extra render loops.
