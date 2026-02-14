import 'audio_node.dart';

/// Audio source node backed by an HTMLMediaElement (web).
/// Mirrors Web Audio API MediaElementAudioSourceNode.
class WAMediaElementSourceNode extends WANode {
  /// Backing media element object (web only).
  final dynamic mediaElement;

  /// Creates a new MediaElementAudioSourceNode wrapper.
  WAMediaElementSourceNode({
    required super.nodeId,
    required super.contextId,
    required this.mediaElement,
  });

  @override
  int get numberOfInputs => 0;

  @override
  int get numberOfOutputs => 1;
}
