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

ffi.Pointer<ffi.Float> _toFloatPtr(dynamic rawPtr) {
  if (rawPtr is ffi.Pointer<ffi.Float>) {
    return rawPtr;
  }
  if (rawPtr is int) {
    return ffi.Pointer<ffi.Float>.fromAddress(rawPtr);
  }
  throw StateError(
      'Invalid worklet buffer pointer type: ${rawPtr.runtimeType}');
}

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
        _toFloatPtr(backend.workletGetBufferPtr(bridgeId, 0, i)),
        getReadPos: () => backend.workletGetReadPos(bridgeId, 0, i),
        getWritePos: () => backend.workletGetWritePos(bridgeId, 0, i),
        setReadPos: (value) => backend.workletSetReadPos(bridgeId, 0, i, value),
        setWritePos: (value) =>
            backend.workletSetWritePos(bridgeId, 0, i, value),
      ));
    }

    final fromChannels = <RingBuffer>[];
    for (int i = 0; i < numOutputs; i++) {
      fromChannels.add(NativeRingBuffer(
        capacity,
        _toFloatPtr(backend.workletGetBufferPtr(bridgeId, 1, i)),
        getReadPos: () => backend.workletGetReadPos(bridgeId, 1, i),
        getWritePos: () => backend.workletGetWritePos(bridgeId, 1, i),
        setReadPos: (value) => backend.workletSetReadPos(bridgeId, 1, i, value),
        setWritePos: (value) =>
            backend.workletSetWritePos(bridgeId, 1, i, value),
      ));
    }

    return BridgedNodeInfo(
      nodeId: bridgeId,
      processor: processor,
      toIsolate: MultiChannelNativeRingBuffer(numInputs, capacity, toChannels),
      fromIsolate:
          MultiChannelNativeRingBuffer(numOutputs, capacity, fromChannels),
      inputs: [List.generate(numInputs, (_) => Float32List(quantumSize))],
      outputs: [List.generate(numOutputs, (_) => Float32List(quantumSize))],
    );
  } catch (e) {
    return null;
  }
}
