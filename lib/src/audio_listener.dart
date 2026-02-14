import 'audio_param.dart';

/// Listener representation for spatial audio.
/// Mirrors Web Audio API AudioListener.
class WAAudioListener {
  /// Listener X position parameter.
  late final WAParam positionX;

  /// Listener Y position parameter.
  late final WAParam positionY;

  /// Listener Z position parameter.
  late final WAParam positionZ;

  /// Listener forward-vector X component parameter.
  late final WAParam forwardX;

  /// Listener forward-vector Y component parameter.
  late final WAParam forwardY;

  /// Listener forward-vector Z component parameter.
  late final WAParam forwardZ;

  /// Listener up-vector X component parameter.
  late final WAParam upX;

  /// Listener up-vector Y component parameter.
  late final WAParam upY;

  /// Listener up-vector Z component parameter.
  late final WAParam upZ;

  /// Creates an [WAAudioListener] bound to the backend listener node.
  WAAudioListener({required int nodeId}) {
    positionX =
        WAParam(nodeId: nodeId, paramName: 'positionX', defaultValue: 0);
    positionY =
        WAParam(nodeId: nodeId, paramName: 'positionY', defaultValue: 0);
    positionZ =
        WAParam(nodeId: nodeId, paramName: 'positionZ', defaultValue: 0);
    forwardX = WAParam(nodeId: nodeId, paramName: 'forwardX', defaultValue: 0);
    forwardY = WAParam(nodeId: nodeId, paramName: 'forwardY', defaultValue: 0);
    forwardZ = WAParam(nodeId: nodeId, paramName: 'forwardZ', defaultValue: -1);
    upX = WAParam(nodeId: nodeId, paramName: 'upX', defaultValue: 0);
    upY = WAParam(nodeId: nodeId, paramName: 'upY', defaultValue: 1);
    upZ = WAParam(nodeId: nodeId, paramName: 'upZ', defaultValue: 0);
  }

  /// Legacy convenience method.
  @Deprecated('Use positionX/positionY/positionZ AudioParam values instead.')
  void setPosition(double x, double y, double z) {
    positionX.value = x;
    positionY.value = y;
    positionZ.value = z;
  }

  /// Legacy convenience method.
  @Deprecated('Use forward*/up* AudioParam values instead.')
  void setOrientation(double forwardXValue, double forwardYValue,
      double forwardZValue, double upXValue, double upYValue, double upZValue) {
    forwardX.value = forwardXValue;
    forwardY.value = forwardYValue;
    forwardZ.value = forwardZValue;
    upX.value = upXValue;
    upY.value = upYValue;
    upZ.value = upZValue;
  }
}
