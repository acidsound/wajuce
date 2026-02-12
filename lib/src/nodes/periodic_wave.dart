import 'dart:typed_data';

/// Defines a periodic waveform that can be used to shape the output of an OscillatorNode.
/// Mirrors Web Audio API PeriodicWave.
class WAPeriodicWave {
  final Float32List real;
  final Float32List imag;
  final bool disableNormalization;

  WAPeriodicWave({
    required this.real,
    required this.imag,
    this.disableNormalization = false,
  });
}
