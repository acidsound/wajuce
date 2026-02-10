import 'audio_buffer.dart';
import 'context.dart';

/// Offline rendering context for non-real-time audio processing.
/// Mirrors Web Audio API OfflineAudioContext.
///
/// Useful for testing, offline rendering, and audio export.
///
/// ```dart
/// final offline = WAOfflineContext(
///   numberOfChannels: 2,
///   length: 44100,  // 1 second
///   sampleRate: 44100,
/// );
///
/// final osc = offline.createOscillator();
/// osc.frequency.value = 440;
/// osc.connect(offline.destination);
/// osc.start();
///
/// final renderedBuffer = await offline.startRendering();
/// ```
class WAOfflineContext extends WAContext {
  final int _numberOfChannels;
  final int _length;
  final double _offlineSampleRate;

  WAOfflineContext({
    required int numberOfChannels,
    required int length,
    required double sampleRate,
  })  : _numberOfChannels = numberOfChannels,
        _length = length,
        _offlineSampleRate = sampleRate,
        super(sampleRate: sampleRate.toInt(), bufferSize: 512);

  /// Number of channels in the output.
  int get numberOfChannels => _numberOfChannels;

  /// Number of sample frames to render.
  int get length => _length;

  /// The sample rate specified at construction.
  double get offlineSampleRate => _offlineSampleRate;

  /// Start rendering and return the resulting AudioBuffer.
  Future<WABuffer> startRendering() async {
    // TODO: Implement offline rendering via backend
    throw UnimplementedError('Offline rendering not yet implemented');
  }
}
