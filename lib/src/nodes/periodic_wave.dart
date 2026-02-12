import 'dart:typed_data';

/// Defines a periodic waveform that can be used to shape the output of an OscillatorNode.
/// Mirrors Web Audio API PeriodicWave.
class WAPeriodicWave {
  /// The real part of the periodic wave (cosine terms).
  final Float32List real;
  /// The imaginary part of the periodic wave (sine terms).
  final Float32List imag;
  /// If true, the wave is not normalized to -1..1 range.
  final bool disableNormalization;

  /// Creates a new periodic wave.
  WAPeriodicWave({
    required this.real,
    required this.imag,
    this.disableNormalization = false,
  });
}
