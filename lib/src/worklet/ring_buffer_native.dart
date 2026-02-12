// ignore_for_file: public_member_api_docs
/// Native implementation of RingBuffer using shared memory via FFI.
library;

import 'dart:typed_data';
import 'dart:math' as math;
import 'dart:ffi' as ffi;
import 'ring_buffer.dart';

/// A native implementation of [RingBuffer] that uses shard memory via FFI.
class NativeRingBuffer extends RingBuffer {
  final ffi.Pointer<ffi.Float> _ptr;
  final ffi.Pointer<ffi.Int32> _readPosPtr;
  final ffi.Pointer<ffi.Int32> _writePosPtr;

  NativeRingBuffer(
      super.capacity, this._ptr, this._readPosPtr, this._writePosPtr);

  @override
  int get available {
    final w = _writePosPtr.value;
    final r = _readPosPtr.value;
    final diff = w - r;
    return diff >= 0 ? diff : diff + capacity;
  }

  @override
  int get space {
    final w = _writePosPtr.value;
    final r = _readPosPtr.value;
    final diff = r - w - 1;
    return diff >= 0 ? diff : diff + capacity;
  }

  @override
  int write(Float32List data, [int offset = 0, int? count]) {
    final n = math.min(count ?? data.length - offset, space);
    int w = _writePosPtr.value;
    for (int i = 0; i < n; i++) {
       _ptr[w] = data[offset + i];
       w = (w + 1) % capacity;
    }
    _writePosPtr.value = w;
    return n;
  }

  @override
  int read(Float32List output, [int offset = 0, int? count]) {
    final n = math.min(count ?? output.length - offset, available);
    int r = _readPosPtr.value;
    for (int i = 0; i < n; i++) {
      output[offset + i] = _ptr[r];
      r = (r + 1) % capacity;
    }
    _readPosPtr.value = r;
    return n;
  }

  @override
  void clear() {
    _readPosPtr.value = 0;
    _writePosPtr.value = 0;
  }
}

/// Multi-channel native ring buffer.
class MultiChannelNativeRingBuffer extends MultiChannelRingBuffer {
  MultiChannelNativeRingBuffer(int channelCount, int capacity, List<RingBuffer> channels)
      : super(channelCount: channelCount, capacity: capacity) {
    this.channels.clear();
    this.channels.addAll(channels);
  }
}
