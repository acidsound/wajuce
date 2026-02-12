import 'audio_node.dart';
import '../audio_param.dart';
import '../enums.dart';
import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart' as ffi;
import 'periodic_wave.dart';
import '../backend/backend.dart' as backend;


/// An oscillator that generates a periodic waveform.
/// Mirrors Web Audio API OscillatorNode.
class WAOscillatorNode extends WANode {
  /// The frequency of the oscillator in Hertz.
  late final WAParam frequency;
  /// The detuning value in cents.
  late final WAParam detune;
  WAOscillatorType _type = WAOscillatorType.sine;

  /// Creates a new OscillatorNode.
  WAOscillatorNode({
    required super.nodeId,
    required super.contextId,
  }) {
    frequency = WAParam(
      nodeId: nodeId,
      paramName: 'frequency',
      defaultValue: 440.0,
      minValue: -22050.0,
      maxValue: 22050.0,
    );
    detune = WAParam(
      nodeId: nodeId,
      paramName: 'detune',
      defaultValue: 0.0,
      minValue: -153600.0,
      maxValue: 153600.0,
    );
  }

  @override
  int get numberOfInputs => 0;

  @override
  int get numberOfOutputs => 1;

  /// The waveform type.
  WAOscillatorType get type => _type;
  set type(WAOscillatorType t) {
    _type = t;
    backend.oscSetType(nodeId, t.index);
  }

  /// Start the oscillator at the given time (in seconds).
  void start([double when = 0]) {
    backend.oscStart(nodeId, when);
  }

  /// Stop the oscillator at the given time.
  void stop([double when = 0]) {
    backend.oscStop(nodeId, when);
  }

  /// Set a custom PeriodicWave waveform.
  void setPeriodicWave(WAPeriodicWave periodicWave) {
    _type = WAOscillatorType.custom;
    
    // We need to pass the arrays to C++
    // Allocate temporary memory for the call
    final len = periodicWave.real.length;
    if (len != periodicWave.imag.length) {
      throw ArgumentError('Real and Imag arrays must have same length');
    }

    ffi.Arena arena = ffi.Arena();
    try {
      final pReal = arena<ffi.Float>(len);
      final pImag = arena<ffi.Float>(len);
      
      for(int i=0; i<len; ++i) {
        pReal[i] = periodicWave.real[i];
        pImag[i] = periodicWave.imag[i];
      }
      
      backend.oscSetPeriodicWave(nodeId, pReal, pImag, len);
    } finally {
      arena.releaseAll();
    }
  }
}
