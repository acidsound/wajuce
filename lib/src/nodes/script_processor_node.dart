import '../audio_buffer.dart';
import 'audio_node.dart';

/// Minimal shim for deprecated Web Audio AudioProcessingEvent.
@Deprecated('AudioProcessingEvent is deprecated in Web Audio 1.1.')
class WAAudioProcessingEvent {
  /// Input buffer snapshot.
  final WABuffer? inputBuffer;

  /// Output buffer snapshot.
  final WABuffer? outputBuffer;

  /// Event playback time in context timeline seconds.
  final double playbackTime;

  /// Creates an audio processing event payload.
  WAAudioProcessingEvent({
    this.inputBuffer,
    this.outputBuffer,
    required this.playbackTime,
  });
}

/// Minimal shim for deprecated Web Audio ScriptProcessorNode.
@Deprecated('ScriptProcessorNode is deprecated. Use AudioWorkletNode instead.')
class WAScriptProcessorNode extends WANode {
  /// Requested processing buffer size.
  final int bufferSize;

  /// Number of input channels.
  final int numberOfInputChannels;

  /// Number of output channels.
  final int numberOfOutputChannels;

  /// Callback invoked by platforms that still support script processing.
  void Function(WAAudioProcessingEvent event)? onaudioprocess;

  /// Creates a deprecated ScriptProcessorNode shim.
  WAScriptProcessorNode({
    required super.nodeId,
    required super.contextId,
    required this.bufferSize,
    required this.numberOfInputChannels,
    required this.numberOfOutputChannels,
  });

  @override
  int get numberOfInputs => numberOfInputChannels;

  @override
  int get numberOfOutputs => numberOfOutputChannels;
}
