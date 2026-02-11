import 'audio_node.dart';
import '../audio_param.dart';

/// A delay line node. Mirrors Web Audio API DelayNode.
class WADelayNode extends WANode {
  /// The amount of delay to apply, in seconds.
  late final WAParam delayTime;
  final double _maxDelayTime;

  /// The maximum delay time this node supports.
  double get maxDelayTime => _maxDelayTime;

  /// Experimental: internal feedback parameter (not in standard Web Audio API).
  late final WAParam feedback;

  /// Creates a new DelayNode.
  WADelayNode({
    required super.nodeId,
    required super.contextId,
    double maxDelayTime = 1.0,
  }) : _maxDelayTime = maxDelayTime {
    delayTime = WAParam(
      nodeId: nodeId,
      paramName: 'delayTime',
      defaultValue: 0.0,
      minValue: 0.0,
      maxValue: maxDelayTime,
    );
    feedback = WAParam(
      nodeId: nodeId,
      paramName: 'feedback',
      defaultValue: 0.0,
      minValue: 0.0,
      maxValue: 1.0,
    );
  }

  @override
  int get numberOfInputs => 1;

  @override
  int get numberOfOutputs => 1;
}
