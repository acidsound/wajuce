import 'audio_node.dart';

/// A node that splits a multi-channel signal into multiple mono outputs.
/// Mirrors Web Audio API ChannelSplitterNode.
class WAChannelSplitterNode extends WANode {
  final int _numberOfOutputs;

  WAChannelSplitterNode({
    required super.nodeId,
    required super.contextId,
    int numberOfOutputs = 6,
  }) : _numberOfOutputs = numberOfOutputs;

  @override
  int get numberOfInputs => 1;

  @override
  int get numberOfOutputs => _numberOfOutputs;
}
