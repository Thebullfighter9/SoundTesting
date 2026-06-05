# SoundTesting: Resonance Field

A Roblox audio visualizer test scene.

The visualizer is the project. A client builds a field of parts and moves it from the audio signal Roblox gives back. The default track is `9043887091`.

The important detail is the signal label in the top pill:

- `Spectrum` means `AudioAnalyzer:GetSpectrum()` is working. Row mode can act like real frequency bars.
- `Loudness` means Roblox only gave amplitude data. It still moves, but it is not a per-frequency display.
- `Demo` means the local demo signal is active.
- `Silent` means nothing is driving the field.

Views:

- `Grid` is the main field.
- `Row` is the clearest readout.
- `Circle` wraps the response around the center.

