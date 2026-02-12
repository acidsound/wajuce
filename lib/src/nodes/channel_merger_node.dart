import 'audio_node.dart';

/// A node that merges multiple mono inputs into a single multi-channel output.
/// Mirrors Web Audio API ChannelMergerNode.
class WAChannelMergerNode extends WANode {
  final int _numberOfInputs;

  /// Creates a new ChannelMergerNode.
  WAChannelMergerNode({
    required super.nodeId,
    required super.contextId,
    int numberOfInputs = 6,
  }) : _numberOfInputs = numberOfInputs;

  @override
  int get numberOfInputs => _numberOfInputs;

  @override
  int get numberOfOutputs => 1;
}
