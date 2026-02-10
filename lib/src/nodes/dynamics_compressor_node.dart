import 'audio_node.dart';
import '../audio_param.dart';

/// A dynamics compressor node. Mirrors Web Audio API DynamicsCompressorNode.
class WADynamicsCompressorNode extends WANode {
  late final WAParam threshold;
  late final WAParam knee;
  late final WAParam ratio;
  late final WAParam attack;
  late final WAParam release;

  // reduction is read-only, obtained from backend
  final double _reduction = 0.0;

  WADynamicsCompressorNode({
    required super.nodeId,
    required super.contextId,
  }) {
    threshold = WAParam(
      nodeId: nodeId,
      paramName: 'threshold',
      defaultValue: -24.0,
      minValue: -100.0,
      maxValue: 0.0,
    );
    knee = WAParam(
      nodeId: nodeId,
      paramName: 'knee',
      defaultValue: 30.0,
      minValue: 0.0,
      maxValue: 40.0,
    );
    ratio = WAParam(
      nodeId: nodeId,
      paramName: 'ratio',
      defaultValue: 12.0,
      minValue: 1.0,
      maxValue: 20.0,
    );
    attack = WAParam(
      nodeId: nodeId,
      paramName: 'attack',
      defaultValue: 0.003,
      minValue: 0.0,
      maxValue: 1.0,
    );
    release = WAParam(
      nodeId: nodeId,
      paramName: 'release',
      defaultValue: 0.25,
      minValue: 0.0,
      maxValue: 1.0,
    );
  }

  @override
  int get numberOfInputs => 1;

  @override
  int get numberOfOutputs => 1;

  /// Current gain reduction in dB (read-only).
  double get reduction => _reduction;
}
