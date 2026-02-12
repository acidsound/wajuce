import '../nodes/audio_node.dart';
import 'wa_worklet.dart';

/// An AudioWorkletNode — connects a custom processor to the audio graph.
/// Mirrors Web Audio API AudioWorkletNode.
///
/// ```dart
/// final dx7 = WAWorkletNode(
///   ctx,
///   'dx7-processor',
///   parameterDefaults: {'gain': 0.8},
/// );
/// dx7.connect(ctx.destination);
/// dx7.port.postMessage({'type': 'noteOn', 'note': 60});
/// ```
class WAWorkletNode extends WANode {
  final String _processorName;
  final WAWorklet _worklet;

  /// The message port for bidirectional communication with the processor.
  late final WAMessagePort port;

  /// Creates a new AudioWorkletNode.
  WAWorkletNode({
    required super.nodeId,
    required super.contextId,
    required String processorName,
    required WAWorklet worklet,
    Map<String, double> parameterDefaults = const {},
  })  : _processorName = processorName,
        _worklet = worklet {
    // Create the processor in the audio isolate
    // On native JUCE, the nodeId IS the bridgeId (returned from createWorkletNode)
    _worklet.createNode(nodeId, processorName,
        paramDefaults: parameterDefaults, bridgeId: nodeId);

    // Set up bidirectional message port
    port = WAMessagePort(
      nodeId: nodeId,
      worklet: _worklet,
    );

    // Listen for messages from the processor
    _worklet.addMessageListener(nodeId, (data) {
      port.onMessage?.call(data);
    });
  }

  /// The name of the registered processor.
  String get processorName => _processorName;

  @override
  int get numberOfInputs => 1;

  @override
  int get numberOfOutputs => 1;

  /// Destroy the processor.
  void destroy() {
    _worklet.removeNode(nodeId);
  }
}

/// Message port for bidirectional communication between main thread and worklet.
/// Mirrors Web Audio API MessagePort on AudioWorkletNode.
class WAMessagePort {
  final int _nodeId;
  final WAWorklet _worklet;

  /// Callback for messages received from the processor (audio → main thread).
  void Function(dynamic)? onMessage;

  /// Creates a new message port for the given node.
  WAMessagePort({required int nodeId, required WAWorklet worklet})
      : _nodeId = nodeId,
        _worklet = worklet;

  /// Send a message to the processor (main → audio thread).
  void postMessage(dynamic message) {
    _worklet.postMessage(_nodeId, message);
  }
}
