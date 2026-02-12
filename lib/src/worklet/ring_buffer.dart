// ignore_for_file: public_member_api_docs
/// Ring buffer for lock-free audio data transfer between Dart isolates.
///
/// Used by the AudioWorklet system for main isolate ↔ audio isolate communication.
/// Implements a single-producer, single-consumer (SPSC) ring buffer using
/// a shared Float64List for the data and atomic int for read/write positions.
library;

import 'dart:typed_data';
import 'dart:math' as math;
import 'dart:ffi' as ffi;

/// A lock-free single-producer, single-consumer ring buffer for audio samples.
class RingBuffer {
  final int _capacity;
  final Float32List _buffer;
  int _readPos = 0;
  int _writePos = 0;

  /// Creates a ring buffer with the given capacity in samples.
  RingBuffer(int capacity)
      : _capacity = capacity,
        _buffer = Float32List(capacity);

  /// Number of samples available to read.
  int get available {
    final diff = _writePos - _readPos;
    return diff >= 0 ? diff : diff + _capacity;
  }

  /// Number of samples that can be written.
  int get space => _capacity - 1 - available;

  /// Write samples into the buffer. Returns number of samples actually written.
  int write(Float32List data, [int offset = 0, int? count]) {
    final n = math.min(count ?? data.length - offset, space);
    for (int i = 0; i < n; i++) {
      _buffer[(_writePos + i) % _capacity] = data[offset + i];
    }
    _writePos = (_writePos + n) % _capacity;
    return n;
  }

  /// Read samples from the buffer. Returns number of samples actually read.
  int read(Float32List output, [int offset = 0, int? count]) {
    final n = math.min(count ?? output.length - offset, available);
    for (int i = 0; i < n; i++) {
      output[offset + i] = _buffer[(_readPos + i) % _capacity];
    }
    _readPos = (_readPos + n) % _capacity;
    return n;
  }

  /// Clear the buffer.
  void clear() {
    _readPos = 0;
    _writePos = 0;
  }
}

/// Multi-channel ring buffer — wraps one [RingBuffer] per channel.
class MultiChannelRingBuffer {
  final List<RingBuffer> _channels;
  /// The number of channels.
  final int channelCount;
  /// The capacity of each channel in samples.
  final int capacity;

  /// Creates a new MultiChannelRingBuffer.
  MultiChannelRingBuffer({required this.channelCount, required this.capacity})
      : _channels = List.generate(channelCount, (_) => RingBuffer(capacity));

  /// Write interleaved or per-channel data.
  void writeChannel(int channel, Float32List data, [int offset = 0, int? count]) {
    if (channel >= 0 && channel < channelCount) {
      _channels[channel].write(data, offset, count);
    }
  }

  /// Read from a specific channel.
  int readChannel(int channel, Float32List output, [int offset = 0, int? count]) {
    if (channel >= 0 && channel < channelCount) {
      return _channels[channel].read(output, offset, count);
    }
    return 0;
  }

  /// Available samples (minimum across all channels).
  int get available {
    if (_channels.isEmpty) return 0;
    return _channels.map((c) => c.available).reduce(math.min);
  }

  /// Clear all channels.
  void clear() {
    for (final ch in _channels) {
      ch.clear();
    }
  }
}

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
    return diff >= 0 ? diff : diff + _capacity;
  }

  @override
  int get space {
    final w = _writePosPtr.value;
    final r = _readPosPtr.value;
    final diff = r - w - 1;
    return diff >= 0 ? diff : diff + _capacity;
  }

  @override
  int write(Float32List data, [int offset = 0, int? count]) {
    final n = math.min(count ?? data.length - offset, space);
    int w = _writePosPtr.value;
    for (int i = 0; i < n; i++) {
       _ptr[w] = data[offset + i];
       w = (w + 1) % _capacity;
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
      r = (r + 1) % _capacity;
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
    _channels.clear();
    _channels.addAll(channels);
  }
}
