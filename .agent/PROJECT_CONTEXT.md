# wajuce Project Context

## Overview

`wajuce` provides Web Audio API 1.1-compatible Dart APIs for Flutter.

- Native: iPlug2-backed C++ WebAudio runtime via Dart FFI.
- Web: browser Web Audio API via `dart:js_interop`.

## Current Native Architecture

- C ABI: `src/wajuce.h`
- Native runtime: `native/engine/Source/WAIPlugEngine.cpp`
- Parameter automation: `native/engine/Source/ParamAutomation.h`
- Worklet bridge buffers: `native/engine/Source/RingBuffer.h`
- Runtime dependency: `native/engine/vendor/iPlug2`

The native engine owns a WebAudio-oriented render graph directly. It is not a
translation layer from another framework graph.

## Validation Direction

Use `wajuce_context_render(...)` for deterministic native block/offline tests.
Live device tests are secondary because they are affected by hardware format,
driver buffer size, and permissions.

## Backend Switch

```dart
export 'backend_stub.dart'
    if (dart.library.ffi) 'backend_native.dart'
    if (dart.library.js_interop) 'backend_web.dart';
```

## Submodule Setup

```zsh
git submodule update --init --recursive native/engine/vendor/iPlug2
```
