import 'audio_node.dart';

/// Audio source node backed by a specific MediaStreamTrack (web).
/// Mirrors Web Audio API MediaStreamTrackAudioSourceNode.
class WAMediaStreamTrackSourceNode extends WANode {
  /// Backing track object (web only).
  final dynamic mediaStreamTrack;

  /// Creates a new MediaStreamTrackAudioSourceNode wrapper.
  WAMediaStreamTrackSourceNode({
    required super.nodeId,
    required super.contextId,
    required this.mediaStreamTrack,
  });

  @override
  int get numberOfInputs => 0;

  @override
  int get numberOfOutputs => 1;
}
