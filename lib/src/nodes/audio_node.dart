import '../enums.dart';
import '../backend/backend.dart' as backend;

/// Base class for all audio nodes. Mirrors the Web Audio API AudioNode.
abstract class WANode {
  final int _nodeId;
  final int _contextId;

  /// How channels are mapped when connecting nodes.
  WAChannelCountMode channelCountMode;
  /// How to interpret channels (speakers vs discrete).
  WAChannelInterpretation channelInterpretation;
  /// The number of channels used by this node.
  int channelCount;

  /// Base constructor for all audio nodes.
  WANode({
    required int nodeId,
    required int contextId,
    this.channelCount = 2,
    this.channelCountMode = WAChannelCountMode.max,
    this.channelInterpretation =
        WAChannelInterpretation.speakers,
  })  : _nodeId = nodeId,
        _contextId = contextId;

  /// Internal node ID used by the backend.
  int get nodeId => _nodeId;

  /// Internal context ID.
  int get contextId => _contextId;

  /// Number of inputs this node accepts.
  int get numberOfInputs;

  /// Number of outputs this node produces.
  int get numberOfOutputs;

  /// Connect this node's output to the input of [destination].
  ///
  /// Optionally specify [output] and [input] channel indices.
  WANode connect(WANode destination, {int output = 0, int input = 0}) {
    backend.connect(_contextId, _nodeId, destination.nodeId, output, input);
    return destination;
  }

  /// Disconnect this node from all destinations, or from a specific
  /// [destination].
  void disconnect([WANode? destination]) {
    if (destination != null) {
      backend.disconnect(_contextId, _nodeId, destination.nodeId);
    } else {
      backend.disconnectAll(_contextId, _nodeId);
    }
  }

  /// Free this node's native resources.
  void dispose() {
    backend.removeNode(_contextId, _nodeId);
  }
}
