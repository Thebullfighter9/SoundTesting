# Audio Notes

PulseForge starts in Demo mode so the project is immediately playable without uploaded assets or microphone permission.

## Demo Mode

Demo mode generates a synthetic audio frame on the client. It uses sine pulses, bass-shaped beat pulses, noise variation, smoothing, rolling energy, and a dynamic beat threshold to produce:

- `rms`
- `peak`
- `bass`
- `beat`
- 32 visualizer bands
- frame time

## Asset Mode

Asset mode sanitizes the text box input and accepts numeric Roblox asset IDs only. Empty, negative, nonnumeric, and extremely long inputs are rejected.

The client first attempts a modular audio graph:

- `AudioPlayer`
- `AudioAnalyzer`
- `AudioDeviceOutput`
- `Wire`

The graph wires the player output to the analyzer and local device output so the local user can hear supported assets while the visualizer reads analyzer levels. Property and method access is wrapped with `pcall` because modular audio support can vary by runtime version and permissions.

If the modular graph fails, the client tries a classic local `Sound` with `SoundId = "rbxassetid://<id>"` and uses `PlaybackLoudness` for visualization. Invalid or private assets fall back to Demo mode instead of crashing.

## Mic Mode

Mic mode attempts a modular microphone graph:

- `AudioDeviceInput`
- `AudioAnalyzer`
- `Wire`

Raw microphone samples are not available to this code path and are never treated as available. The controller only reads analyzer values such as RMS, peak, and spectrum when supported.

If microphone APIs, permission, or eligibility are unavailable, the UI reports `Mic unavailable - using demo pulse` and returns to Demo mode.

## Privacy

Raw microphone data, raw audio samples, spectrum data, RMS, peak, bass, and beat frames are never saved and never sent to the server.
