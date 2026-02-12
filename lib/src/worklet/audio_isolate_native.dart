// ignore_for_file: public_member_api_docs
/// Native-specific utilities for Audio Isolate.
library;

import 'dart:typed_data';
import 'dart:ffi' as ffi;
import 'wa_worklet_processor.dart';
import 'ring_buffer.dart';
import 'ring_buffer_native.dart';
import '../backend/backend.dart' as backend;

const int quantumSize = 128;

class BridgedNodeInfo {
  final int nodeId;
  final WAWorkletProcessor processor;
  final MultiChannelNativeRingBuffer toIsolate;
  final MultiChannelNativeRingBuffer fromIsolate;
  final List<List<Float32List>> inputs;
  final List<List<Float32List>> outputs;

  BridgedNodeInfo({
    required this.nodeId,
    required this.processor,
    required this.toIsolate,
    required this.fromIsolate,
    required this.inputs,
    required this.outputs,
  });
}

BridgedNodeInfo? setupBridgedNode(int bridgeId, WAWorkletProcessor processor) {
   try {
     final capacity = backend.workletGetCapacity(bridgeId);
     if (capacity <= 0) return null;

     const numInputs = 2; 
     const numOutputs = 2;

     final toChannels = <RingBuffer>[];
     for (int i = 0; i < numInputs; i++) {
        toChannels.add(NativeRingBuffer(
           capacity,
           ffi.Pointer<ffi.Float>.fromAddress(backend.workletGetBufferPtr(bridgeId, 0, i)),
           ffi.Pointer<ffi.Int32>.fromAddress(backend.workletGetReadPosPtr(bridgeId, 0, i)),
           ffi.Pointer<ffi.Int32>.fromAddress(backend.workletGetWritePosPtr(bridgeId, 0, i)),
        ));
     }

     final fromChannels = <RingBuffer>[];
     for (int i = 0; i < numOutputs; i++) {
        fromChannels.add(NativeRingBuffer(
           capacity,
           ffi.Pointer<ffi.Float>.fromAddress(backend.workletGetBufferPtr(bridgeId, 1, i)),
           ffi.Pointer<ffi.Int32>.fromAddress(backend.workletGetReadPosPtr(bridgeId, 1, i)),
           ffi.Pointer<ffi.Int32>.fromAddress(backend.workletGetWritePosPtr(bridgeId, 1, i)),
        ));
     }

     return BridgedNodeInfo(
        nodeId: bridgeId,
        processor: processor,
        toIsolate: MultiChannelNativeRingBuffer(numInputs, capacity, toChannels),
        fromIsolate: MultiChannelNativeRingBuffer(numOutputs, capacity, fromChannels),
        inputs: [List.generate(numInputs, (_) => Float32List(quantumSize))],
        outputs: [List.generate(numOutputs, (_) => Float32List(quantumSize))],
     );
   } catch (e) {
     return null;
   }
}
