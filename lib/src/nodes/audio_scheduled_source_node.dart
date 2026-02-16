import 'dart:async';

import 'audio_node.dart';
import '../backend/backend.dart' as backend;

/// Base class for source nodes with scheduled start/stop behavior.
/// Mirrors Web Audio API AudioScheduledSourceNode.
abstract class WAScheduledSourceNode extends WANode {
  /// Callback invoked when the source has ended.
  void Function()? onEnded;
  Timer? _autoDisposeTimer;
  bool _hasEnded = false;
  double _scheduledStopTime = double.infinity;
  int _scheduleToken = 0;

  /// Creates a scheduled source node base.
  WAScheduledSourceNode({
    required super.nodeId,
    required super.contextId,
    super.channelCount,
    super.channelCountMode,
    super.channelInterpretation,
  });

  /// Start playback/generation at [when] (seconds, context timeline).
  void start([double when = 0]);

  /// Stop playback/generation at [when] (seconds, context timeline).
  void stop([double when = 0]);

  /// `true` if ended callback has already fired.
  bool get hasEnded => _hasEnded;

  /// Call from subclass `start(...)` implementations.
  void markStarted() {
    if (isDisposed) return;
    _hasEnded = false;
  }

  /// Call from subclass `stop(...)` implementations.
  /// Last-write-wins semantics: each call replaces prior end scheduling.
  void scheduleStopAutoDispose(double when) {
    if (isDisposed || _hasEnded) return;
    _scheduledStopTime = when;
    _scheduleAutoDispose(when);
  }

  /// Schedule auto-dispose for natural one-shot completion.
  void scheduleEstimatedNaturalEnd(double when) {
    if (isDisposed || _hasEnded) return;
    if (_scheduledStopTime.isFinite && _scheduledStopTime <= when) {
      return;
    }
    _scheduledStopTime = when;
    _scheduleAutoDispose(when);
  }

  /// Cancel pending auto-dispose task.
  void cancelAutoDisposeSchedule() {
    _autoDisposeTimer?.cancel();
    _autoDisposeTimer = null;
    _scheduleToken++;
  }

  void _scheduleAutoDispose(double when) {
    cancelAutoDisposeSchedule();
    final now = backend.contextGetTime(contextId);
    final safeWhen = when.isFinite ? when : now;
    final delta = safeWhen - now;
    final delayMs = delta <= 0 ? 0 : (delta * 1000).round();
    final token = _scheduleToken;
    _autoDisposeTimer = Timer(
        Duration(milliseconds: delayMs + 100), () => _finalizeEnded(token));
  }

  void _finalizeEnded(int token) {
    if (isDisposed || _hasEnded || token != _scheduleToken) {
      return;
    }
    _hasEnded = true;
    onEnded?.call();
    dispose();
  }

  @override
  void dispose() {
    if (isDisposed) return;
    cancelAutoDisposeSchedule();
    super.dispose();
  }
}
