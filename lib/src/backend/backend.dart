// ignore_for_file: public_member_api_docs
// Backend interface — platform-specific implementations
// Uses conditional imports to select native FFI or Web Audio at build time.
export 'backend_stub.dart'
    if (dart.library.ffi) 'backend_native.dart'
    if (dart.library.js_interop) 'backend_web.dart';
