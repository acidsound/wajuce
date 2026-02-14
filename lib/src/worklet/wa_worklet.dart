import 'audio_isolate_stub.dart' if (dart.library.ffi) 'audio_isolate.dart';
import 'wa_worklet_processor.dart';
import 'wa_worklet_module.dart';
import '../backend/backend.dart' as backend;

/// The AudioWorklet interface. Mirrors Web Audio API AudioWorklet.
///
/// Manages processor registration and the audio processing isolate.
class WAWorklet {
  static final Set<WAWorklet> _instances = <WAWorklet>{};
  static bool _backendListenerInstalled = false;

  /// The native context ID this worklet belongs to.
  final int contextId;

  /// The sample rate of the audio context.
  final int sampleRate;
  final AudioIsolateManager _isolateManager = AudioIsolateManager();
  final Map<String, WAWorkletProcessor Function()> _factories = {};
  final Set<String> _registeredFactories = {};
  final Set<String> _loadedModules = {};
  final Set<int> _backendManagedNodes = {};
  bool _isolateStarted = false;
  final Map<int, void Function(dynamic)> _listeners = {};

  /// Creates a new AudioWorklet manager.
  WAWorklet({required this.contextId, this.sampleRate = 44100}) {
    _isolateManager.onProcessorMessage = (nodeId, data) {
      _listeners[nodeId]?.call(data);
    };

    _instances.add(this);
    if (!_backendListenerInstalled) {
      backend.onWebWorkletMessage = _dispatchBackendMessage;
      _backendListenerInstalled = true;
    }
  }

  /// Internal: Add a listener for a specific node.
  void addMessageListener(int nodeId, void Function(dynamic) callback) {
    _listeners[nodeId] = callback;
  }

  /// Internal: Remove a listener for a specific node.
  void removeMessageListener(int nodeId) {
    _listeners.remove(nodeId);
  }

  /// Register a processor factory by name.
  ///
  /// Deprecated: use [WAWorkletModules.define] in module files and call
  /// [addModule] from the context, mirroring Web Audio API usage.
  @Deprecated(
      'Use WAWorkletModules.define(...) in module files and then call addModule(...).')
  void registerProcessor(String name, WAWorkletProcessor Function() factory) {
    _registerProcessorFactory(name, factory);
  }

  /// Load a "module" — starts the audio isolate if needed and registers
  /// all pending processor factories.
  ///
  /// On web, this calls `audioWorklet.addModule(url)`.
  /// On native, this resolves the Dart module from [WAWorkletModules].
  Future<void> addModule(String moduleIdentifier) async {
    if (!_isolateStarted) {
      await _isolateManager.start(
        sampleRate: sampleRate,
        bufferSize: 128,
      );
      _isolateStarted = true;
    }

    // On web this forwards real module URLs to audioWorklet.addModule().
    await backend.webAddWorkletModule(contextId, moduleIdentifier);

    final moduleId = moduleIdentifier.trim();
    if (moduleId.isNotEmpty && _loadedModules.add(moduleId)) {
      final moduleLoader = WAWorkletModules.resolve(moduleId);
      if (moduleLoader != null) {
        final registrar = WAWorkletModuleRegistrar(_registerProcessorFactory);
        moduleLoader(registrar);
      }
    }

    // Register all factories once per isolate lifecycle.
    for (final entry in _factories.entries) {
      if (_registeredFactories.add(entry.key)) {
        _isolateManager.registerProcessor(entry.key, entry.value);
      }
    }
  }

  /// Check if a processor is registered.
  bool hasProcessor(String name) => _factories.containsKey(name);

  /// Create a node that runs a registered processor.
  int createNode(int nodeId, String processorName,
      {Map<String, double> paramDefaults = const {}, int? bridgeId}) {
    if (_factories.containsKey(processorName)) {
      _backendManagedNodes.remove(nodeId);
      _isolateManager.createNode(nodeId, processorName,
          paramDefaults: paramDefaults, bridgeId: bridgeId);
      return nodeId;
    }

    if (backend.workletSupportsExternalProcessors()) {
      _backendManagedNodes.add(nodeId);
      return nodeId;
    }

    throw StateError(
        'Processor "$processorName" is not registered. Import/define its module and call addModule(...) before createWorkletNode().');
  }

  /// Remove a processor node.
  void removeNode(int nodeId) {
    _listeners.remove(nodeId);
    if (_backendManagedNodes.remove(nodeId)) {
      return;
    }
    _isolateManager.removeNode(nodeId);
  }

  /// Send a message to a processor.
  void postMessage(int nodeId, dynamic data) {
    if (_backendManagedNodes.contains(nodeId)) {
      backend.workletPostMessage(nodeId, data);
      return;
    }
    _isolateManager.postMessage(nodeId, data);
  }

  /// Get the isolate manager for direct access.
  AudioIsolateManager get isolateManager => _isolateManager;

  /// Stop the audio isolate.
  Future<void> close() async {
    await _isolateManager.stop();
    _listeners.clear();
    _registeredFactories.clear();
    _loadedModules.clear();
    _backendManagedNodes.clear();
    _isolateStarted = false;

    _instances.remove(this);
    if (_instances.isEmpty) {
      backend.onWebWorkletMessage = null;
      _backendListenerInstalled = false;
    }
  }

  void _registerProcessorFactory(
      String name, WAWorkletProcessor Function() factory) {
    _factories[name] = factory;
  }

  static void _dispatchBackendMessage(int nodeId, dynamic data) {
    for (final worklet in _instances) {
      final listener = worklet._listeners[nodeId];
      if (listener != null) {
        listener(data);
        return;
      }
    }
  }
}
