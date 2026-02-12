// ignore_for_file: public_member_api_docs
/// Audio Isolate — runs AudioWorklet processors in a separate Dart isolate.
///
/// This isolate handles:
/// - Receiving audio buffers from the native engine via ring buffers
/// - Running registered WAWorkletProcessor instances
/// - Sending processed audio back to the engine
/// - Message passing between main isolate and processors
library;

import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'wa_worklet_processor.dart';
import 'ring_buffer.dart';
import '../backend/backend_juce.dart' as backend;

const int quantumSize = 128;

/// Configuration passed to the audio isolate on startup.
class AudioIsolateConfig {
  final SendPort mainSendPort;
  final int sampleRate;
  final int bufferSize;
  final int numInputs;
  final int numOutputs;

  AudioIsolateConfig({
    required this.mainSendPort,
    required this.sampleRate,
    required this.bufferSize,
    this.numInputs = 0,
    this.numOutputs = 2,
  });
}

/// Messages sent between main and audio isolate.
sealed class AudioIsolateMessage {}

/// Register a processor factory in the audio isolate.
class RegisterProcessorMessage extends AudioIsolateMessage {
  final String name;
  final WAWorkletProcessor Function() factory;
  RegisterProcessorMessage(this.name, this.factory);
}

/// Create a processor instance from a registered factory.
class CreateNodeMessage extends AudioIsolateMessage {
  final int nodeId;
  final String processorName;
  final Map<String, double> parameterDefaults;
  final int? bridgeId; // If provided, use native ring buffers
  CreateNodeMessage(this.nodeId, this.processorName, this.parameterDefaults, {this.bridgeId});
}

/// Remove a processor instance.
class RemoveNodeMessage extends AudioIsolateMessage {
  final int nodeId;
  RemoveNodeMessage(this.nodeId);
}

/// Forward a message to a processor's port.
class ProcessorMessage extends AudioIsolateMessage {
  final int nodeId;
  final dynamic data;
  ProcessorMessage(this.nodeId, this.data);
}

/// Process a render quantum (128 samples).
class ProcessQuantumMessage extends AudioIsolateMessage {
  final int nodeId;
  final List<Float32List> inputData; // per-channel input
  ProcessQuantumMessage(this.nodeId, this.inputData);
}

/// Result of processing a quantum.
class ProcessedQuantumMessage extends AudioIsolateMessage {
  final int nodeId;
  final List<Float32List> outputData;
  ProcessedQuantumMessage(this.nodeId, this.outputData);
}

/// Port message from processor to main.
class PortMessage extends AudioIsolateMessage {
  final int nodeId;
  final dynamic data;
  PortMessage(this.nodeId, this.data);
}

/// Stop the audio isolate.
class StopIsolateMessage extends AudioIsolateMessage {}

/// Manages the audio processing isolate.
class AudioIsolateManager {
  Isolate? _isolate;
  SendPort? _isolateSendPort;
  ReceivePort? _mainReceivePort;
  final _readyCompleter = Completer<void>();

  /// Callbacks for messages from processors.
  void Function(int nodeId, dynamic data)? onProcessorMessage;

  /// Start the audio isolate.
  Future<void> start({
    required int sampleRate,
    required int bufferSize,
    int numInputs = 0,
    int numOutputs = 2,
  }) async {
    _mainReceivePort = ReceivePort();

    final config = AudioIsolateConfig(
      mainSendPort: _mainReceivePort!.sendPort,
      sampleRate: sampleRate,
      bufferSize: bufferSize,
      numInputs: numInputs,
      numOutputs: numOutputs,
    );

    _isolate = await Isolate.spawn(_audioIsolateEntry, config);

    _mainReceivePort!.listen((message) {
      if (message is SendPort) {
        _isolateSendPort = message;
        _readyCompleter.complete();
      } else if (message is PortMessage) {
        onProcessorMessage?.call(message.nodeId, message.data);
      } else if (message is ProcessedQuantumMessage) {
        // Handle processed quantum — feed back to native engine
        _onQuantumProcessed?.call(message);
      }
    });

    await _readyCompleter.future;
  }

  /// Register a processor class in the audio isolate.
  void registerProcessor(String name, WAWorkletProcessor Function() factory) {
    _isolateSendPort?.send(RegisterProcessorMessage(name, factory));
  }

  /// Create a processor node instance.
  void createNode(int nodeId, String processorName,
      {Map<String, double> paramDefaults = const {}, int? bridgeId}) {
    _isolateSendPort?.send(
        CreateNodeMessage(nodeId, processorName, paramDefaults, bridgeId: bridgeId));
  }

  /// Remove a processor node instance.
  void removeNode(int nodeId) {
    _isolateSendPort?.send(RemoveNodeMessage(nodeId));
  }

  /// Send a message to a processor.
  void postMessage(int nodeId, dynamic data) {
    _isolateSendPort?.send(ProcessorMessage(nodeId, data));
  }

  /// Submit a render quantum for processing.
  void processQuantum(int nodeId, List<Float32List> inputData) {
    _isolateSendPort?.send(ProcessQuantumMessage(nodeId, inputData));
  }

  /// Callback for when a quantum is processed.
  void Function(ProcessedQuantumMessage)? _onQuantumProcessed;
  set onQuantumProcessed(void Function(ProcessedQuantumMessage)? cb) {
    _onQuantumProcessed = cb;
  }

  /// Stop the audio isolate.
  Future<void> stop() async {
    _isolateSendPort?.send(StopIsolateMessage());
    await Future.delayed(const Duration(milliseconds: 100));
    _isolate?.kill();
    _mainReceivePort?.close();
    _isolate = null;
    _isolateSendPort = null;
    _mainReceivePort = null;
  }

  bool get isRunning => _isolate != null;
}

/// Entry point for the audio isolate.
void _audioIsolateEntry(AudioIsolateConfig config) {
  final receivePort = ReceivePort();
  config.mainSendPort.send(receivePort.sendPort);

  final processors = <String, WAWorkletProcessor Function()>{};
  final activeNodes = <int, WAWorkletProcessor>{};
  final bridgedNodes = <int, _BridgedNodeInfo>{};

  void runBridgedProcessing() {
    if (bridgedNodes.isEmpty) return;

    bool dataProcessed = false;
    for (final info in bridgedNodes.values) {
      if (info.toIsolate.available >= quantumSize) {
        // Read from native toIsolate buffer
        for (int ch = 0; ch < info.toIsolate.channelCount; ch++) {
           info.toIsolate.readChannel(ch, info.inputs[0][ch], 0, quantumSize);
        }

        // Process
        final keepAlive = info.processor.process(info.inputs, info.outputs, {});

        // Write to native fromIsolate buffer
        for (int ch = 0; ch < info.fromIsolate.channelCount; ch++) {
           info.fromIsolate.writeChannel(ch, info.outputs[0][ch], 0, quantumSize);
        }
        dataProcessed = true;

        if (!keepAlive) {
          info.processor.dispose();
          activeNodes.remove(info.nodeId);
          bridgedNodes.remove(info.nodeId);
        }
      }
    }

    // Schedule next processing pass
    if (dataProcessed) {
      // If we just processed data, check again as soon as possible
      Future.microtask(runBridgedProcessing);
    } else {
      // If no data was available, wait a tiny bit to avoid pinning the CPU
      // while remaining responsive to control messages.
      Future.delayed(Duration.zero, runBridgedProcessing);
    }
  }

  receivePort.listen((message) {
    if (message is RegisterProcessorMessage) {
      processors[message.name] = message.factory;
    } else if (message is CreateNodeMessage) {
      final factory = processors[message.processorName];
      if (factory != null) {
        final proc = factory();
        proc.init(message.parameterDefaults);
        proc.port.bind((data) {
           config.mainSendPort.send(PortMessage(message.nodeId, data));
        });
        activeNodes[message.nodeId] = proc;

        if (message.bridgeId != null) {
          // Initialize native ring buffers
          final bridgeId = message.bridgeId!;
          // We need access to the backend functions here.
          // Since it's a separate isolate, we might need a separate way to load the lib.
          // However, if the lib is loaded globally in the process, dart:ffi can find it.
          // We'll use a dynamic lookup or expect backend_juce.dart to be importable.
          final info = _setupBridgedNode(bridgeId, proc);
          if (info != null) {
            final startLoop = bridgedNodes.isEmpty;
            bridgedNodes[message.nodeId] = info;
            if (startLoop) runBridgedProcessing();
          }
        }
      }
    } else if (message is RemoveNodeMessage) {
      activeNodes.remove(message.nodeId);
      bridgedNodes.remove(message.nodeId);
    } else if (message is ProcessorMessage) {
      final proc = activeNodes[message.nodeId];
      if (proc != null) {
        proc.port.onMessage?.call(message.data);
      }
    } else if (message is ProcessQuantumMessage) {
      // Manual trigger for non-bridged nodes (e.g. offline context or mock tests)
      final proc = activeNodes[message.nodeId];
      if (proc != null && !bridgedNodes.containsKey(message.nodeId)) {
        final inputs = [message.inputData];
        final outputs = [List.generate(2, (_) => Float32List(quantumSize))];
        proc.process(inputs, outputs, {});
        config.mainSendPort.send(ProcessedQuantumMessage(message.nodeId, outputs[0]));
      }
    } else if (message is StopIsolateMessage) {
      for (final proc in activeNodes.values) {
        proc.dispose();
      }
      activeNodes.clear();
      bridgedNodes.clear();
      receivePort.close();
    }
  });
}

class _BridgedNodeInfo {
  final int nodeId;
  final WAWorkletProcessor processor;
  final MultiChannelNativeRingBuffer toIsolate;
  final MultiChannelNativeRingBuffer fromIsolate;
  final List<List<Float32List>> inputs;
  final List<List<Float32List>> outputs;

  _BridgedNodeInfo({
    required this.nodeId,
    required this.processor,
    required this.toIsolate,
    required this.fromIsolate,
    required this.inputs,
    required this.outputs,
  });
}

_BridgedNodeInfo? _setupBridgedNode(int bridgeId, WAWorkletProcessor processor) {
   // This requires backend_juce functions to be available in the isolate.
   // We import them at the top of the file.
   try {
     final capacity = backend.workletGetCapacity(bridgeId);
     if (capacity <= 0) return null;

     const numInputs = 2; // Fixed for now, or get from bridge
     const numOutputs = 2;

     final toChannels = <RingBuffer>[];
     for (int i = 0; i < numInputs; i++) {
        toChannels.add(NativeRingBuffer(
           capacity,
           backend.workletGetBufferPtr(bridgeId, 0, i),
           backend.workletGetReadPosPtr(bridgeId, 0, i),
           backend.workletGetWritePosPtr(bridgeId, 0, i),
        ));
     }

     final fromChannels = <RingBuffer>[];
     for (int i = 0; i < numOutputs; i++) {
        fromChannels.add(NativeRingBuffer(
           capacity,
           backend.workletGetBufferPtr(bridgeId, 1, i),
           backend.workletGetReadPosPtr(bridgeId, 1, i),
           backend.workletGetWritePosPtr(bridgeId, 1, i),
        ));
     }

     return _BridgedNodeInfo(
        nodeId: bridgeId,
        processor: processor,
        toIsolate: MultiChannelNativeRingBuffer(numInputs, capacity, toChannels),
        fromIsolate: MultiChannelNativeRingBuffer(numOutputs, capacity, fromChannels),
        inputs: [List.generate(numInputs, (_) => Float32List(quantumSize))],
        outputs: [List.generate(numOutputs, (_) => Float32List(quantumSize))],
     );
   } catch (e) {
     // Error handling in isolate
     return null;
   }
}
