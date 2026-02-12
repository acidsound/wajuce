// ignore_for_file: public_member_api_docs
/// Common messages and configuration for Audio Isolate system.
library;

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

class RegisterProcessorMessage extends AudioIsolateMessage {
  final String name;
  final WAWorkletProcessor Function() factory;
  RegisterProcessorMessage(this.name, this.factory);
}

class CreateNodeMessage extends AudioIsolateMessage {
  final int nodeId;
  final String processorName;
  final Map<String, double> paramDefaults;
  final int? bridgeId; 
  CreateNodeMessage(this.nodeId, this.processorName, this.paramDefaults, {this.bridgeId});
}

class RemoveNodeMessage extends AudioIsolateMessage {
  final int nodeId;
  RemoveNodeMessage(this.nodeId);
}

class ProcessorMessage extends AudioIsolateMessage {
  final int nodeId;
  final dynamic data;
  ProcessorMessage(this.nodeId, this.data);
}

class ProcessQuantumMessage extends AudioIsolateMessage {
  final int nodeId;
  final List<Float32List> inputData; 
  ProcessQuantumMessage(this.nodeId, this.inputData);
}

class ProcessedQuantumMessage extends AudioIsolateMessage {
  final int nodeId;
  final List<Float32List> outputData;
  ProcessedQuantumMessage(this.nodeId, this.outputData);
}

class PortMessage extends AudioIsolateMessage {
  final int nodeId;
  final dynamic data;
  PortMessage(this.nodeId, this.data);
}

class StopIsolateMessage extends AudioIsolateMessage {}

const int quantumSize = 128;
