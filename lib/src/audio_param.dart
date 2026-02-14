import 'dart:typed_data';

import 'enums.dart';
import 'backend/backend.dart' as backend;

/// Represents an AudioParam — a parameter of an AudioNode that can be
/// automated over time. Mirrors the Web Audio API AudioParam interface.
class WAParam {
  final int _nodeId;
  final String _paramName;
  final double _defaultValue;
  final double _minValue;
  final double _maxValue;

  double _value;

  /// Creates a new AudioParameter.
  WAParam({
    required int nodeId,
    required String paramName,
    double defaultValue = 0.0,
    double minValue = -3.4028235e38,
    double maxValue = 3.4028235e38,
    this.automationRate = WAAutomationRate.aRate,
  })  : _nodeId = nodeId,
        _paramName = paramName,
        _defaultValue = defaultValue,
        _minValue = minValue,
        _maxValue = maxValue,
        _value = defaultValue;

  // ---------------------------------------------------------------------------
  // Properties
  // ---------------------------------------------------------------------------

  /// The current value of the parameter.
  double get value => _value;
  set value(double v) {
    _value = v.clamp(_minValue, _maxValue);
    backend.paramSet(_nodeId, _paramName, _value);
  }

  /// The default value of the parameter (set at creation time).
  double get defaultValue => _defaultValue;

  /// The minimum allowable value for this parameter.
  double get minValue => _minValue;

  /// The maximum allowable value for this parameter.
  double get maxValue => _maxValue;

  /// Whether this parameter is a-rate (per-sample) or k-rate (per-block).
  WAAutomationRate automationRate;

  // ---------------------------------------------------------------------------
  // Automation Methods — P1
  // ---------------------------------------------------------------------------

  /// Schedules a parameter value change at the given time.
  WAParam setValueAtTime(double value, double startTime) {
    backend.paramSetAtTime(_nodeId, _paramName, value, startTime);
    return this;
  }

  /// Schedules a linear ramp to the given value, ending at [endTime].
  WAParam linearRampToValueAtTime(double value, double endTime) {
    backend.paramLinearRamp(_nodeId, _paramName, value, endTime);
    return this;
  }

  /// Schedules an exponential ramp to the given value, ending at [endTime].
  /// [value] must be positive.
  WAParam exponentialRampToValueAtTime(double value, double endTime) {
    assert(value > 0, 'exponentialRamp target must be positive');
    backend.paramExpRamp(_nodeId, _paramName, value, endTime);
    return this;
  }

  /// Starts an exponential approach to [target] at [startTime], with
  /// [timeConstant] controlling the rate (like an RC filter).
  WAParam setTargetAtTime(
      double target, double startTime, double timeConstant) {
    backend.paramSetTarget(
        _nodeId, _paramName, target, startTime, timeConstant);
    return this;
  }

  /// Cancels all scheduled parameter changes at or after [cancelTime].
  WAParam cancelScheduledValues(double cancelTime) {
    backend.paramCancel(_nodeId, _paramName, cancelTime);
    return this;
  }

  // ---------------------------------------------------------------------------
  // Automation Methods — P2
  // ---------------------------------------------------------------------------

  /// Schedules a curve of values over a duration.
  WAParam setValueCurveAtTime(
      Float32List values, double startTime, double duration) {
    backend.paramSetValueCurve(
      _nodeId,
      _paramName,
      values,
      startTime,
      duration,
    );
    return this;
  }

  /// Cancels scheduled changes at [cancelTime] and holds current interpolated
  /// value.
  WAParam cancelAndHoldAtTime(double cancelTime) {
    backend.paramCancelAndHold(_nodeId, _paramName, cancelTime);
    return this;
  }
}
