import 'dart:typed_data';

/// Represents a buffer of audio sample data.
/// Mirrors Web Audio API AudioBuffer.
class WABuffer {
  final int _bufferId;
  final int _numberOfChannels;
  final int _length;
  final num _sampleRate;
  final List<Float32List> _channels;

  /// Creates a new audio buffer.
  WABuffer({
    int bufferId = 0,
    required int numberOfChannels,
    required int length,
    required num sampleRate,
    List<Float32List>? channels,
  })  : _bufferId = bufferId,
        _numberOfChannels = numberOfChannels,
        _length = length,
        _sampleRate = sampleRate,
        _channels = channels ??
            List.generate(numberOfChannels, (_) => Float32List(length));

  /// Internal buffer ID.
  int get bufferId => _bufferId;

  /// The sample rate of the buffer.
  num get sampleRate => _sampleRate;

  /// Number of frames in the buffer.
  int get length => _length;

  /// Duration in seconds.
  double get duration => _length / _sampleRate;

  /// Number of audio channels.
  int get numberOfChannels => _numberOfChannels;

  /// Get the data for a specific channel index.
  Float32List getChannelData(int channel) {
    assert(channel >= 0 && channel < _numberOfChannels);
    return _channels[channel];
  }

  /// Copy data from [source] into a region of channel [channelNumber].
  void copyToChannel(Float32List source, int channelNumber,
      [int bufferOffset = 0]) {
    final dest = _channels[channelNumber];
    final count = source.length.clamp(0, dest.length - bufferOffset);
    for (int i = 0; i < count; i++) {
      dest[bufferOffset + i] = source[i];
    }
  }

  /// Copy data from channel [channelNumber] into [destination].
  void copyFromChannel(Float32List destination, int channelNumber,
      [int bufferOffset = 0]) {
    final src = _channels[channelNumber];
    final count = destination.length.clamp(0, src.length - bufferOffset);
    for (int i = 0; i < count; i++) {
      destination[i] = src[bufferOffset + i];
    }
  }
}
