// ignore_for_file: public_member_api_docs
/// Native-specific utilities for Audio Isolate.
library;

import 'dart:developer' as developer;
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

BridgedNodeInfo? setupBridgedNode(
    int contextId, int bridgeId, WAWorkletProcessor processor) {
  try {
    final capacity = backend.workletGetCapacity(contextId, bridgeId);
    if (capacity <= 0) return null;

    final numInputs = backend.workletGetInputChannelCount(contextId, bridgeId);
    final numOutputs =
        backend.workletGetOutputChannelCount(contextId, bridgeId);
    if (numInputs <= 0 || numOutputs <= 0) {
      developer.log(
        'WorkletBridge setup failed: invalid channel config '
        'ctx=$contextId bridge=$bridgeId in=$numInputs out=$numOutputs',
        name: 'wajuce',
      );
      return null;
    }

    final toChannels = <RingBuffer>[];
    for (int i = 0; i < numInputs; i++) {
      final bufferPtr = _toFloatPtr(
        backend.workletGetBufferPtr(contextId, bridgeId, 0, i),
      );
      if (bufferPtr.address == 0) {
        developer.log(
          'WorkletBridge setup failed: missing input buffer '
          'ctx=$contextId bridge=$bridgeId ch=$i',
          name: 'wajuce',
        );
        return null;
      }
      toChannels.add(NativeRingBuffer(
        capacity,
        bufferPtr,
        getReadPos: () => backend.workletGetReadPos(contextId, bridgeId, 0, i),
        getWritePos: () =>
            backend.workletGetWritePos(contextId, bridgeId, 0, i),
        setReadPos: (value) =>
            backend.workletSetReadPos(contextId, bridgeId, 0, i, value),
        setWritePos: (value) =>
            backend.workletSetWritePos(contextId, bridgeId, 0, i, value),
      ));
    }

    final fromChannels = <RingBuffer>[];
    for (int i = 0; i < numOutputs; i++) {
      final bufferPtr = _toFloatPtr(
        backend.workletGetBufferPtr(contextId, bridgeId, 1, i),
      );
      if (bufferPtr.address == 0) {
        developer.log(
          'WorkletBridge setup failed: missing output buffer '
          'ctx=$contextId bridge=$bridgeId ch=$i',
          name: 'wajuce',
        );
        return null;
      }
      fromChannels.add(NativeRingBuffer(
        capacity,
        bufferPtr,
        getReadPos: () => backend.workletGetReadPos(contextId, bridgeId, 1, i),
        getWritePos: () =>
            backend.workletGetWritePos(contextId, bridgeId, 1, i),
        setReadPos: (value) =>
            backend.workletSetReadPos(contextId, bridgeId, 1, i, value),
        setWritePos: (value) =>
            backend.workletSetWritePos(contextId, bridgeId, 1, i, value),
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
  } catch (e, stackTrace) {
    developer.log(
      'WorkletBridge setup failed: ctx=$contextId bridge=$bridgeId error=$e',
      name: 'wajuce',
      error: e,
      stackTrace: stackTrace,
    );
    return null;
  }
}
