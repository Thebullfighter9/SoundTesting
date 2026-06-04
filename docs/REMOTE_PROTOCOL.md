# Remote Protocol

## MarbleRequested

Direction: client -> server

Payload:

```lua
{
	energy = number, -- optional cosmetic value, finite, clamped 0..1
}
```

The payload may be `nil`; the server then uses a safe default energy.

## Server Validation

The server validates:

- player still exists
- character exists
- `HumanoidRootPart` exists
- payload is `nil` or a table
- `energy` is finite when provided
- `energy` is clamped to `0..1`
- player is within the request rate limit
- player has fewer than the maximum active marbles

## Server Ignores

The server ignores:

- client position
- client velocity
- client color
- client size
- client network ownership claims
- player identity in payloads

The client requests a marble. The server owns the physical result.
