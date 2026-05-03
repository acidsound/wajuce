// ignore_for_file: public_member_api_docs
/// Stub for AudioIsolateManager — used on platforms where Dart isolates
/// are not used for audio processing (e.g. Web).
library;

import 'dart:async';
import 'wa_worklet_processor.dart';

import 'dart:typed_data';
import '../backend/backend.dart' as backend;

/// On Web, this runs on the main thread, driven by the AudioWorklet clock
/// via backend callbacks.
class AudioIsolateManager {
  void Function(int nodeId, dynamic data)? onProcessorMessage;
  void Function(int nodeId)? onNodeEnded;
  void Function(int nodeId)? onNodeRemoved;

  final Map<String, WAWorkletProcessor Function()> _factories = {};
  final Map<int, WAWorkletProcessor> _processorNodes = {};
  final Map<int, Map<String, double>> _paramDefaults = {};
  final Map<int, Map<String, Float32List>> _parameterBlocks = {};

  Future<void> start({
    required int sampleRate,
    int bufferSize = 128,
    int numInputs = 0,
    int numOutputs = 2,
  }) async {
    // Register the callback from backend_web.dart
    // This connects the JS AudioWorklet 'tick' to this manager
    backend.onWebProcessQuantum = _onProcessQuantum;
  }

  void registerProcessor(String name, WAWorkletProcessor Function() factory) {
    _factories[name] = factory;
  }

  void createNode(int contextId, int nodeId, String processorName,
      {Map<String, double> paramDefaults = const {}, int? bridgeId}) {
    _processorNodes.remove(nodeId)?.dispose();

    final factory = _factories[processorName];
    if (factory != null) {
      final processor = factory();
      processor.init(paramDefaults);

      // Bind outgoing messages (Processor -> Main)
      processor.port.bind((data) {
        onProcessorMessage?.call(nodeId, data);
      });

      _processorNodes[nodeId] = processor;
      final defaults = _workletParamDefaults(paramDefaults);
      _paramDefaults[nodeId] = defaults;
      _parameterBlocks[nodeId] = _createParameterBlocks(defaults);
    }
  }

  void removeNode(int nodeId) {
    _processorNodes.remove(nodeId)?.dispose();
    _paramDefaults.remove(nodeId);
    _parameterBlocks.remove(nodeId);
    onNodeRemoved?.call(nodeId);
  }

  void postMessage(int nodeId, dynamic data) {
    final processor = _processorNodes[nodeId];
    processor?.port.onMessage?.call(data);
  }

  Future<void> stop() async {
    for (final processor in _processorNodes.values) {
      processor.dispose();
    }
    _processorNodes.clear();
    _paramDefaults.clear();
    _parameterBlocks.clear();
    if (identical(backend.onWebProcessQuantum, _onProcessQuantum)) {
      backend.onWebProcessQuantum = null;
    }
  }

  // Driven by AudioWorklet (JS) -> Backend (Dart) -> Here
  void _onProcessQuantum(int nodeId) {
    final processor = _processorNodes[nodeId];
    if (processor != null) {
      // Create empty buffers for now as we are focusing on Logic/Clock
      // WAWorkletProcessor expects List<List<Float32List>> (Buses -> Channels -> Samples)
      // We simulate 1 bus with 2 channels (Stereo)
      final inputs = [
        [Float32List(128), Float32List(128)]
      ];
      final outputs = [
        [Float32List(128), Float32List(128)]
      ];

      final defaults = _paramDefaults[nodeId] ?? const <String, double>{};
      final parameters =
          _parameterBlocks[nodeId] ?? const <String, Float32List>{};
      _refreshParameterBlocks(nodeId, defaults, parameters);
      final keepAlive = processor.process(inputs, outputs, parameters);
      if (!keepAlive) {
        _processorNodes.remove(nodeId)?.dispose();
        _paramDefaults.remove(nodeId);
        _parameterBlocks.remove(nodeId);
        onNodeEnded?.call(nodeId);
      }
    }
  }
}

Map<String, double> _workletParamDefaults(Map<String, double> defaults) {
  final result = <String, double>{};
  for (final entry in defaults.entries) {
    if (entry.key == 'sampleRate') continue;
    result[entry.key] = entry.value;
  }
  return result;
}

Map<String, Float32List> _createParameterBlocks(Map<String, double> defaults) {
  final params = <String, Float32List>{};
  for (final entry in defaults.entries) {
    params[entry.key] = Float32List(128)..fillRange(0, 128, entry.value);
  }
  return params;
}

void _refreshParameterBlocks(
  int nodeId,
  Map<String, double> defaults,
  Map<String, Float32List> parameters,
) {
  for (final entry in defaults.entries) {
    final value = backend.paramGet(nodeId, entry.key);
    final block = parameters.putIfAbsent(entry.key, () => Float32List(128));
    block.fillRange(0, 128, value.isFinite ? value : entry.value);
  }
}
