import '../enums.dart';
import '../backend/backend.dart' as backend;

/// Base class for all audio nodes. Mirrors the Web Audio API AudioNode.
abstract class WANode {
  final int _nodeId;
  final int _contextId;
  final Set<WANode> _ownedDownstream = <WANode>{};
  bool _isDisposed = false;

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
    this.channelInterpretation = WAChannelInterpretation.speakers,
  })  : _nodeId = nodeId,
        _contextId = contextId;

  /// Internal node ID used by the backend.
  int get nodeId => _nodeId;

  /// Internal context ID.
  int get contextId => _contextId;

  /// `true` once this node has been disposed.
  bool get isDisposed => _isDisposed;

  /// Whether this node can be auto-disposed by owned-cascade.
  bool get canBeCascadeDisposed => true;

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

  /// Connect and mark [destination] as owned by this node.
  ///
  /// Owned nodes are recursively auto-disposed when this node is disposed.
  WANode connectOwned(WANode destination, {int output = 0, int input = 0}) {
    if (destination.canBeCascadeDisposed) {
      _ownedDownstream.add(destination);
    }
    return connect(destination, output: output, input: input);
  }

  /// Disconnect this node from all destinations, or from a specific
  /// [destination].
  void disconnect([WANode? destination]) {
    if (destination != null) {
      _ownedDownstream.remove(destination);
      backend.disconnect(_contextId, _nodeId, destination.nodeId);
    } else {
      _ownedDownstream.clear();
      backend.disconnectAll(_contextId, _nodeId);
    }
  }

  /// Free this node's native resources.
  void dispose() {
    _disposeWithVisited(<WANode>{});
  }

  void _disposeWithVisited(Set<WANode> visited) {
    if (!visited.add(this) || _isDisposed) {
      return;
    }
    _isDisposed = true;
    _disposeOwnedSubgraph(visited);
    backend.removeNode(_contextId, _nodeId);
  }

  void _disposeOwnedSubgraph(Set<WANode> visited) {
    final owned = _ownedDownstream.toList(growable: false);
    _ownedDownstream.clear();
    for (final node in owned) {
      if (!node.canBeCascadeDisposed) {
        continue;
      }
      node._disposeWithVisited(visited);
    }
  }
}
