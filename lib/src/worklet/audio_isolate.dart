library;

import 'dart:async';
import 'dart:developer' as developer;
import 'dart:isolate';
import 'dart:typed_data';

import 'wa_worklet_processor.dart';
import 'audio_isolate_messages.dart';
import 'audio_isolate_native.dart' as native;

/// Manages the audio processing isolate.
class AudioIsolateManager {
  /// Isolate instance.
  Isolate? _isolate;

  /// SendPort to communicate with the isolate.
  SendPort? _isolateSendPort;

  /// ReceivePort for messages from the isolate.
  ReceivePort? _mainReceivePort;
  final _readyCompleter = Completer<void>();

  /// Callback for messages received from processors.
  void Function(int nodeId, dynamic data)? onProcessorMessage;

  /// Callback fired when a processor indicates it has ended.
  void Function(int nodeId)? onNodeEnded;

  /// Callback fired after the isolate fully disposes a node.
  void Function(int nodeId)? onNodeRemoved;

  /// Starts the audio isolate.
  /// Starts the audio processing isolate.
  Future<void> start({
    required int sampleRate,
    int bufferSize = 128,
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
      } else if (message is NodeEndedMessage) {
        onNodeEnded?.call(message.nodeId);
      } else if (message is NodeRemovedMessage) {
        onNodeRemoved?.call(message.nodeId);
      }
    });

    return _readyCompleter.future;
  }

  /// Registers a processor factory with the isolate.
  void registerProcessor(String name, WAWorkletProcessor Function() factory) {
    _isolateSendPort?.send(RegisterProcessorMessage(name, factory));
  }

  /// Creates a processor node in the isolate.
  void createNode(int contextId, int nodeId, String processorName,
      {Map<String, double> paramDefaults = const {}, int? bridgeId}) {
    _isolateSendPort?.send(CreateNodeMessage(
        contextId, nodeId, processorName, paramDefaults,
        bridgeId: bridgeId));
  }

  /// Removes a processor node from the isolate.
  void removeNode(int nodeId) {
    _isolateSendPort?.send(RemoveNodeMessage(nodeId));
  }

  /// Sends a message to a processor.
  void postMessage(int nodeId, dynamic data) {
    _isolateSendPort?.send(ProcessorMessage(nodeId, data));
  }

  /// Stops the audio isolate and disposes resources.
  Future<void> stop() async {
    _isolateSendPort?.send(StopIsolateMessage());
    _isolate?.kill();
    _mainReceivePort?.close();
    _isolate = null;
  }
}

void _audioIsolateEntry(AudioIsolateConfig config) {
  final receivePort = ReceivePort();
  config.mainSendPort.send(receivePort.sendPort);

  final Map<String, WAWorkletProcessor Function()> processors = {};
  final Map<int, WAWorkletProcessor> activeNodes = {};
  final Map<int, native.BridgedNodeInfo> bridgedNodes = {};
  final quantumMicros = config.sampleRate > 0
      ? ((native.quantumSize * 1000000) / config.sampleRate).round()
      : 3000;
  final idleDelayMicros = quantumMicros > 1000 ? quantumMicros ~/ 4 : 250;
  late void Function() runBridgedProcessing;

  void scheduleNextBridgedProcessing({required bool processedData}) {
    if (bridgedNodes.isEmpty) return;
    if (processedData) {
      Future(runBridgedProcessing);
      return;
    }
    Future.delayed(
      Duration(microseconds: idleDelayMicros),
      runBridgedProcessing,
    );
  }

  runBridgedProcessing = () {
    if (bridgedNodes.isEmpty) return;

    bool dataProcessed = false;
    final deadNodeIds = <int>[];

    for (final entry in bridgedNodes.entries) {
      final nodeId = entry.key;
      final info = entry.value;
      final hasInputQuantum = info.toIsolate.available >= native.quantumSize;
      final hasOutputSpace = info.fromIsolate.space >= native.quantumSize;

      if (hasInputQuantum && hasOutputSpace) {
        for (int ch = 0; ch < info.toIsolate.channelCount; ch++) {
          final read = info.toIsolate
              .readChannel(ch, info.inputs[0][ch], 0, native.quantumSize);
          if (read < native.quantumSize) {
            for (int i = read; i < native.quantumSize; i++) {
              info.inputs[0][ch][i] = 0.0;
            }
          }
        }

        final keepAlive = info.processor.process(info.inputs, info.outputs, {});
        var bridgeFault = false;

        for (int ch = 0; ch < info.fromIsolate.channelCount; ch++) {
          final wrote = info.fromIsolate
              .writeChannel(ch, info.outputs[0][ch], 0, native.quantumSize);
          if (wrote < native.quantumSize) {
            bridgeFault = true;
            break;
          }
        }
        dataProcessed = true;

        if (bridgeFault) {
          developer.log(
            'WorkletBridge fault: partial output write '
            'node=$nodeId quantum=${native.quantumSize}',
            name: 'wajuce',
          );
          deadNodeIds.add(nodeId);
          config.mainSendPort.send(NodeEndedMessage(nodeId));
          continue;
        }

        if (!keepAlive) {
          deadNodeIds.add(nodeId);
          config.mainSendPort.send(NodeEndedMessage(nodeId));
        }
      }
    }

    for (final nodeId in deadNodeIds) {
      activeNodes.remove(nodeId)?.dispose();
      bridgedNodes.remove(nodeId);
    }

    if (bridgedNodes.isEmpty) return;
    scheduleNextBridgedProcessing(processedData: dataProcessed);
  };

  receivePort.listen((message) {
    if (message is RegisterProcessorMessage) {
      processors[message.name] = message.factory;
    } else if (message is CreateNodeMessage) {
      activeNodes.remove(message.nodeId)?.dispose();
      bridgedNodes.remove(message.nodeId);

      final factory = processors[message.processorName];
      if (factory != null) {
        final proc = factory();
        proc.init(message.paramDefaults);
        proc.port.bind((data) {
          config.mainSendPort.send(PortMessage(message.nodeId, data));
        });
        activeNodes[message.nodeId] = proc;

        if (message.bridgeId != null) {
          final bridgeInfo = native.setupBridgedNode(
            message.contextId,
            message.bridgeId!,
            proc,
          );
          if (bridgeInfo != null) {
            final startLoop = bridgedNodes.isEmpty;
            bridgedNodes[message.nodeId] = bridgeInfo;
            if (startLoop) runBridgedProcessing();
          }
        }
      }
    } else if (message is RemoveNodeMessage) {
      activeNodes.remove(message.nodeId)?.dispose();
      bridgedNodes.remove(message.nodeId);
      config.mainSendPort.send(NodeRemovedMessage(message.nodeId));
    } else if (message is ProcessorMessage) {
      final proc = activeNodes[message.nodeId];
      if (proc != null) {
        proc.port.onMessage?.call(message.data);
      }
    } else if (message is ProcessQuantumMessage) {
      final proc = activeNodes[message.nodeId];
      if (proc != null && !bridgedNodes.containsKey(message.nodeId)) {
        final inputs = [message.inputData];
        final outputs = [List.generate(2, (_) => Float32List(quantumSize))];
        final keepAlive = proc.process(inputs, outputs, {});
        config.mainSendPort
            .send(ProcessedQuantumMessage(message.nodeId, outputs[0]));
        if (!keepAlive) {
          proc.dispose();
          activeNodes.remove(message.nodeId);
          config.mainSendPort.send(NodeEndedMessage(message.nodeId));
        }
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
