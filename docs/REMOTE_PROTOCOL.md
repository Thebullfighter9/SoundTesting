# Remote Protocol

There is one optional remote left: `MarbleRequested`.

It is not part of the audio visualizer. The normal UI keeps the marble control hidden.

Direction:

```text
client -> server
```

Payload:

```lua
{
	energy = number?, -- finite, clamped 0..1
}
```

The payload can be `nil`. The server uses a safe default.

## Server Rules

The server checks that:

- the player and character still exist
- `HumanoidRootPart` exists
- the payload is either `nil` or a table
- `energy`, if present, is finite
- the request is inside the rate limit
- the player is under the active marble limit

The server ignores client-provided position, velocity, color, size, ownership, and identity fields.

The client asks. The server decides what gets created.
