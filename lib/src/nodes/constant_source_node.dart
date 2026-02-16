import 'audio_scheduled_source_node.dart';
import '../audio_param.dart';
import '../backend/backend.dart' as backend;

/// Constant source node that outputs a DC signal.
/// Mirrors Web Audio API ConstantSourceNode.
class WAConstantSourceNode extends WAScheduledSourceNode {
  /// Offset value of the generated constant signal.
  late final WAParam offset;

  /// Creates a new ConstantSourceNode.
  WAConstantSourceNode({
    required super.nodeId,
    required super.contextId,
  }) {
    offset = WAParam(
      nodeId: nodeId,
      paramName: 'offset',
      defaultValue: 1.0,
      minValue: -3.4028235e38,
      maxValue: 3.4028235e38,
    );
  }

  @override
  int get numberOfInputs => 0;

  @override
  int get numberOfOutputs => 1;

  @override
  void start([double when = 0]) {
    if (isDisposed) return;
    markStarted();
    backend.constantSourceStart(nodeId, when);
  }

  @override
  void stop([double when = 0]) {
    if (isDisposed || hasEnded) return;
    backend.constantSourceStop(nodeId, when);
    scheduleStopAutoDispose(when);
  }
}
