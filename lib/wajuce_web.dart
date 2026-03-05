import 'package:flutter_web_plugins/flutter_web_plugins.dart';

/// Web plugin registrant for `wajuce`.
///
/// The package's Web Audio implementation is pure Dart/JS interop, so the
/// registrar hook is intentionally a no-op.
class WajuceWebPlugin {
  /// Registers the web implementation with Flutter.
  static void registerWith(Registrar registrar) {}
}
