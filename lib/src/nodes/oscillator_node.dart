import 'audio_node.dart';
import '../audio_param.dart';
import '../enums.dart';
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
  void setPeriodicWave(/* WAPeriodicWave */ dynamic periodicWave) {
    _type = WAOscillatorType.custom;
    // TODO: Implement PeriodicWave pass-through
  }
}
