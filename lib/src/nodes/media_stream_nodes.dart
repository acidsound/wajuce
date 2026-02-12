import 'audio_node.dart';
import '../backend/backend.dart' as backend;

/// Represents an audio source from a media stream (e.g., microphone).
/// Mirrors Web Audio API MediaStreamAudioSourceNode.
class WAMediaStreamSourceNode extends WANode {
  /// Creates a new MediaStreamSourceNode.
  WAMediaStreamSourceNode({
    required super.nodeId,
    required super.contextId,
  });

  @override
  int get numberOfInputs => 0;

  @override
  int get numberOfOutputs => 1;
}

/// Represents an audio destination that records to a media stream.
/// Mirrors Web Audio API MediaStreamAudioDestinationNode.
class WAMediaStreamDestNode extends WANode {
  /// Creates a new MediaStreamAudioDestinationNode.
  WAMediaStreamDestNode({
    required super.nodeId,
    required super.contextId,
  }) {
    // MediaStreamDestination usually has a 'stream' property
  }

  @override
  int get numberOfInputs => 1;

  @override
  int get numberOfOutputs => 0;
}
