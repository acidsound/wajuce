// Backend interface — platform-specific implementations
// Uses conditional imports to select JUCE FFI or Web Audio at build time
export 'backend_stub.dart'
    if (dart.library.ffi) 'backend_juce.dart'
    if (dart.library.js_interop) 'backend_web.dart';
