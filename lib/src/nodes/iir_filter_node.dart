import 'dart:typed_data';

import 'audio_node.dart';
import '../backend/backend.dart' as backend;

/// Infinite impulse response filter node.
/// Mirrors Web Audio API IIRFilterNode.
class WAIIRFilterNode extends WANode {
  /// Feed-forward coefficients.
  final Float64List feedforward;

  /// Feed-back coefficients.
  final Float64List feedback;

  /// Creates a new IIRFilterNode.
  WAIIRFilterNode({
    required super.nodeId,
    required super.contextId,
    required this.feedforward,
    required this.feedback,
  });

  @override
  int get numberOfInputs => 1;

  @override
  int get numberOfOutputs => 1;

  /// Computes the filter frequency response at [frequencyHz].
  void getFrequencyResponse(
    Float32List frequencyHz,
    Float32List magResponse,
    Float32List phaseResponse,
  ) {
    backend.iirGetFrequencyResponse(
        nodeId, frequencyHz, magResponse, phaseResponse);
  }
}
