import 'audio_node.dart';
import '../audio_param.dart';
import '../audio_buffer.dart';
import '../backend/backend.dart' as backend;

/// Plays an AudioBuffer. Mirrors Web Audio API AudioBufferSourceNode.
class WABufferSourceNode extends WANode {
  late final WAParam playbackRate;
  late final WAParam detune;
  late final WAParam decay;
  WABuffer? _buffer;
  bool _loop = false;
  double loopStart = 0;
  double loopEnd = 0;

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

  /// Start playback at the given time.
  void start([double when = 0]) {
    backend.bufferSourceStart(nodeId, when);
  }

  /// Stop playback at the given time.
  void stop([double when = 0]) {
    backend.bufferSourceStop(nodeId, when);
  }
}
