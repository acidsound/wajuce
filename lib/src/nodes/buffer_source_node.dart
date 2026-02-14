import 'audio_scheduled_source_node.dart';
import '../audio_param.dart';
import '../audio_buffer.dart';
import '../backend/backend.dart' as backend;

/// Plays an AudioBuffer. Mirrors Web Audio API AudioBufferSourceNode.
class WABufferSourceNode extends WAScheduledSourceNode {
  /// The rate at which the buffer is played back.
  late final WAParam playbackRate;

  /// The detuning value in cents.
  late final WAParam detune;

  /// Experimental: decay parameter for grain/buffer sources.
  late final WAParam decay;
  WABuffer? _buffer;
  bool _loop = false;

  double _loopStart = 0;
  double _loopEnd = 0;

  /// Creates a new BufferSourceNode.
  WABufferSourceNode({
    required super.nodeId,
    required super.contextId,
  }) {
    playbackRate = WAParam(
      nodeId: nodeId,
      paramName: 'playbackRate',
      defaultValue: 1.0,
      minValue: -3.4028235e38,
      maxValue: 3.4028235e38,
    );
    detune = WAParam(
      nodeId: nodeId,
      paramName: 'detune',
      defaultValue: 0.0,
      minValue: -153600.0,
      maxValue: 153600.0,
    );
    decay = WAParam(
      nodeId: nodeId,
      paramName: 'decay',
      defaultValue: 0.5,
      minValue: 0.001,
      maxValue: 10.0,
    );
  }

  @override
  int get numberOfInputs => 0;

  @override
  int get numberOfOutputs => 1;

  /// The audio buffer to play.
  WABuffer? get buffer => _buffer;
  set buffer(WABuffer? buf) {
    _buffer = buf;
    if (buf != null) {
      backend.bufferSourceSetBuffer(nodeId, buf);
    }
  }

  /// Whether to loop playback.
  bool get loop => _loop;
  set loop(bool v) {
    _loop = v;
    backend.bufferSourceSetLoop(nodeId, v);
  }

  /// Start time for looping, in seconds.
  double get loopStart => _loopStart;
  set loopStart(double value) {
    _loopStart = value;
    backend.bufferSourceSetLoopStart(nodeId, value);
  }

  /// End time for looping, in seconds.
  double get loopEnd => _loopEnd;
  set loopEnd(double value) {
    _loopEnd = value;
    backend.bufferSourceSetLoopEnd(nodeId, value);
  }

  /// Start playback at [when].
  @override
  void start([double when = 0]) {
    backend.bufferSourceStart(nodeId, when);
  }

  /// Start playback at [when], with optional [offset] and [duration].
  void startAt(double when, [double offset = 0, double? duration]) {
    backend.bufferSourceStartAdvanced(nodeId, when, offset, duration);
  }

  /// Stop playback at the given time.
  @override
  void stop([double when = 0]) {
    backend.bufferSourceStop(nodeId, when);
  }
}
