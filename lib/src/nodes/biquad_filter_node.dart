import 'dart:typed_data';

import 'audio_node.dart';
import '../audio_param.dart';
import '../enums.dart';
import '../backend/backend.dart' as backend;

/// A second-order IIR filter node.
/// Mirrors Web Audio API BiquadFilterNode.
class WABiquadFilterNode extends WANode {
  late final WAParam frequency;
  late final WAParam detune;
  late final WAParam Q;
  late final WAParam gain;
  WABiquadFilterType _type = WABiquadFilterType.lowpass;

  WABiquadFilterNode({
    required super.nodeId,
    required super.contextId,
  }) {
    frequency = WAParam(
      nodeId: nodeId,
      paramName: 'frequency',
      defaultValue: 350.0,
      minValue: 0.0,
      maxValue: 22050.0,
    );
    detune = WAParam(
      nodeId: nodeId,
      paramName: 'detune',
      defaultValue: 0.0,
      minValue: -153600.0,
      maxValue: 153600.0,
    );
    Q = WAParam(
      nodeId: nodeId,
      paramName: 'Q',
      defaultValue: 1.0,
      minValue: -3.4028235e38,
      maxValue: 3.4028235e38,
    );
    gain = WAParam(
      nodeId: nodeId,
      paramName: 'gain',
      defaultValue: 0.0,
      minValue: -3.4028235e38,
      maxValue: 3.4028235e38,
    );
  }

  @override
  int get numberOfInputs => 1;

  @override
  int get numberOfOutputs => 1;

  /// The filter type (lowpass, highpass, bandpass, etc.)
  WABiquadFilterType get type => _type;
  set type(WABiquadFilterType t) {
    _type = t;
    backend.filterSetType(nodeId, t.index);
  }

  /// Get the frequency response for the given frequencies.
  void getFrequencyResponse(
    Float32List frequencyHz,
    Float32List magResponse,
    Float32List phaseResponse,
  ) {
    // TODO: Implement native getFrequencyResponse when available
  }
}
