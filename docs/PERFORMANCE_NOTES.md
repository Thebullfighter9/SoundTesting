# Performance Notes

Resonance Field is designed as a lightweight kinetic sculpture.

## Client

- One render connection updates the field.
- Visual parts are created once and reused.
- Field pins, surface tiles, wave segments, and orbit masses are updated in place.
- Pulse particles are sparse and emitter-based.
- UI readouts are throttled.
- Audio frames are never sent to the server.

## Server

- The server creates the field environment once at startup.
- Runtime server work is limited to validated pulse mass spawning.
- Pulse masses are capped per player.
- Pulse masses self-clean after a short lifetime.
- The remote is rate-limited per player.

## Profiling

Use Roblox Developer Console, Script Profiler, and MicroProfiler during Studio playtests. The client field update should stay a small part of frame time, and server work should remain near idle unless players are sending pulses.
