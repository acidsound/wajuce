import 'audio_node.dart';

/// Represents an audio source from a media stream (e.g., microphone).
/// Mirrors Web Audio API MediaStreamAudioSourceNode.
class WAMediaStreamSourceNode extends WANode {
  /// Source MediaStream (web) when available.
  final dynamic mediaStream;

  /// Creates a new MediaStreamSourceNode.
  WAMediaStreamSourceNode({
    required super.nodeId,
    required super.contextId,
    this.mediaStream,
  });

  @override
  int get numberOfInputs => 0;

  @override
  int get numberOfOutputs => 1;
}

/// Represents an audio destination that records to a media stream.
/// Mirrors Web Audio API MediaStreamAudioDestinationNode.
class WAMediaStreamDestNode extends WANode {
  /// Destination MediaStream (web) when available.
  final dynamic stream;

  /// Creates a new MediaStreamAudioDestinationNode.
  WAMediaStreamDestNode({
    required super.nodeId,
    required super.contextId,
    this.stream,
  });

  @override
  int get numberOfInputs => 1;

  @override
  int get numberOfOutputs => 0;
}
