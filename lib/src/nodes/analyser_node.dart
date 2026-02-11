import 'dart:typed_data';

import 'audio_node.dart';
import '../backend/backend.dart' as backend;

/// Provides real-time frequency and time-domain analysis.
/// Mirrors Web Audio API AnalyserNode.
class WAAnalyserNode extends WANode {
  int _fftSize = 2048;

  /// Maximum decibels for FFT analysis.
  double maxDecibels = -30.0;
  /// Minimum decibels for FFT analysis.
  double minDecibels = -100.0;
  double _smoothingTimeConstant = 0.8;

  /// Creates a new AnalyserNode.
  WAAnalyserNode({
    required super.nodeId,
    required super.contextId,
  });

  @override
  int get numberOfInputs => 1;

  @override
  int get numberOfOutputs => 1;

  /// The size of the FFT (Fast Fourier Transform) used for frequency analysis.
  /// Must be a power of two between 32 and 32768.
  int get fftSize => _fftSize;
  set fftSize(int size) {
    assert(size >= 32 && size <= 32768 && (size & (size - 1)) == 0,
        'fftSize must be a power of 2 between 32 and 32768');
    _fftSize = size;
    backend.analyserSetFftSize(nodeId, size);
  }

  /// The number of frequency bins (half of [fftSize]).
  int get frequencyBinCount => _fftSize ~/ 2;

  /// Smoothing constant for frequency data (0.0 to 1.0).
  double get smoothingTimeConstant => _smoothingTimeConstant;
  set smoothingTimeConstant(double v) =>
      _smoothingTimeConstant = v.clamp(0.0, 1.0);

  /// Copies current frequency-domain data into [array].
  void getByteFrequencyData(Uint8List array) {
    final result = backend.analyserGetByteFrequencyData(nodeId, array.length);
    array.setAll(0, result);
  }

  /// Copies current time-domain data into [array].
  void getByteTimeDomainData(Uint8List array) {
    final result = backend.analyserGetByteTimeDomainData(nodeId, array.length);
    array.setAll(0, result);
  }

  /// Copies current frequency-domain data (Float32) into [array].
  void getFloatFrequencyData(Float32List array) {
    final result =
        backend.analyserGetFloatFrequencyData(nodeId, array.length);
    array.setAll(0, result);
  }

  /// Copies current time-domain data (Float32) into [array].
  void getFloatTimeDomainData(Float32List array) {
    final result =
        backend.analyserGetFloatTimeDomainData(nodeId, array.length);
    array.setAll(0, result);
  }
}
