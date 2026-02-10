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
  late final WAMessagePort port;

  WAWorkletNode({
    required super.nodeId,
    required super.contextId,
    required String processorName,
    required WAWorklet worklet,
    Map<String, double> parameterDefaults = const {},
  })  : _processorName = processorName,
        _worklet = worklet {
    // Create the processor in the audio isolate
    _worklet.createNode(nodeId, processorName, parameterDefaults);

    // Set up bidirectional message port
    port = WAMessagePort(
      nodeId: nodeId,
      worklet: _worklet,
    );

    // Listen for messages from the processor
    _worklet.onProcessorMessage = (id, data) {
      if (id == nodeId) {
        port.onMessage?.call(data);
      }
    };
  }

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
  void Function(dynamic)? onMessage;

  WAMessagePort({required int nodeId, required WAWorklet worklet})
      : _nodeId = nodeId,
        _worklet = worklet;

  /// Send a message to the processor (main → audio thread).
  void postMessage(dynamic message) {
    _worklet.postMessage(_nodeId, message);
  }
}
