import 'audio_node.dart';
import '../audio_param.dart';

/// A simple gain (volume) node. Mirrors Web Audio API GainNode.
class WAGainNode extends WANode {
  late final WAParam gain;

  WAGainNode({
    required super.nodeId,
    required super.contextId,
  }) {
    gain = WAParam(
      nodeId: nodeId,
      paramName: 'gain',
      defaultValue: 1.0,
      minValue: -3.4028235e38,
      maxValue: 3.4028235e38,
    );
  }

  @override
  int get numberOfInputs => 1;

  @override
  int get numberOfOutputs => 1;
}
