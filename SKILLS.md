# Flutter FFI & C++ (JUCE) Integration Guidelines

This document summarizes troubleshooting experiences and best practices for building high-performance audio libraries using Flutter FFI and JUCE.

## 1. Native Build Strategy: Unity Build
For Apple platforms (iOS/macOS), the most reliable way to integrate JUCE into a Flutter FFI plugin is through a **Unity Build** file.

- **Problem**: CocoaPods does not natively support complex CMake-based projects like JUCE reliably within the plugin's `podspec`.
- **Solution**: Create a single `.mm` (Objective-C++) file that includes all required JUCE module `.mm` files and your engine's `.cpp` source.
- **Benefit**: All symbols are compiled into a single translation unit, avoiding linking errors and allowing easy passing of compiler flags via `pod_target_xcconfig`.

## 2. API Alignment & Naming
Transitioning from a prototype to a full implementation often reveals naming mismatches.

- **Naming Strategy**: Avoid lengthy names like `wajuce_oscillator_set_frequency`. Use concise, consistent prefixes for the C-API:
  - `oscSetFreq`
  - `ctxGetTime`
  - `bufSrcStart`
- **Mismatches**: Always verify that the Dart FFI lookup matches the exact symbol name in the C header. Use `dart analyze` to catch missing function calls across the Dart side.

## 3. Web Interop (Phase 6)
Web platforms should **not** use JUCE. Use `dart:js_interop` to bridge to the browser's native Web Audio API.

- **ID Mapping**: Maintain an integer-to-JSObject map in the web backend. This allows the Dart frontend to remain agnostic of the underlying object type (Native ID vs JS Reference).
- **Conditional Imports**: Use `export 'stub.dart' if (dart.library.js_interop) 'web.dart' if (dart.library.ffi) 'native.dart';` to ensure the correct backend is linked at build time.

## 4. Troubleshooting Edge Cases
- **SDK Compatibility**: New macOS/iOS SDKs (e.g., SDK 26.2) may break older JUCE versions (missing `NSUniquePtr`, `CFObjectHolder`). If native builds fail with "no template named...", check the SDK version compatibility.
- **FFI Memory**: When passing arrays to native code (e.g., `setCurve`), use `package:ffi` (`calloc` or `malloc`) and **always** free the memory after the call if the native side does not take ownership.
- **Sample Rate Types**: Web Audio API often uses `double` for sample rate, while JUCE might expect `int` in some C-API bridges. Use `num` in Dart to handle both flexibly.
