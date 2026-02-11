import 'audio_node.dart';
import '../audio_param.dart';

/// A simple stereo panner. Mirrors Web Audio API StereoPannerNode.
class WAStereoPannerNode extends WANode {
  /// The pan position, where -1 is L and +1 is R.
  late final WAParam pan;

  /// Creates a new StereoPannerNode.
  WAStereoPannerNode({
    required super.nodeId,
    required super.contextId,
  }) {
    pan = WAParam(
      nodeId: nodeId,
      paramName: 'pan',
      defaultValue: 0.0,
      minValue: -1.0,
      maxValue: 1.0,
    );
  }

  @override
  int get numberOfInputs => 1;

  @override
  int get numberOfOutputs => 1;
}
