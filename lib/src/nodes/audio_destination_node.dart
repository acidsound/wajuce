import 'audio_node.dart';

/// Represents the final destination of an audio graph.
/// Mirrors Web Audio API AudioDestinationNode.
class WADestinationNode extends WANode {
  final int _maxChannelCount;

  WADestinationNode({
    required super.nodeId,
    required super.contextId,
    int maxChannelCount = 2,
  }) : _maxChannelCount = maxChannelCount;

  /// The maximum number of channels supported.
  int get maxChannelCount => _maxChannelCount;

  @override
  int get numberOfInputs => 1;

  @override
  int get numberOfOutputs => 0;
}
