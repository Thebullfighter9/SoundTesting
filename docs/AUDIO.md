# Audio

ArrayWave keeps all audio analysis local to the client. Audio frames are presentation data, not server authority.

## Demo Mode

Demo mode starts immediately. It synthesizes a signal with layered sine waves, a kick-like pulse, slow bass motion, and `math.noise` variation. The controller produces 32 changing bands, RMS, peak, bass, beat, and frame time.

`ResonanceController` also has a fallback band synthesizer. If the audio frame is unavailable or all bands are flat, Grid, Row, and Circle modes still receive useful band values from RMS, peak, bass, and time.

## Asset Mode

Asset mode trims the text box input and accepts numeric asset IDs only. Empty, nonnumeric, negative, or excessively long input is rejected.

The client first attempts a modular audio graph:

- `AudioPlayer`
- `AudioAnalyzer`
- `Wire`
- `AudioDeviceOutput` when supported

Analyzer reads prefer `RmsLevel`, `PeakLevel`, and `GetSpectrum()` when available. If spectrum access fails, bands are synthesized from RMS and peak.

If the modular graph cannot be created, the client tries a local `Sound` using `SoundId = "rbxassetid://<id>"` and reads `PlaybackLoudness`. Invalid or private assets return to Demo mode with a clear status.

## Mic Mode

Mic mode attempts supported modular audio only:

- `AudioDeviceInput`
- `AudioAnalyzer`
- `Wire`

The implementation does not claim access to raw microphone samples. If microphone APIs, permission, or eligibility are unavailable, the controller reports `Mic unavailable - using demo signal` and returns to Demo mode.

## Privacy

Raw microphone data, raw audio samples, spectrum arrays, RMS, peak, bass, and beat values are never saved and never sent to the server.
