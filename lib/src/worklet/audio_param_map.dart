import '../audio_param.dart';

/// Minimal AudioParamMap-like wrapper for AudioWorkletNode.parameters.
class WAAudioParamMap {
  final Map<String, WAParam> _params;

  /// Creates an AudioParam map wrapper from [params].
  WAAudioParamMap([Map<String, WAParam> params = const {}])
      : _params = Map<String, WAParam>.from(params);

  /// Number of entries in the map.
  int get size => _params.length;

  /// Whether a parameter with [key] exists.
  bool has(String key) => _params.containsKey(key);

  /// Returns the parameter for [key], or `null` if absent.
  WAParam? get(String key) => _params[key];

  /// Iterable view of parameter names.
  Iterable<String> keys() => _params.keys;

  /// Iterable view of parameter values.
  Iterable<WAParam> values() => _params.values;

  /// Iterable view of parameter entries.
  Iterable<MapEntry<String, WAParam>> entries() => _params.entries;

  /// Runs [action] for each key/value pair.
  void forEach(void Function(String key, WAParam value) action) {
    _params.forEach(action);
  }
}
