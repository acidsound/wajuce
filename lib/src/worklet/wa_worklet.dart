import 'audio_isolate.dart';
import 'wa_worklet_processor.dart';

/// The AudioWorklet interface. Mirrors Web Audio API AudioWorklet.
///
/// Manages processor registration and the audio processing isolate.
class WAWorklet {
  /// The native context ID this worklet belongs to.
  final int contextId;
  /// The sample rate of the audio context.
  final int sampleRate;
  final AudioIsolateManager _isolateManager = AudioIsolateManager();
  final Map<String, WAWorkletProcessor Function()> _factories = {};
  bool _isolateStarted = false;

  /// Creates a new AudioWorklet manager.
  WAWorklet({required this.contextId, this.sampleRate = 44100});

  /// Register a processor factory by name.
  ///
  /// In Web Audio, `registerProcessor()` is called inside the worklet script.
  /// In wajuce, call this on the main thread before `addModule()`.
  void registerProcessor(String name, WAWorkletProcessor Function() factory) {
    _factories[name] = factory;
  }

  /// Load a "module" — starts the audio isolate if needed and registers
  /// all pending processor factories.
  ///
  /// On web, this calls `audioWorklet.addModule(url)`.
  /// On native, this starts the Dart audio isolate.
  Future<void> addModule(String moduleIdentifier) async {
    if (!_isolateStarted) {
      await _isolateManager.start(
        sampleRate: sampleRate,
        bufferSize: 128,
      );
      _isolateStarted = true;
    }

    // Register all factories
    for (final entry in _factories.entries) {
      _isolateManager.registerProcessor(entry.key, entry.value);
    }
  }

  /// Check if a processor is registered.
  bool hasProcessor(String name) => _factories.containsKey(name);

  /// Create a node that runs a registered processor.
  int createNode(int nodeId, String processorName,
      [Map<String, double> paramDefaults = const {}]) {
    _isolateManager.createNode(nodeId, processorName, paramDefaults);
    return nodeId;
  }

  /// Remove a processor node.
  void removeNode(int nodeId) {
    _isolateManager.removeNode(nodeId);
  }

  /// Send a message to a processor.
  void postMessage(int nodeId, dynamic data) {
    _isolateManager.postMessage(nodeId, data);
  }

  /// Set callback for messages from processors.
  set onProcessorMessage(void Function(int nodeId, dynamic data)? cb) {
    _isolateManager.onProcessorMessage = cb;
  }

  /// Get the isolate manager for direct access.
  AudioIsolateManager get isolateManager => _isolateManager;

  /// Stop the audio isolate.
  Future<void> close() async {
    await _isolateManager.stop();
    _isolateStarted = false;
  }
}
