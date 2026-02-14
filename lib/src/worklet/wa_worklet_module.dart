import 'wa_worklet_processor.dart';

/// Loader callback invoked by [WAWorklet.addModule].
typedef WAWorkletModuleLoader = void Function(
    WAWorkletModuleRegistrar registrar);

/// Registrar passed to module loaders.
///
/// A module should call [registerProcessor] for each processor it provides.
class WAWorkletModuleRegistrar {
  final void Function(String name, WAWorkletProcessor Function() factory)
      _register;

  /// Creates a registrar used by the runtime to collect processors.
  WAWorkletModuleRegistrar(this._register);

  /// Registers a processor factory exposed by the module.
  void registerProcessor(String name, WAWorkletProcessor Function() factory) {
    _register(name, factory);
  }
}

/// Global registry for Dart-side AudioWorklet modules.
///
/// Importing a module file should call [define] once at top-level to register
/// how that module maps processor names to factories.
class WAWorkletModules {
  static final Map<String, WAWorkletModuleLoader> _loaders = {};

  /// Static utility holder. Not intended to be instantiated.
  WAWorkletModules._();

  /// Defines a module loader for a module identifier (e.g. a module URL or id).
  ///
  /// Returns `false` when the identifier is empty or already defined and
  /// [replace] is `false`.
  static bool define(String moduleIdentifier, WAWorkletModuleLoader loader,
      {bool replace = false}) {
    final id = moduleIdentifier.trim();
    if (id.isEmpty) return false;
    if (!replace && _loaders.containsKey(id)) return false;
    _loaders[id] = loader;
    return true;
  }

  /// Resolves a module loader by identifier.
  ///
  /// Also accepts URL-like identifiers by trying their basename and basename
  /// without extension.
  static WAWorkletModuleLoader? resolve(String moduleIdentifier) {
    final id = moduleIdentifier.trim();
    if (id.isEmpty) return null;
    final exact = _loaders[id];
    if (exact != null) return exact;

    // Allow URL-style addModule values to resolve by basename.
    final noFragment = id.split('#').first;
    final noQuery = noFragment.split('?').first;
    final segments = noQuery.split('/');
    final basename = segments.isEmpty ? noQuery : segments.last;
    if (basename.isEmpty) return null;

    final basenameExact = _loaders[basename];
    if (basenameExact != null) return basenameExact;

    final dotIndex = basename.lastIndexOf('.');
    if (dotIndex > 0) {
      final withoutExt = basename.substring(0, dotIndex);
      return _loaders[withoutExt];
    }
    return null;
  }
}
