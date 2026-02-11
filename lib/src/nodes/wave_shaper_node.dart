import 'dart:typed_data';

import 'audio_node.dart';
import '../enums.dart';
import '../backend/backend.dart' as backend;

/// Distortion / saturation via a shaping curve.
/// Mirrors Web Audio API WaveShaperNode.
class WAWaveShaperNode extends WANode {
  Float32List? _curve;
  WAOverSampleType _oversample = WAOverSampleType.none;

  /// Creates a new WaveShaperNode.
  WAWaveShaperNode({
    required super.nodeId,
    required super.contextId,
  });

  @override
  int get numberOfInputs => 1;

  @override
  int get numberOfOutputs => 1;

  /// The shaping curve. Null means no shaping (pass-through).
  Float32List? get curve => _curve;
  set curve(Float32List? c) {
    _curve = c;
    if (c != null) {
      backend.waveShaperSetCurve(nodeId, c);
    }
  }

  /// Oversampling mode to reduce aliasing.
  WAOverSampleType get oversample => _oversample;
  set oversample(WAOverSampleType o) {
    _oversample = o;
    backend.waveShaperSetOversample(nodeId, o.index);
  }
}
