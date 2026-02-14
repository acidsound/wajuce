import 'audio_node.dart';
import '../audio_buffer.dart';
import '../backend/backend.dart' as backend;

/// Convolution processor node, commonly used for impulse-response reverb.
/// Mirrors Web Audio API ConvolverNode.
class WAConvolverNode extends WANode {
  WABuffer? _buffer;
  bool _normalize = true;

  /// Creates a new ConvolverNode.
  WAConvolverNode({
    required super.nodeId,
    required super.contextId,
  });

  @override
  int get numberOfInputs => 1;

  @override
  int get numberOfOutputs => 1;

  /// Impulse response buffer.
  WABuffer? get buffer => _buffer;
  set buffer(WABuffer? value) {
    _buffer = value;
    backend.convolverSetBuffer(nodeId, value);
  }

  /// Whether to apply equal-power normalization to the impulse response.
  bool get normalize => _normalize;
  set normalize(bool value) {
    _normalize = value;
    backend.convolverSetNormalize(nodeId, value);
  }
}
