import 'audio_node.dart';
import '../audio_param.dart';
import '../enums.dart';
import '../backend/backend.dart' as backend;

/// 3D spatial panner node.
/// Mirrors Web Audio API PannerNode.
class WAPannerNode extends WANode {
  /// Source X position parameter.
  late final WAParam positionX;

  /// Source Y position parameter.
  late final WAParam positionY;

  /// Source Z position parameter.
  late final WAParam positionZ;

  /// Source orientation X parameter.
  late final WAParam orientationX;

  /// Source orientation Y parameter.
  late final WAParam orientationY;

  /// Source orientation Z parameter.
  late final WAParam orientationZ;

  WAPanningModel _panningModel = WAPanningModel.hrtf;
  WADistanceModel _distanceModel = WADistanceModel.inverse;
  double _refDistance = 1.0;
  double _maxDistance = 10000.0;
  double _rolloffFactor = 1.0;
  double _coneInnerAngle = 360.0;
  double _coneOuterAngle = 360.0;
  double _coneOuterGain = 0.0;

  /// Creates a new PannerNode.
  WAPannerNode({
    required super.nodeId,
    required super.contextId,
  }) {
    positionX = WAParam(
      nodeId: nodeId,
      paramName: 'positionX',
      defaultValue: 0.0,
    );
    positionY = WAParam(
      nodeId: nodeId,
      paramName: 'positionY',
      defaultValue: 0.0,
    );
    positionZ = WAParam(
      nodeId: nodeId,
      paramName: 'positionZ',
      defaultValue: 0.0,
    );
    orientationX = WAParam(
      nodeId: nodeId,
      paramName: 'orientationX',
      defaultValue: 1.0,
    );
    orientationY = WAParam(
      nodeId: nodeId,
      paramName: 'orientationY',
      defaultValue: 0.0,
    );
    orientationZ = WAParam(
      nodeId: nodeId,
      paramName: 'orientationZ',
      defaultValue: 0.0,
    );
  }

  @override
  int get numberOfInputs => 1;

  @override
  int get numberOfOutputs => 1;

  /// Panning algorithm mode.
  WAPanningModel get panningModel => _panningModel;
  set panningModel(WAPanningModel model) {
    _panningModel = model;
    backend.pannerSetPanningModel(nodeId, model.index);
  }

  /// Distance attenuation model.
  WADistanceModel get distanceModel => _distanceModel;
  set distanceModel(WADistanceModel model) {
    _distanceModel = model;
    backend.pannerSetDistanceModel(nodeId, model.index);
  }

  /// Reference distance for distance attenuation.
  double get refDistance => _refDistance;
  set refDistance(double value) {
    _refDistance = value;
    backend.pannerSetRefDistance(nodeId, value);
  }

  /// Maximum distance for attenuation calculations.
  double get maxDistance => _maxDistance;
  set maxDistance(double value) {
    _maxDistance = value;
    backend.pannerSetMaxDistance(nodeId, value);
  }

  /// Rolloff factor for distance attenuation.
  double get rolloffFactor => _rolloffFactor;
  set rolloffFactor(double value) {
    _rolloffFactor = value;
    backend.pannerSetRolloffFactor(nodeId, value);
  }

  /// Inner cone angle in degrees.
  double get coneInnerAngle => _coneInnerAngle;
  set coneInnerAngle(double value) {
    _coneInnerAngle = value;
    backend.pannerSetConeInnerAngle(nodeId, value);
  }

  /// Outer cone angle in degrees.
  double get coneOuterAngle => _coneOuterAngle;
  set coneOuterAngle(double value) {
    _coneOuterAngle = value;
    backend.pannerSetConeOuterAngle(nodeId, value);
  }

  /// Outer cone gain multiplier.
  double get coneOuterGain => _coneOuterGain;
  set coneOuterGain(double value) {
    _coneOuterGain = value;
    backend.pannerSetConeOuterGain(nodeId, value);
  }

  /// Legacy convenience method.
  @Deprecated('Use positionX/positionY/positionZ AudioParam values instead.')
  void setPosition(double x, double y, double z) {
    positionX.value = x;
    positionY.value = y;
    positionZ.value = z;
  }

  /// Legacy convenience method.
  @Deprecated(
      'Use orientationX/orientationY/orientationZ AudioParam values instead.')
  void setOrientation(double x, double y, double z) {
    orientationX.value = x;
    orientationY.value = y;
    orientationZ.value = z;
  }
}
