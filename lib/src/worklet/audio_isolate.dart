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
  CreateNodeMessage(this.nodeId, this.processorName, this.parameterDefaults);
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
      [Map<String, double> paramDefaults = const {}]) {
    _isolateSendPort?.send(
        CreateNodeMessage(nodeId, processorName, paramDefaults));
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

  /// The render quantum size (Web Audio spec: 128 samples).
  const quantumSize = 128;

  receivePort.listen((message) {
    if (message is RegisterProcessorMessage) {
      processors[message.name] = message.factory;
    } else if (message is CreateNodeMessage) {
      final factory = processors[message.processorName];
      if (factory != null) {
        final proc = factory();
        proc.init(message.parameterDefaults);
        activeNodes[message.nodeId] = proc;
      }
    } else if (message is RemoveNodeMessage) {
      final proc = activeNodes.remove(message.nodeId);
      proc?.dispose();
    } else if (message is ProcessorMessage) {
      final proc = activeNodes[message.nodeId];
      if (proc != null) {
        proc.port.onMessage?.call(message.data);
      }
    } else if (message is ProcessQuantumMessage) {
      final proc = activeNodes[message.nodeId];
      if (proc != null) {
        // Prepare inputs/outputs in Web Audio spec format
        final inputs = [message.inputData];
        final outputs = [
          List.generate(
              2, (_) => Float32List(quantumSize)) // stereo output
        ];
        final parameters = <String, Float32List>{};

        final keepAlive = proc.process(inputs, outputs, parameters);

        config.mainSendPort.send(
            ProcessedQuantumMessage(message.nodeId, outputs[0]));

        if (!keepAlive) {
          activeNodes.remove(message.nodeId);
          proc.dispose();
        }
      }
    } else if (message is StopIsolateMessage) {
      for (final proc in activeNodes.values) {
        proc.dispose();
      }
      activeNodes.clear();
      receivePort.close();
    }
  });
}
