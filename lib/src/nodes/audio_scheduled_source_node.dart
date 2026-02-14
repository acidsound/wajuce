import 'audio_node.dart';

/// Base class for source nodes with scheduled start/stop behavior.
/// Mirrors Web Audio API AudioScheduledSourceNode.
abstract class WAScheduledSourceNode extends WANode {
  /// Callback invoked when the source has ended.
  void Function()? onEnded;

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
}
