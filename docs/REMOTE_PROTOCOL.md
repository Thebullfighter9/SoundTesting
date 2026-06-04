# Remote Protocol

## BeatOrbRequested

Direction: client -> server

Payload:

```lua
{
	energy = number, -- optional/cosmetic, finite, clamped 0..1
}
```

The payload may also be `nil`, in which case the server uses a safe default cosmetic energy.

## Server Validation

The server validates:

- player still exists
- character exists
- `HumanoidRootPart` exists
- payload is `nil` or a table
- `energy` is a finite number when provided
- `energy` is clamped to `0..1`
- player is within the request rate limit
- player has fewer than the maximum active beat orbs

## Server Ignores

The server ignores:

- client position
- client velocity
- client color
- client size
- client network ownership claims
- player identity inside payloads

The client may only request an orb. The server decides where it spawns, how large it is, how fast it moves, how long it lives, and who owns physics simulation.
