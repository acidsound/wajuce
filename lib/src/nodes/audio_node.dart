import '../enums.dart';
import '../audio_param.dart';
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
    _validateSameContext(destination.contextId);
    _validateOutput(output);
    if (input < 0 || input >= destination.numberOfInputs) {
      throw RangeError.value(
        input,
        'input',
        'Destination has ${destination.numberOfInputs} input(s)',
      );
    }
    backend.connect(_contextId, _nodeId, destination.nodeId, output, input);
    return destination;
  }

  /// Connect this node's output to a [WAParam]-style destination.
  ///
  /// This mirrors Web Audio's `AudioNode.connect(AudioParam)` overload. The
  /// source output is down-mixed to mono before it modulates the parameter.
  void connectParam(WAParam destination, {int output = 0}) {
    _validateSameContext(destination.contextId);
    _validateOutput(output);
    backend.connectParam(
      _contextId,
      _nodeId,
      destination.nodeId,
      destination.paramName,
      output,
    );
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
      _validateSameContext(destination.contextId);
      _ownedDownstream.remove(destination);
      backend.disconnect(_contextId, _nodeId, destination.nodeId);
    } else {
      _ownedDownstream.clear();
      backend.disconnectAll(_contextId, _nodeId);
    }
  }

  /// Disconnect every outgoing connection from a specific [output].
  void disconnectOutput(int output) {
    _validateOutput(output);
    _ownedDownstream.clear();
    backend.disconnectOutput(_contextId, _nodeId, output);
  }

  /// Disconnect this node from [destination] with optional output/input
  /// filtering.
  void disconnectFrom(WANode destination, {int? output, int? input}) {
    _validateSameContext(destination.contextId);
    _ownedDownstream.remove(destination);
    if (output == null && input == null) {
      backend.disconnect(_contextId, _nodeId, destination.nodeId);
      return;
    }
    if (output == null) {
      throw ArgumentError.value(
        input,
        'input',
        'Cannot specify input without output',
      );
    }
    _validateOutput(output);
    if (input == null) {
      backend.disconnectNodeOutput(
        _contextId,
        _nodeId,
        destination.nodeId,
        output,
      );
      return;
    }
    if (input < 0 || input >= destination.numberOfInputs) {
      throw RangeError.value(
        input,
        'input',
        'Destination has ${destination.numberOfInputs} input(s)',
      );
    }
    backend.disconnectNodeInput(
      _contextId,
      _nodeId,
      destination.nodeId,
      output,
      input,
    );
  }

  /// Disconnect this node's output from a [WAParam]-style destination.
  void disconnectParam(WAParam destination, {int output = 0}) {
    _validateSameContext(destination.contextId);
    _validateOutput(output);
    backend.disconnectParam(
      _contextId,
      _nodeId,
      destination.nodeId,
      destination.paramName,
      output,
    );
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

  void _validateSameContext(int destinationContextId) {
    if (_contextId != destinationContextId) {
      throw ArgumentError.value(
        destinationContextId,
        'destination',
        'Destination belongs to a different audio context',
      );
    }
  }

  void _validateOutput(int output) {
    if (output < 0 || output >= numberOfOutputs) {
      throw RangeError.value(
        output,
        'output',
        'Node has $numberOfOutputs output(s)',
      );
    }
  }
}
