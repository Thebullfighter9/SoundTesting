# Remote Protocol

## FieldPulseRequested

Direction: client -> server

Payload:

```lua
{
	intensity = number, -- optional/cosmetic, finite, clamped 0..1
}
```

The payload may be `nil`; the server then uses a safe default intensity.

## Server Validation

The server validates:

- player still exists
- character exists
- `HumanoidRootPart` exists
- payload is `nil` or a table
- `intensity` is finite when provided
- `intensity` is clamped to `0..1`
- player is within the request rate limit
- player has fewer than the maximum active pulse masses

## Server Ignores

The server ignores:

- client position
- client velocity
- client color
- client size
- client network ownership claims
- player identity in payloads

The client requests a pulse. The server owns the physical result.
