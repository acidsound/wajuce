import 'dart:typed_data';

/// Base class for audio worklet processors.
/// Mirrors Web Audio API AudioWorkletProcessor.
///
/// Subclass this to create custom audio processing:
/// ```dart
/// class DX7Processor extends WAWorkletProcessor {
///   DX7Processor() : super(name: 'dx7-processor');
///
///   @override
///   bool process(
///     List<List<Float32List>> inputs,
///     List<List<Float32List>> outputs,
///     Map<String, Float32List> parameters,
///   ) {
///     final output = outputs[0]; // first output bus
///     final outL = output[0];    // left channel
///     final outR = output[1];    // right channel
///     for (int i = 0; i < outL.length; i++) {
///       final sample = synthesize(i);
///       outL[i] = sample;
///       outR[i] = sample;
///     }
///     return true; // keep alive
///   }
/// }
/// ```
abstract class WAWorkletProcessor {
  /// The name of the processor class as registered via WAContext.audioWorklet.
  final String name;

  /// Port for receiving messages from the main thread.
  late final WAProcessorPort port;

  /// Creates a new WorkletProcessor.
  WAWorkletProcessor({required this.name}) {
    port = WAProcessorPort();
  }

  /// Called for every render quantum (128 frames at 44.1kHz ≈ 2.9ms).
  ///
  /// [inputs] — `List<List<Float32List>>`: buses → channels → samples
  /// [outputs] — `List<List<Float32List>>`: buses → channels → samples
  /// [parameters] — AudioParam k-rate or a-rate values
  ///
  /// Return `true` to keep the processor alive, `false` to destroy it.
  bool process(
    List<List<Float32List>> inputs,
    List<List<Float32List>> outputs,
    Map<String, Float32List> parameters,
  );

  /// Called when the processor is created. Override to initialize state.
  /// [options] contains parameter defaults from the WAWorkletNode constructor.
  void init([Map<String, double> options = const {}]) {}

  /// Called when the processor is destroyed. Override to clean up.
  void dispose() {}
}

/// Port for communication from the audio thread back to main thread.
class WAProcessorPort {
  /// Callback for messages received from the main thread (main → audio).
  void Function(dynamic)? onMessage;

  /// Send a message to the main thread (audio → main).
  ///
  /// This is called from within the audio isolate. Messages are
  /// forwarded via SendPort to the main isolate.
  void postMessage(dynamic message) {
    // The audio isolate listens for these and forwards to main SendPort.
    // Injection happens in audio_isolate.dart when creating the processor.
    _sendCallback?.call(message);
  }

  /// Internal: set by the audio isolate to wire up the SendPort.
  void Function(dynamic)? _sendCallback;
  
  /// Used by the system to bind the postMessage callback.
  void bind(void Function(dynamic) callback) {
    _sendCallback = callback;
  }
}
