# Audio Notes

Resonance Field starts in Demo mode so the piece works immediately without uploaded audio or microphone access.

## Demo Mode

Demo mode synthesizes a smooth audio frame on the client:

- band values
- RMS
- peak
- bass
- beat boolean
- frame time

The generated signal is intentionally calm and sculptural rather than aggressive.

## Asset Mode

Asset input is sanitized to numeric Roblox asset IDs. Empty, negative, nonnumeric, or excessively long inputs are rejected.

The client first attempts a modular graph:

- `AudioPlayer`
- `AudioAnalyzer`
- `AudioDeviceOutput`
- `Wire`

If the graph is unavailable or unsupported, the client tries a local `Sound` and reads `PlaybackLoudness`. Private or invalid assets fall back to Demo mode.

## Mic Mode

Mic mode attempts a modular microphone graph:

- `AudioDeviceInput`
- `AudioAnalyzer`
- `Wire`

The implementation does not assume raw microphone samples are available. It only reads analyzer values when Roblox exposes them for the local player.

## Privacy

Raw audio, microphone data, spectrum arrays, RMS, peak, bass, and beat frames are never sent to the server.
