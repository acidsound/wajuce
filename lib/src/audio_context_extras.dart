import 'dart:async';

import 'backend/backend.dart' as backend;

/// Timestamp pair for AudioContext output timing.
class WAAudioTimestamp {
  /// Timestamp on the AudioContext timeline, in seconds.
  final double contextTime;

  /// High-resolution clock timestamp, in milliseconds.
  final double performanceTime;

  /// Creates a new audio timestamp.
  const WAAudioTimestamp({
    required this.contextTime,
    required this.performanceTime,
  });
}

/// Audio sink info object.
class WAAudioSinkInfo {
  /// Sink type identifier (for example, `none` or backend-specific type).
  final String type;

  /// Creates a new sink info object.
  const WAAudioSinkInfo({this.type = 'none'});
}

/// Options for render capacity updates.
class WAAudioRenderCapacityOptions {
  /// Polling interval in seconds.
  final double updateInterval;

  /// Creates render-capacity polling options.
  const WAAudioRenderCapacityOptions({this.updateInterval = 1.0});
}

/// Render-capacity update payload.
class WAAudioRenderCapacityEvent {
  /// Event timestamp in AudioContext time.
  final double timestamp;

  /// Average render load ratio.
  final double averageLoad;

  /// Peak render load ratio.
  final double peakLoad;

  /// Ratio of underruns over the update window.
  final double underrunRatio;

  /// Creates a render-capacity event payload.
  const WAAudioRenderCapacityEvent({
    required this.timestamp,
    this.averageLoad = 0.0,
    this.peakLoad = 0.0,
    this.underrunRatio = 0.0,
  });
}

/// Minimal render-capacity API wrapper.
class WAAudioRenderCapacity {
  final int _contextId;
  Timer? _timer;

  /// Update callback.
  void Function(WAAudioRenderCapacityEvent event)? onUpdate;

  /// Creates a render-capacity wrapper bound to the given context ID.
  WAAudioRenderCapacity(this._contextId);

  /// Starts periodic update callbacks.
  void start(
      [WAAudioRenderCapacityOptions options =
          const WAAudioRenderCapacityOptions()]) {
    stop();
    final intervalMs = (options.updateInterval * 1000).clamp(50, 60000).toInt();
    _timer = Timer.periodic(Duration(milliseconds: intervalMs), (_) {
      onUpdate?.call(WAAudioRenderCapacityEvent(
        timestamp: backend.contextGetTime(_contextId),
      ));
    });
  }

  /// Stops periodic update callbacks.
  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}
