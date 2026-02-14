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

  final Map<String, WAWorkletProcessor Function()> _factories = {};
  final Map<int, WAWorkletProcessor> _processorNodes = {};

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

  void createNode(int nodeId, String processorName,
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
    }
  }

  void removeNode(int nodeId) {
    _processorNodes.remove(nodeId)?.dispose();
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

      final keepAlive = processor.process(inputs, outputs, {});
      if (!keepAlive) {
        _processorNodes.remove(nodeId)?.dispose();
      }
    }
  }
}
