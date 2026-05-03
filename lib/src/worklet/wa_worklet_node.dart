import '../nodes/audio_node.dart';
import '../audio_param.dart';
import '../backend/backend.dart' as backend;
import '../enums.dart';
import 'wa_worklet.dart';
import 'wa_worklet_module.dart';
import 'audio_param_map.dart';

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
  bool _isDisposed = false;

  /// The message port for bidirectional communication with the processor.
  late final WAMessagePort port;

  /// Worklet parameter map (minimal parity for AudioParamMap).
  late final WAAudioParamMap parameters;

  /// Creates a new AudioWorkletNode.
  WAWorkletNode({
    required super.nodeId,
    required super.contextId,
    required String processorName,
    required WAWorklet worklet,
    Map<String, double> parameterDefaults = const {},
    Map<String, WAWorkletParameterDescriptor> parameterDescriptors = const {},
  })  : _processorName = processorName,
        _worklet = worklet {
    final effectiveDefaults = <String, double>{
      'sampleRate': worklet.currentSampleRate,
      ...parameterDefaults,
    };

    // Create the processor in the audio isolate
    // On native backends, nodeId is the bridgeId returned from createWorkletNode.
    _worklet.createNode(nodeId, processorName,
        paramDefaults: effectiveDefaults, bridgeId: nodeId);

    // Set up bidirectional message port
    port = WAMessagePort(
      nodeId: nodeId,
      worklet: _worklet,
    );

    final params = <String, WAParam>{};
    for (final entry in parameterDefaults.entries) {
      final descriptor = parameterDescriptors[entry.key];
      params[entry.key] = WAParam(
        contextId: contextId,
        nodeId: nodeId,
        paramName: entry.key,
        defaultValue: entry.value,
        minValue: descriptor?.minValue ?? -3.4028235e38,
        maxValue: descriptor?.maxValue ?? 3.4028235e38,
        automationRate: descriptor?.automationRate ?? WAAutomationRate.aRate,
      );
      backend.paramSet(nodeId, entry.key, entry.value);
    }
    parameters = WAAudioParamMap(params);

    // Listen for messages from the processor
    _worklet.addMessageListener(nodeId, (data) {
      port.onMessage?.call(data);
    });
    _worklet.registerNodeDisposer(nodeId, dispose);
  }

  /// The name of the registered processor.
  String get processorName => _processorName;

  @override
  int get numberOfInputs => 1;

  @override
  int get numberOfOutputs => 1;

  /// Destroy the processor.
  void destroy() {
    dispose();
  }

  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _worklet.unregisterNodeDisposer(nodeId);
    _worklet.removeMessageListener(nodeId);
    _worklet.removeNode(nodeId);
    super.dispose();
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
